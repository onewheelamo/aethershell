#!/usr/bin/env python3
"""Quota Antigravity (Google AI Pro) — pourcentage par modèle et fenêtre.

    antigravity_service.py [--force]

Une ligne JSON sur stdout, rien d'autre. Trois sources, dans cet ordre :

0. `agy -p /usage --output-format json` — la commande de quota du CLI lui-même.
   Elle répond depuis la session déjà ouverte, sans tour de modèle et sans
   consommer de quota, et rend un bucket par couple (groupe de modèles, fenêtre) :
   fraction restante et heure de remise à zéro. C'est la mesure la plus fine des
   trois, et la seule qui nomme la fenêtre (« Gemini 5 h » vs « Claude/GPT 7 j »)
   au lieu de la déduire de l'heure de reset.

1. L'API Code Assist (`cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`),
   la même que Gemini CLI. Elle rend, par modèle, une fraction restante et l'heure
   de remise à zéro : c'est la seule mesure réelle du quota. L'authentification
   est le jeton OAuth que le CLI `agy` range dans le trousseau (libsecret,
   service=gemini / username=antigravity) ; il n'est ni copié ni journalisé.
   Il expire au bout d'une heure environ et le CLI ne le renouvelle qu'en
   s'exécutant : quand c'est le cas, le service lance `agy models` (sans quota,
   ~2 s, une fois par quart d'heure au plus) et refait l'appel. Si le compte
   reste hors d'atteinte, le dernier relevé complet est réaffiché avec sa date.

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
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CACHE_FILE = BASE_DIR / "antigravity_cache.json"
# Dernier relevé *complet* (pourcentages par modèle) : il survit à l'expiration du
# jeton, pour que le widget montre une mesure datée plutôt qu'un simple décompte.
PLEIN_FILE = BASE_DIR / "antigravity_full_cache.json"
# Un seul essai de renouvellement par quart d'heure : `agy models` coûte ~2 s et
# un processus, inutile de le relancer à chaque lecture ratée.
RENEW_FILE = BASE_DIR / "antigravity_renew_cache.json"
RENEW_DELAI = 900
PLEIN_TTL = 6 * 3600


sys.path.insert(0, str(BASE_DIR))
import llm_contrat  # noqa: E402

API_MODELES = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels"
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
# Les modèles qui nous concernent ; `chat_*`, `tab_*` et consorts sont internes.
NOM_MODELE = re.compile(r"gemini|claude|gpt", re.I)


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


def lire_json(chemin):
    try:
        return json.loads(chemin.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def ecrire_json(chemin, donnees):
    try:
        chemin.write_text(json.dumps(donnees, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError:
        pass


def _trouver_agy():
    """Où le CLI `agy` est réellement installé.

    Selon l'installation il vit dans `~/.local/bin` (présent dans le PATH d'un
    shell interactif, pas forcément dans celui de la coquille) ou dans
    `~/.gemini/bin` (hors PATH). Chercher les deux évite un renouvellement qui
    échoue en silence et un widget bloqué en mode dégradé.
    """
    candidats = [
        shutil.which("agy"),
        Path.home() / ".local" / "bin" / "agy",
        Path.home() / ".gemini" / "bin" / "agy",
    ]
    for candidat in candidats:
        if candidat and Path(candidat).is_file():
            return str(candidat)
    return "agy"          # dernier recours : que le PATH tranche


# Fenêtre du CLI -> ce qu'on écrit dans la colonne « tranche ».
TRANCHES = {"weekly": "7 j", "5h": "5 h"}
AGY_USAGE_TIMEOUT = 6.0
# `agy` sans session ouverte lance son flux OAuth et se bloque : on retient
# l'échec dix minutes plutôt que de payer l'attente à chaque rafraîchissement.
# L'applet et le widget retombent alors tout de suite sur l'API ou les logs ;
# `--force` ignore ce délai pour éprouver après une connexion.
AGY_FAIL_FILE = BASE_DIR / "antigravity_agy_fail.json"
AGY_FAIL_TTL = 600


def _groupe_court(nom):
    """« Claude and GPT models » -> « Claude/GPT » ; le reste est conservé."""
    mots = str(nom or "").split()
    if mots and mots[-1].lower() == "models":
        mots = mots[:-1]
    return " ".join(mots).replace(" and ", "/") or "quota"


def _instant(texte):
    """Horodatage ISO du CLI -> secondes Unix (0 si illisible)."""
    try:
        return int(dt.datetime.fromisoformat(str(texte).replace("Z", "+00:00")).timestamp())
    except (TypeError, ValueError):
        return 0


def _agy_echec(raison):
    """Retient l'échec et le rend, pour que le prochain passage n'attende pas."""
    ecrire_json(AGY_FAIL_FILE, {"ts": int(time.time()), "raison": raison})
    return raison


def depuis_agy(force=False):
    """Fenêtres de quota lues sur `agy -p /usage` ; ([], raison) si indisponible.

    Le CLI est lancé dans un groupe de processus à lui : un `agy` qui se bloque
    après avoir rendu la main à son enfant ne doit pas retenir le shell. On lui
    donne un cwd temporaire pour qu'il n'adopte pas le dépôt courant comme
    espace de travail, et on coupe sa mise à jour automatique.
    """
    if not force:
        echec = lire_json(AGY_FAIL_FILE)
        age = int(time.time()) - int(echec.get("ts") or 0)
        if echec.get("raison") and 0 <= age < AGY_FAIL_TTL:
            return [], f'{echec["raison"]} (retenté dans {max(1, (AGY_FAIL_TTL - age) // 60)} min)'

    agy = _trouver_agy()
    env = dict(os.environ, AGY_CLI_DISABLE_AUTO_UPDATE="true")
    argv = [agy, "-p", "/usage", "--output-format", "json", "--print-timeout", "6s"]
    sortie = None
    try:
        with tempfile.TemporaryDirectory(prefix="aether-agy-usage-") as cwd:
            proc = subprocess.Popen(
                argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                encoding="utf-8", errors="replace", start_new_session=True)
            try:
                sortie, _ = proc.communicate(timeout=AGY_USAGE_TIMEOUT)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                proc.communicate()
                return [], _agy_echec("agy n'a pas répondu à temps")
            if proc.returncode != 0:
                # Le CLI range la cause dans son JSON (« authentication failed
                # or timed out », par exemple) : la remonter vaut mieux qu'un
                # code de sortie, qui se lit comme une panne du service.
                motif = ""
                try:
                    motif = str((json.loads(sortie or "") or {}).get("error") or "").strip()
                except (ValueError, AttributeError):
                    pass
                return [], _agy_echec(f"agy : {motif[:80]}" if motif
                                      else f"agy a échoué (code {proc.returncode})")
    except OSError as erreur:
        return [], _agy_echec(f"agy injoignable : {erreur}")

    try:
        corps = json.loads(sortie or "")
    except ValueError:
        return [], _agy_echec("réponse agy illisible")
    # Un `num_turns` non nul veut dire que le CLI a traité « /usage » comme un
    # prompt : le quota vient d'être dépensé pour un aller-retour de modèle.
    if not isinstance(corps, dict) or corps.get("status") != "SUCCESS" \
            or corps.get("num_turns") != 0:
        return [], _agy_echec("réponse agy inattendue")
    commande = corps.get("command") or {}
    if commande.get("name") != "usage":
        return [], _agy_echec("commande /usage non reconnue")
    donnees = commande.get("data") or {}

    fenetres = []
    for groupe in donnees.get("groups") or []:
        if not isinstance(groupe, dict):
            continue
        nom = _groupe_court(groupe.get("name"))
        for bucket in groupe.get("buckets") or []:
            if not isinstance(bucket, dict):
                continue
            reste = bucket.get("remaining_fraction")
            # Un bucket sans fraction n'est pas « 0 % » : il ne dit rien du quota.
            if isinstance(reste, bool) or not isinstance(reste, (int, float)):
                continue
            reste = min(1.0, max(0.0, float(reste)))
            fenetre = str(bucket.get("window") or "")
            fenetres.append({
                "groupe": nom,
                "tranche": TRANCHES.get(fenetre, fenetre),
                "reste": reste,
                "reset_at": _instant(bucket.get("reset_time")),
                "detail": str(bucket.get("description") or ""),
            })
    if not fenetres:
        return [], _agy_echec("aucune fenêtre dans la réponse")
    fenetres.sort(key=lambda f: (f["reste"], -f["reset_at"]))
    # Source redevenue bonne : on efface la mémoire d'échec.
    try:
        AGY_FAIL_FILE.unlink()
    except OSError:
        pass
    return fenetres, ""


def lignes_de_agy(fenetres):
    """Une ligne de tableau par fenêtre, la plus contrainte d'abord."""
    lignes = [{
        "nom": fenetre["groupe"],
        "tranche": fenetre["tranche"],
        "valeur": f'{int(round(fenetre["reste"] * 100)):>3} %',
        "echeance": echeance(fenetre["reset_at"]) if fenetre["reset_at"] else "",
        "reste": fenetre["reste"],
        "alerte": fenetre["reste"] <= SEUIL_ALERTE,
    } for fenetre in fenetres]
    lignes.sort(key=lambda ligne: (0 if ligne["alerte"] else 1, ligne["reste"]))
    return lignes


