#!/usr/bin/env python3
"""Quota Antigravity (Google AI Pro) — pourcentage par modèle et fenêtre.

    antigravity_service.py [--force]

Une ligne JSON sur stdout, rien d'autre. Deux sources, dans cet ordre :

1. L'API Code Assist (`cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`),
   la même que Gemini CLI. Elle rend, par modèle, une fraction restante et l'heure
   de remise à zéro : c'est la seule mesure réelle du quota. L'authentification
   est le jeton OAuth que le CLI `agy` range dans le trousseau (libsecret,
   service=gemini / username=antigravity) ; il n'est ni copié ni journalisé.
   Il expire au bout d'une heure environ et le CLI ne le renouvelle qu'en
   s'exécutant — d'où le repli.

2. Les logs du CLI (`~/.gemini/antigravity/log`, `~/.gemini/antigravity-cli/log`),
   en lecture seule. On y lit « RESOURCE_EXHAUSTED … Resets in 151h24m24s » quand
   le quota est atteint, et on en déduit une échéance. Ce n'est pas un
   pourcentage : c'est « bloqué jusqu'à telle heure », et l'absence de 429 veut
   dire « aucun refus journalisé », pas « quota mesuré ».

Le widget affiche la fenêtre la plus contrainte en grand, l'autre en dessous.
Deux fenêtres coexistent : une courte (~5 h) pour Gemini, une hebdomadaire pour
Claude et GPT-OSS — c'est l'API qui les distingue par leur heure de reset, pas
des noms que les logs donneraient.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CACHE_FILE = BASE_DIR / "antigravity_cache.json"

sys.path.insert(0, str(BASE_DIR))
import llm_contrat  # noqa: E402

API_QUOTA = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
API_ASSIST = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
AGENT = "antigravity/1.10.0"
TTL = 120
TIMEOUT = 20
SEUIL_ALERTE = 0.05      # 5 % restants : on prévient avant le blocage

LOG_DIRS = [
    Path(os.path.expanduser("~/.gemini/antigravity/log")),
    Path(os.path.expanduser("~/.gemini/antigravity-cli/log")),
]

# « E1101 09:51:02.966262   72205 errorreport.go:224] … Resets in 151h24m24s. »
LIGNE = re.compile(r"^([IWEF])(\d{2})(\d{2}) (\d{2}):(\d{2}):(\d{2})\.\d+\s+\d+\s+\S+\]\s*(.*)$")
DELAI = re.compile(r"Resets in (?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?")
QUOTA = "Individual quota reached"

FAMILLES = (("claude", "Claude"), ("gemini", "Gemini"), ("gpt", "GPT"))


# ---------------------------------------------------------------- cache

def lire_cache():
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def ecrire_cache(donnees):
    try:
        CACHE_FILE.write_text(json.dumps(donnees, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError:
        pass


# ---------------------------------------------------------------- source 1 : API

def jeton():
    """Jeton OAuth rangé par `agy` dans le trousseau — jamais écrit sur disque.

    Aucun repli sur un fichier : `~/.gemini/oauth_creds.json` date de janvier et
    son rafraîchissement échoue (`invalid_client`), il ne sert plus à rien.
    """
    try:
        brut = subprocess.run(
            ["secret-tool", "lookup", "service", "gemini", "username", "antigravity"],
            capture_output=True, text=True, timeout=10).stdout.strip()
        charge = json.loads(brut)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None, "jeton absent du trousseau"
    bloc = charge.get("token") or {}
    acces = bloc.get("access_token")
    if not acces:
        return None, "jeton sans access_token"
    echeance = bloc.get("expiry") or ""
    if echeance:
        try:
            quand = dt.datetime.fromisoformat(echeance.replace("Z", "+00:00"))
            if quand <= dt.datetime.now(dt.timezone.utc):
                return None, "jeton expiré (relancer agy le renouvelle)"
        except ValueError:
            pass
    return acces, None


def poster(url, corps, jeton_acces):
    requete = urllib.request.Request(
        url, data=json.dumps(corps).encode(),
        headers={"Authorization": "Bearer " + jeton_acces,
                 "Content-Type": "application/json",
                 "User-Agent": AGENT},
        method="POST")
    with urllib.request.urlopen(requete, timeout=TIMEOUT) as reponse:
        return json.loads(reponse.read().decode("utf-8", errors="replace"))


def famille(model_id):
    for prefixe, nom in FAMILLES:
        if model_id.startswith(prefixe):
            return nom
    return "autres"


def depuis_api():
    """Compartiments par fenêtre, ou (None, raison) si l'API n'est pas joignable."""
    jeton_acces, raison = jeton()
    if not jeton_acces:
        return None, raison
    try:
        assist = poster(API_ASSIST, {"metadata": {"pluginType": "GEMINI"}}, jeton_acces)
        projet = assist.get("cloudaicompanionProject")
        if not projet:
            return None, "projet Code Assist introuvable"
        quota = poster(API_QUOTA, {"project": projet}, jeton_acces)
    except urllib.error.HTTPError as erreur:
        return None, f"API quota : HTTP {erreur.code}"
    except (urllib.error.URLError, ValueError) as erreur:
        return None, f"API quota : {erreur}"

    partages = {}
    for compartiment in quota.get("buckets") or []:
        remise = compartiment.get("resetTime")
        if not remise:
            continue                      # modèles sans quota horaire : toujours libres
        partages.setdefault(remise, []).append({
            "model": str(compartiment.get("modelId") or "?"),
            "reste": round(float(compartiment.get("remainingFraction") or 0), 4),
        })
    if not partages:
        return None, "aucun compartiment quota dans la réponse"

    fenetres = []
    for remise, modeles in partages.items():
        try:
            reset_at = int(dt.datetime.fromisoformat(remise.replace("Z", "+00:00")).timestamp())
        except ValueError:
            continue
        pire = min(m["reste"] for m in modeles)
        familles = sorted({famille(m["model"]) for m in modeles
                           if m["reste"] <= pire + 1e-9})
        fenetres.append({
            "reset_at": reset_at,
            "reste": pire,
            "familles": familles,
            "models": modeles,
        })
    if not fenetres:
        return None, "fenêtres illisibles"

    maintenant = time.time()
    for fenetre in fenetres:
        # Une fenêtre qui se rouvre dans plus de deux jours est l'hebdomadaire ;
        # les libellés viennent de la durée, pas d'un nom qu'on supposerait.
        fenetre["kind"] = "week" if fenetre["reset_at"] - maintenant > 48 * 3600 else "session"
        fenetre["label"] = "hebdo" if fenetre["kind"] == "week" else "5 h"
    fenetres.sort(key=lambda f: (f["reste"], -f["reset_at"]))
    return fenetres, None


# ---------------------------------------------------------------- source 2 : logs

def annee_du_fichier(chemin):
    """cli-20261105_145455.log → 2026 ; sinon l'année de modification."""
    m = re.search(r"(20\d{2})(\d{2})(\d{2})_", chemin.name)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    t = time.localtime(chemin.stat().st_mtime)
    return t.tm_year, t.tm_mon, t.tm_mday


