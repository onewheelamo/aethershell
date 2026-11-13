#!/usr/bin/env python3
"""Dire si le shell déployé est à jour par rapport à ce qui est publié sur GitHub.

Le dossier déployé (`~/.config/quickshell`) n'est pas un dépôt git : il ne peut
pas répondre seul à « quelle version tourne ? ». `deploy.sh` écrit donc
`core/version.json` à chaque déploiement, et ce programme le compare au dernier
tag publié sur GitHub.

La même ligne d'installation sert aux deux gestes — première pose et mise à
jour —, exactement comme pour Ollama :

    curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | bash

Fréquence : GitHub n'est interrogé qu'une fois toutes les **280 minutes**.
Entre deux, la réponse vient du cache (`~/.cache/quickshell/maj_shell.json`) :
le panneau peut demander l'état à chaque ouverture, sans sortir sur le réseau.
Après un échec, une nouvelle tentative attend 10 minutes au lieu de 280 —
sinon une coupure passagère masquerait une mise à jour pendant près de 5 h.

Aucune sortie d'erreur qui casse l'appelant : le panneau lit du JSON sur une
ligne, et un réseau absent donne `"etat": "inconnu"`, pas une exception.

Usage :
    maj_shell.py                # JSON sur une ligne, cache respecté
    maj_shell.py --force        # interroge GitHub maintenant
    maj_shell.py --texte        # résumé lisible (terminal)
    maj_shell.py --lien         # imprime seulement la ligne d'installation
    maj_shell.py --intervalle N # change la fenêtre de cache (minutes)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

DEPOT = "onewheelamo/aethershell"
BRANCHE = "master"
LIEN = f"https://raw.githubusercontent.com/{DEPOT}/{BRANCHE}/install.sh"
COMMANDE = f"curl -fsSL {LIEN} | bash"

INTERVALLE_MIN = 280
ESSAI_APRES_ECHEC_MIN = 10
DELAI_RESEAU = 8  # secondes

RACINE = Path(__file__).resolve().parent


# ── Cache ────────────────────────────────────────────────────────────────────
def dossier_cache() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(Path.home(), ".cache")
    chemin = Path(base) / "quickshell"
    try:
        chemin.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass
    return chemin


CACHE = dossier_cache() / "maj_shell.json"


def lire_cache() -> dict:
    try:
        donnee = json.loads(CACHE.read_text(encoding="utf-8"))
        return donnee if isinstance(donnee, dict) else {}
    except (OSError, ValueError):
        return {}


def ecrire_cache(donnee: dict) -> None:
    """Écriture atomique : le panneau peut lire pendant qu'on écrit."""
    temporaire = CACHE.with_suffix(".json.new")
    try:
        temporaire.write_text(json.dumps(donnee) + "\n", encoding="utf-8")
        os.replace(temporaire, CACHE)
    except OSError:
        pass


# ── Version locale ───────────────────────────────────────────────────────────
def version_locale() -> dict:
    """D'abord `core/version.json` (écrit au déploiement), puis le dépôt git."""
    fichier = RACINE / "version.json"
    if fichier.is_file():
        try:
            donnee = json.loads(fichier.read_text(encoding="utf-8"))
            if isinstance(donnee, dict) and (donnee.get("version") or donnee.get("tag")):
                return {
                    "version": str(donnee.get("version") or ""),
                    "tag": str(donnee.get("tag") or ""),
                    "commit": str(donnee.get("commit") or ""),
                    "origine": "déploiement",
                }
        except (OSError, ValueError):
            pass

    # Exécuté depuis un clone (`dev/core/`) : deux niveaux au-dessus, le dépôt.
    depot = RACINE.parent.parent
    if (depot / ".git").exists():
        def git(*arguments: str) -> str:
            try:
                sortie = subprocess.run(
                    ["git", "-C", str(depot), *arguments],
                    capture_output=True, text=True, timeout=5,
                )
                return sortie.stdout.strip()
            except (OSError, subprocess.SubprocessError):
                return ""

        return {
            "version": git("describe", "--tags", "--always", "--dirty"),
            "tag": git("describe", "--tags", "--abbrev=0"),
            "commit": git("rev-parse", "--short", "HEAD"),
            "origine": "dépôt",
        }

    return {"version": "", "tag": "", "commit": "", "origine": "absente"}


# ── Version publiée ──────────────────────────────────────────────────────────
def _dernier_tag(donnee):
    if isinstance(donnee, dict):
        return str(donnee.get("tag_name") or "")
    if isinstance(donnee, list) and donnee and isinstance(donnee[0], dict):
        return str(donnee[0].get("name") or "")
    return ""