def renouveler():
    """Fait renouveler le jeton par le CLI lui-même, sans rien écrire nous-mêmes.

    `agy models` ouvre le magasin d'identifiants, rafraîchit le jeton OAuth et sort
    (mesuré : 1,8 à 3,7 s, aucun quota consommé, code 0). C'est le seul moyen sûr
    de renouveler sans toucher au refresh_token : un rafraîchissement fait par nos
    soins pourrait le faire tourner et casser la session du CLI.
    """
    maintenant = int(time.time())
    if maintenant - int(lire_json(RENEW_FILE).get("ts") or 0) < RENEW_DELAI:
        return False
    ecrire_json(RENEW_FILE, {"ts": maintenant})
    binaire = _trouver_agy()
    try:
        # Session détachée, sorties sur /dev/null : le CLI écrit son « Fetching
        # available models… » sur le terminal, pas sur stdout, et il n'a rien à
        # faire dans la sortie du service.
        subprocess.run([binaire, "models"], stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       timeout=45, check=False, start_new_session=True)
    except (OSError, subprocess.SubprocessError):
        return False
    return True



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


def court(nom):
    """« Claude Opus 5.5 (High) » → « Opus 5.5 » : la famille est déjà dite ailleurs."""
    nom = re.sub(r"\s*\([^)]*\)\s*$", "", str(nom or "")).strip()
    if nom.lower().startswith("claude "):
        return nom[len("claude "):]
    return nom