def evenements(chemin):
    """[(instant, secondes_annoncées, texte)] pour chaque 429 lisible du fichier."""
    annee, mois_fichier, jour_fichier = annee_du_fichier(chemin)
    trouves = []
    try:
        with chemin.open("r", encoding="utf-8", errors="replace") as fh:
            for ligne in fh:
                if QUOTA not in ligne:
                    continue
                m = LIGNE.match(ligne)
                if not m:
                    continue
                _, mois, jour, heure, minute, seconde, reste = m.groups()
                d = DELAI.search(reste)
                if not d:
                    continue
                secondes = (int(d.group(1) or 0) * 3600
                            + int(d.group(2) or 0) * 60
                            + int(d.group(3) or 0))
                if secondes <= 0:
                    continue
                # Un fichier peut chevaucher le jour de l'an : si la date de la
                # ligne précède celle du fichier, c'est l'année suivante.
                annee_ligne = annee
                if (int(mois), int(jour)) < (mois_fichier, jour_fichier):
                    annee_ligne += 1
                try:
                    instant = time.mktime((annee_ligne, int(mois), int(jour),
                                           int(heure), int(minute), int(seconde), 0, 0, -1))
                except (OverflowError, ValueError):
                    continue
                trouves.append((instant, secondes, ligne.strip()[:200]))
    except OSError:
        pass
    return trouves


def collecter():
    tous = []
    for dossier in LOG_DIRS:
        if not dossier.is_dir():
            continue
        for fichier in sorted(dossier.glob("*.log")):
            tous.extend((instant, secondes, texte, fichier)
                        for instant, secondes, texte in evenements(fichier))
    return tous


def depuis_logs():
    now = time.time()
    tous = collecter()
    if not tous:
        return {"ok": True, "provider": "antigravity", "state": "free", "windows": [],
                "source": "logs", "detail": "aucun épuisement journalisé"}

    # Le dernier épuisement de chaque fenêtre fait foi.
    fenetres = {}
    for instant, secondes, texte, fichier in tous:
        genre = "session" if secondes < 24 * 3600 else "week"
        if genre not in fenetres or instant > fenetres[genre][0]:
            fenetres[genre] = (instant, secondes, fichier)

    sortie = []
    for genre, (instant, secondes, fichier) in fenetres.items():
        remise = int(instant + secondes)
        sortie.append({"kind": genre, "reset_at": remise,
                       "seconds_left": max(0, remise - int(now))})
    sortie.sort(key=lambda f: f["reset_at"])

    actives = [f for f in sortie if f["seconds_left"] > 0]
    dernier = max(tous, key=lambda e: e[0])
    # « libre » seul n'informe de rien ; la dernière échéance passée, si.
    passees = [(int(instant + secondes), "session" if secondes < 24 * 3600 else "week")
               for instant, secondes, _, _ in tous if instant + secondes < now]
    remise, genre_remise = max(passees) if passees else (0, "")
    return {
        "ok": True, "provider": "antigravity",
        "state": "exhausted" if actives else "free",
        "windows": sortie,
        "source": "logs",
        "source_log": str(dernier[3]),
        "last_event": int(dernier[0]),
        "last_reset_at": remise,
        "last_reset_kind": genre_remise,
        "detail": "déduit des logs (API indisponible)",
    }