def interroger_github():
    """(tag, None) en cas de succès, (None, message) sinon.

    `releases/latest` d'abord : c'est là qu'une version est annoncée. Sans
    release publiée (404), les tags font foi — le développement tague sans
    toujours créer de release.
    """
    entetes = {
        "User-Agent": "aethershell-maj",
        "Accept": "application/vnd.github+json",
    }
    urls = (
        f"https://api.github.com/repos/{DEPOT}/releases/latest",
        f"https://api.github.com/repos/{DEPOT}/tags?per_page=1",
    )
    dernier = "GitHub n'a pas répondu"
    introuvable = 0
    for url in urls:
        demande = urllib.request.Request(url, headers=entetes)
        try:
            with urllib.request.urlopen(demande, timeout=DELAI_RESEAU) as reponse:
                donnee = json.loads(reponse.read().decode("utf-8"))
        except urllib.error.HTTPError as erreur:
            if erreur.code == 404:      # pas de release : on demande les tags
                introuvable += 1
                dernier = "aucune release ni tag publié" if introuvable == 1 \
                    else "dépôt introuvable ou privé (404 sur la release et les tags)"
                continue
            return None, f"GitHub a répondu {erreur.code}"
        except (urllib.error.URLError, OSError) as erreur:
            return None, f"réseau indisponible ({erreur.__class__.__name__})"
        except ValueError:
            return None, "réponse GitHub illisible"
        tag = _dernier_tag(donnee)
        if tag:
            return tag, None
        dernier = "aucune release ni tag publié"
    return None, dernier


def numeros(version: str):
    """« v0.1.5-3-gabc » → (0, 1, 5, 0), « v0.3.6.1 » → (0, 3, 6, 1)."""
    trouve = re.search(r"(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?", version or "")
    if not trouve:
        return None
    a, b, c, d = trouve.groups()
    return (int(a), int(b), int(c), int(d) if d is not None else 0)


# ── État ─────────────────────────────────────────────────────────────────────
def horodatage(secondes) -> str:
    if not secondes:
        return ""
    return datetime.fromtimestamp(secondes).astimezone().isoformat(timespec="seconds")


def etat_complet(intervalle: int, force: bool) -> dict:
    locale = version_locale()
    cache = lire_cache()
    maintenant = time.time()

    verifie_le = float(cache.get("verifie_le") or 0)
    echec_le = float(cache.get("echec_le") or 0)
    distante = str(cache.get("distante") or "")
    erreur = str(cache.get("erreur") or "")

    frais = verifie_le and (maintenant - verifie_le) < intervalle * 60
    recent_echec = echec_le and (maintenant - echec_le) < ESSAI_APRES_ECHEC_MIN * 60

    if force or not (frais or recent_echec):
        tag, message = interroger_github()
        if tag:
            distante, erreur = tag, ""
            verifie_le = maintenant
            ecrire_cache({"verifie_le": verifie_le, "distante": distante})
        else:
            # On garde la dernière version connue : un réseau tombé ne doit pas
            # effacer « v0.1.6 est disponible ».
            erreur = message or "GitHub n'a pas répondu"
            ecrire_cache({
                "verifie_le": verifie_le,
                "distante": distante,
                "erreur": erreur,
                "echec_le": maintenant,
            })

    locale_txt = locale["version"] or locale["tag"]
    num_locale = numeros(locale["tag"] or locale_txt)
    num_distante = numeros(distante)

    if not distante:
        etat = "inconnu"
        detail = erreur or "version publiée inconnue"
    elif num_locale is None:
        etat = "inconnu"
        detail = "version locale illisible — relance l'installateur pour la réécrire"
    elif num_distante is None:
        etat = "inconnu"
        detail = f"tag publié illisible ({distante})"
    elif num_distante > num_locale:
        etat = "disponible"
        detail = f"{distante} est publiée sur GitHub"
    else:
        etat = "a_jour"
        detail = "tu as la dernière version publiée"
        if num_distante < num_locale:
            detail += " (ton clone est en avance sur le dernier tag)"

    return {
        "etat": etat,
        "locale": locale_txt,
        "locale_tag": locale["tag"],
        "commit": locale["commit"],
        "origine": locale["origine"],
        "distante": distante,
        "detail": detail,
        "erreur": erreur,
        "verifie_le": horodatage(verifie_le),
        "il_y_a_min": round((maintenant - verifie_le) / 60) if verifie_le else None,
        "intervalle_min": intervalle,
        "commande": COMMANDE,
        "lien": LIEN,
    }


def resume(etat: dict) -> str:
    marque = {"a_jour": "✓", "disponible": "↑", "inconnu": "?"}.get(etat["etat"], "?")
    lignes = [
        f"{marque} {etat['locale'] or 'version inconnue'} — {etat['detail']}",
    ]
    if etat["distante"]:
        lignes.append(f"  publiée : {etat['distante']}")
    if etat["verifie_le"]:
        lignes.append(f"  vérifié  : {etat['verifie_le']} (toutes les {etat['intervalle_min']} min)")
    lignes.append(f"  installer / mettre à jour : {etat['commande']}")
    return "\n".join(lignes)


def main(argv=None) -> int:
    analyseur = argparse.ArgumentParser(
        description="État de la version d'AetherShell : locale et publiée sur GitHub.",
    )
    analyseur.add_argument("--force", action="store_true",
                           help="ignore le cache et interroge GitHub maintenant")
    analyseur.add_argument("--intervalle", type=int, default=INTERVALLE_MIN,
                           help=f"fenêtre de cache en minutes (défaut : {INTERVALLE_MIN})")
    analyseur.add_argument("--texte", action="store_true",
                           help="résumé lisible au lieu du JSON")
    analyseur.add_argument("--lien", action="store_true",
                           help="imprime seulement la ligne d'installation")
    arguments = analyseur.parse_args(argv)

    if arguments.lien:
        print(COMMANDE)
        return 0

    intervalle = max(1, arguments.intervalle)
    etat = etat_complet(intervalle, arguments.force)
    print(resume(etat) if arguments.texte else json.dumps(etat, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