# Un identifiant de modèle → le nom qu'on veut lire sur le widget. Les variantes
# (High / Medium / Low) partagent le même quota : les fusionner est voulu.
ETIQUETTES = (
    ("claude-opus", "Claude Opus"),
    ("claude-sonnet", "Claude Sonnet"),
    ("gpt", "GPT-OSS 120B"),
    ("argon", "Gemini Argon"),
    ("-pro", "Gemini Pro"),
    ("flash", "Gemini Flash"),
)


def etiquette(model):
    """« claude-opus-5-5-high » → « Claude Opus » ; "" si le modèle n'intéresse pas."""
    bas = str(model or "").lower()
    for motif, nom in ETIQUETTES:
        if motif in bas:
            return nom
    return ""


def echeance(instant):
    """« 20:06 » si c'est aujourd'hui, « 07/11 17:15 » sinon : le jour est inutile
    quand la remise tombe dans les heures qui viennent."""
    quand = time.localtime(int(instant))
    maintenant = time.localtime()
    if (quand.tm_year, quand.tm_yday) == (maintenant.tm_year, maintenant.tm_yday):
        return time.strftime("%H:%M", quand)
    return time.strftime("%d/%m %H:%M", quand)


def lignes_de(fenetres):
    """Un tableau : un modèle par ligne, sa tranche et le pourcentage qui reste.

    L'API ne donne qu'une tranche par modèle (les Gemini sont bornés par la fenêtre
    de 5 h, les Claude et GPT par l'hebdomadaire) : il n'y a donc pas deux nombres
    à écrire en face d'un nom, et la tranche est ce qui manquait pour lire.
    """
    pires = {}
    for fenetre in fenetres:
        tranche = "7 j" if fenetre.get("kind") == "week" else "5 h"
        for modele in fenetre.get("models") or []:
            nom = etiquette(modele.get("model"))
            if not nom:
                continue
            reste = float(modele.get("reste") or 0)
            cle = (nom, tranche)
            if cle not in pires or reste < pires[cle][0]:
                pires[cle] = (reste, int(fenetre.get("reset_at") or 0))
    lignes = [{
        "nom": nom,
        "tranche": tranche,
        "valeur": f"{int(round(reste * 100)):>3} %",
        "echeance": echeance(remise) if remise else "",
        "alerte": reste <= SEUIL_ALERTE,
    } for (nom, tranche), (reste, remise) in pires.items()]
    lignes.sort(key=lambda l: (0 if l["alerte"] else 1, l["nom"]))
    return lignes