# ---------------------------------------------------------------- présentation

def presenter(donnees):
    """La fenêtre la plus contrainte en grand, l'autre en dessous.

    Avec l'API on a de vrais pourcentages : la mesure porte le modèle le plus
    touché et sa fenêtre. Sans elle, on retombe sur des échéances, et le widget
    décompte — c'est tout ce que les logs permettent de dire.
    """
    if not donnees.get("ok"):
        return donnees

    fenetres = donnees.get("percent_windows")
    if fenetres:
        mesures = []
        for i, fenetre in enumerate(fenetres):
            pourcent = int(round(float(fenetre["reste"]) * 100))
            familles = " · ".join(fenetre.get("familles") or []) or "quota"
            if i == 0:
                mesures.append(llm_contrat.mesure(
                    f"{pourcent} %", f'{fenetre["label"]} · {familles}',
                    releve=fenetre["reset_at"]))
            else:
                mesures.append(llm_contrat.mesure(
                    texte=f'{fenetre["label"]} · {familles} {pourcent} %',
                    releve=fenetre["reset_at"]))
        # Une fenêtre à zéro sans date de réouverture laisse sans réponse : on
        # l'ajoute en petit, et seulement dans ce cas.
        if float(fenetres[0]["reste"]) <= 0:
            mesures.append(llm_contrat.mesure(texte="rouvre " + time.strftime(
                "%d/%m %H:%M", time.localtime(fenetres[0]["reset_at"]))))
        alerte = min(f["reste"] for f in fenetres) <= SEUIL_ALERTE
        return llm_contrat.presenter(donnees, "Antigravity", "rocket", mesures, alerte)

    # Repli : échéances issues des logs.
    maintenant = int(time.time())
    par_genre = {f.get("kind"): f for f in donnees.get("windows") or []}
    libelles = {"session": "5 h", "week": "hebdo"}
    actives = [f for f in par_genre.values() if int(f.get("reset_at") or 0) > maintenant]
    mesures = []
    if actives:
        principale = max(actives, key=lambda f: f["reset_at"])
        genre = str(principale.get("kind"))
        mesures.append(llm_contrat.mesure(
            llm_contrat.duree(principale["reset_at"] - maintenant),
            libelles.get(genre, genre) + " · épuisé", fin=principale["reset_at"]))
        autre = "session" if genre == "week" else "week"
        if autre in par_genre and int(par_genre[autre].get("reset_at") or 0) > maintenant:
            mesures.append(llm_contrat.mesure(
                llm_contrat.duree(par_genre[autre]["reset_at"] - maintenant),
                libelles[autre] + " épuisée", fin=par_genre[autre]["reset_at"]))
        else:
            mesures.append(llm_contrat.mesure(libelles[autre], "libre"))
    else:
        mesures.append(llm_contrat.mesure("libre", "Antigravity"))
        remise = int(donnees.get("last_reset_at") or 0)
        if remise > 0:
            genre = str(donnees.get("last_reset_kind") or "")
            mesures.append(llm_contrat.mesure(
                "reset " + libelles.get(genre, genre), "", depuis=remise))
    return llm_contrat.presenter(
        donnees, "Antigravity", "rocket", mesures, bool(actives))


def analyser():
    fenetres, raison = depuis_api()
    if fenetres:
        pire = min(f["reste"] for f in fenetres)
        return {
            "ok": True, "provider": "antigravity",
            "state": "exhausted" if pire <= 0 else "free",
            "reste_min": pire,
            "percent_windows": fenetres,
            "source": "api",
        }
    donnees = depuis_logs()
    donnees["api_error"] = raison
    return donnees


def main(argv):
    force = "--force" in argv
    cache = lire_cache()
    if cache and not force and (time.time() - int(cache.get("ts") or 0)) < TTL:
        cache["cached"] = True
        return llm_contrat.sortir(presenter(cache))

    try:
        donnees = analyser()
    except Exception as erreur:                       # noqa: BLE001
        donnees = {"ok": False, "provider": "antigravity", "error": str(erreur)[:120]}

    if donnees.get("ok"):
        donnees["ts"] = int(time.time())
        donnees["cached"] = False
        ecrire_cache(donnees)
    return llm_contrat.sortir(presenter(donnees))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