def fenetres_de(modeles):
    """[{reset_at, reste, familles, noms, models}] regroupés par heure de remise."""
    partages = {}
    for modele in modeles:
        if modele.get("reset"):
            partages.setdefault(modele["reset"], []).append(modele)

    fenetres = []
    for remise, groupe in partages.items():
        try:
            reset_at = int(dt.datetime.fromisoformat(remise.replace("Z", "+00:00")).timestamp())
        except ValueError:
            continue
        pire = min(m["reste"] for m in groupe)
        retenus = [m for m in groupe if m["reste"] <= pire + 1e-9]
        # Claude d'abord, puis Gemini, puis GPT : l'ordre des familles, pas celui
        # de la réponse, qui mélange les variantes.
        rang = {nom: i for i, (_, nom) in enumerate(FAMILLES)}
        retenus.sort(key=lambda m: (rang.get(famille(m["model"]), len(rang)),
                                    m.get("nom") or m["model"]))
        noms = []
        for modele in retenus:
            nom = modele.get("nom") or modele["model"]
            if nom not in noms:
                noms.append(nom)
        fenetres.append({
            "reset_at": reset_at,
            "reste": pire,
            "familles": sorted({famille(m["model"]) for m in retenus}),
            "noms": noms[:3],
            "models": [{"model": m["model"], "reste": m["reste"]} for m in groupe],
        })
    if not fenetres:
        return []

    maintenant = time.time()
    # Deux fenêtres : celle qui rouvre le plus tard est l'hebdomadaire. Un seuil
    # fixe de 48 h se trompait dès que l'hebdo s'en approchait (il était annoncé
    # « 5 h » les deux derniers jours). Une seule fenêtre : on retombe sur le seuil.
    tardive = max(f["reset_at"] for f in fenetres)
    for fenetre in fenetres:
        if len(fenetres) > 1:
            hebdo = fenetre["reset_at"] == tardive
        else:
            hebdo = fenetre["reset_at"] - maintenant > 48 * 3600
        fenetre["kind"] = "week" if hebdo else "session"
        fenetre["label"] = "hebdo" if hebdo else "5 h"
    fenetres.sort(key=lambda f: (f["reste"], -f["reset_at"]))
    return fenetres


def _modeles_utiles(table):
    """Les modèles servis par l'abonnement, ramenés à leur fenêtre de quota."""
    utiles = []
    for nom, info in (table or {}).items():
        if not NOM_MODELE.search(nom):
            continue                     # chat_*, tab_* : internes, sans remise
        quota = (info or {}).get("quotaInfo") or {}
        if not quota.get("resetTime"):
            continue                     # pas de fenêtre : quota illimité
        utiles.append({
            "model": nom,
            "nom": court((info or {}).get("displayName") or nom),
            # Champ absent = plus rien ne reste : c'est ainsi que la réponse dit
            # « épuisé », sans zéro explicite.
            "reste": round(float(quota.get("remainingFraction") or 0), 4),
            "reset": quota["resetTime"],
        })
    return utiles


def _lire_modeles(acces, projet):
    try:
        reponse = poster(API_MODELES, {"project": projet} if projet else {}, acces)
    except urllib.error.HTTPError as erreur:
        return None, f"API modèles : HTTP {erreur.code}", erreur.code
    except (urllib.error.URLError, ValueError) as erreur:
        return None, f"API modèles : {erreur}", None
    fenetres = fenetres_de(_modeles_utiles(reponse.get("models")))
    if not fenetres:
        return None, "aucun modèle quota dans la réponse", None
    return fenetres, None, None


def _lire_quota(acces, projet):
    """L'endpoint groupé d'avant, gardé en second : il donne les mêmes fractions."""
    try:
        quota = poster(API_QUOTA, {"project": projet}, acces)
    except urllib.error.HTTPError as erreur:
        return None, f"API quota : HTTP {erreur.code}", erreur.code
    except (urllib.error.URLError, ValueError) as erreur:
        return None, f"API quota : {erreur}", None
    modeles = [{
        "model": str(compartiment.get("modelId") or "?"),
        "nom": "",
        "reste": round(float(compartiment.get("remainingFraction") or 0), 4),
        "reset": compartiment.get("resetTime"),
    } for compartiment in quota.get("buckets") or []]
    fenetres = fenetres_de(modeles)
    if not fenetres:
        return None, "aucun compartiment quota dans la réponse", None
    return fenetres, None, None


def _lire_assist(acces):
    """(projet, palier d'abonnement, souci)."""
    try:
        reponse = poster(API_ASSIST, {"metadata": {"ideType": "ANTIGRAVITY"}}, acces)
    except urllib.error.HTTPError as erreur:
        return "", "", f"Code Assist : HTTP {erreur.code}"
    except (urllib.error.URLError, ValueError) as erreur:
        return "", "", f"Code Assist : {erreur}"
    # paidTier dit ce que l'abonnement payant apporte (g1-pro-tier), currentTier
    # ce dont le compte dispose par défaut (free-tier) : c'est le premier qui
    # porte les quotas affichés.
    palier = ((reponse.get("paidTier") or {}).get("id")
              or (reponse.get("currentTier") or {}).get("id") or "")
    return str(reponse.get("cloudaicompanionProject") or ""), str(palier), None


def _interroger(acces):
    projet, palier, souci = _lire_assist(acces)
    if souci:
        return None, souci, None, ""
    fenetres, raison, code = _lire_modeles(acces, projet)
    if fenetres:
        return fenetres, None, None, palier
    if code == 401:
        return None, raison, 401, palier
    fenetres, raison2, code2 = _lire_quota(acces, projet)
    if fenetres:
        return fenetres, None, None, palier
    return None, raison2 or raison, code2, palier


def depuis_api():
    """(fenêtres, raison, palier) — les fenêtres de quota, ou la raison du silence.

    Un jeton expiré ou un 401 ne sont pas des impasses : le CLI sait le
    renouveler, et un second essai suffit presque toujours.
    """
    acces, raison = jeton()
    if not acces:
        if "expiré" in str(raison) and renouveler():
            acces, raison = jeton()
        if not acces:
            return None, raison, ""
    fenetres, souci, code, palier = _interroger(acces)
    if fenetres:
        return fenetres, None, palier
    if code == 401 and renouveler():
        acces, _ = jeton()
        if acces:
            fenetres, souci, _, palier = _interroger(acces)
            if fenetres:
                return fenetres, None, palier
    return None, souci or raison, palier


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
                # Un fichier de log peut chevaucher le jour de l'an : une ligne
                # de janvier dans un fichier de décembre appartient à l'année
                # suivante, et une ligne de décembre dans un fichier de janvier
                # à l'année précédente (cas du repli sur `st_mtime`, qui peut
                # contenir la veille). Prendre tout écart pour un passage
                # d'année datait les événements d'un an dans le futur, et un
                # blocage passé comptait alors comme actif.
                annee_ligne = annee
                if mois_fichier == 12 and int(mois) == 1:
                    annee_ligne += 1
                elif (int(mois), int(jour)) > (mois_fichier, jour_fichier):
                    annee_ligne -= 1
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

    # 0. Fenêtres lues sur `agy -p /usage` : le tableau se suffit. Le pied ne
    #    garde que ce qui ne s'y lit pas — la fraîcheur d'un relevé repris du
    #    cache. `mesures` reste vide : en mode tableau le widget ne l'affiche
    #    pas, et l'applet, elle, lit `lignes`.
    lignes_agy = donnees.get("lignes")
    if lignes_agy:
        pied = []
        if donnees.get("source") == "cache":
            pied.append(llm_contrat.mesure(
                texte="relevé", depuis=int(donnees.get("releve_ts") or 0)))
        alerte = any(ligne.get("alerte") for ligne in lignes_agy)
        resultat = llm_contrat.presenter(
            donnees, "Antigravity", "rocket", pied, alerte)
        resultat["lignes"] = lignes_agy
        return resultat

    fenetres = donnees.get("percent_windows")
    if fenetres:
        lignes = lignes_de(fenetres)
        # Le pied ne garde que ce que le tableau ne dit pas : réouverture,
        # fraîcheur d'un relevé repris du cache, palier d'abonnement.
        pied = []
        # Quand le tableau existe, chaque ligne porte déjà son échéance : la
        # répéter en pied n'apprendrait rien.
        if not lignes:
            bloquees = [f for f in fenetres if float(f["reste"]) <= 0]
            if bloquees:
                fenetre = bloquees[0]
                pied.append(llm_contrat.mesure(
                    texte=f'{fenetre["label"]} rouvre ' + echeance(fenetre["reset_at"])))
            elif donnees.get("source") == "cache":
                actives = [f for f in donnees.get("windows") or []
                           if int(f.get("reset_at") or 0) > int(time.time())]
                if actives:
                    plus_tard = max(actives, key=lambda f: f["reset_at"])
                    pied.append(llm_contrat.mesure(
                        texte=("hebdo" if plus_tard.get("kind") == "week" else "5 h")
                        + " rouvre " + echeance(plus_tard["reset_at"])))
        if donnees.get("source") == "cache":
            pied.append(llm_contrat.mesure(
                texte="relevé", depuis=int(donnees.get("releve_ts") or 0)))
        # Un palier sans abonnement payant change tout ce que le widget raconte :
        # mieux vaut le dire que laisser lire des quotas sans portée.
        palier = str(donnees.get("palier") or "")
        sans_pro = palier != "" and "pro" not in palier.lower()
        if sans_pro:
            pied.append(llm_contrat.mesure(texte="palier " + palier.replace("-", " ")))
        alerte = (sans_pro or any(l["alerte"] for l in lignes)
                  or min(f["reste"] for f in fenetres) <= SEUIL_ALERTE)

        if lignes:
            resultat = llm_contrat.presenter(
                donnees, "Antigravity", "rocket", pied, alerte)
            resultat["lignes"] = lignes
            return resultat

        # Aucun modèle reconnaissable : deux lignes de fenêtres, comme avant.
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
        mesures.extend(pied)
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


def analyser(force=False):
    # 1. La commande de quota du CLI : la mesure la plus fine des trois, et la
    #    seule qui dise à quelle fenêtre appartient chaque groupe de modèles.
    agy, raison_agy = depuis_agy(force)
    if agy:
        pire = min(f["reste"] for f in agy)
        maintenant = int(time.time())
        return {
            "ok": True, "provider": "antigravity",
            "state": "exhausted" if pire <= 0 else "free",
            "reste_min": pire,
            "lignes": lignes_de_agy(agy),
            # Gardé pour la compatibilité des lecteurs qui comptent les fenêtres.
            "windows": [{
                "kind": "week" if f["tranche"] == "7 j" else "session",
                "reset_at": f["reset_at"],
                "seconds_left": max(0, f["reset_at"] - maintenant),
            } for f in agy],
            "source": "agy",
        }

    fenetres, raison, palier = depuis_api()
    if fenetres:
        pire = min(f["reste"] for f in fenetres)
        ecrire_json(PLEIN_FILE, {"ts": int(time.time()), "percent_windows": fenetres,
                                 "palier": palier})
        return {
            "ok": True, "provider": "antigravity",
            "state": "exhausted" if pire <= 0 else "free",
            "reste_min": pire,
            "percent_windows": fenetres,
            "palier": palier,
            "source": "api",
        }

    donnees = depuis_logs()
    donnees["api_error"] = raison
    if raison_agy:
        donnees["agy_error"] = raison_agy
    donnees["palier"] = palier
    # Repli de repli : plutôt qu'un simple décompte, montrer le dernier relevé
    # complet, daté. Un pourcentage d'il y a quarante minutes vaut mieux qu'un
    # « épuisé » sans ampleur.
    plein = lire_json(PLEIN_FILE)
    age = int(time.time()) - int(plein.get("ts") or 0)
    if plein.get("percent_windows") and -60 <= age < PLEIN_TTL:
        donnees["percent_windows"] = plein["percent_windows"]
        donnees["palier"] = plein.get("palier") or palier
        donnees["releve_ts"] = int(plein["ts"])
        donnees["source"] = "cache"
    return donnees


def main(argv):
    force = "--force" in argv
    cache = lire_cache()
    if cache and not force and (time.time() - int(cache.get("ts") or 0)) < TTL:
        cache["cached"] = True
        return llm_contrat.sortir(presenter(cache))

    try:
        donnees = analyser(force)
    except Exception as erreur:                       # noqa: BLE001
        donnees = {"ok": False, "provider": "antigravity", "error": str(erreur)[:120]}

    if donnees.get("ok"):
        donnees["ts"] = int(time.time())
        donnees["cached"] = False
        ecrire_cache(donnees)
    return llm_contrat.sortir(presenter(donnees))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
