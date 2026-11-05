#!/usr/bin/env python3
"""Quota Antigravity (Google AI Pro) — quand le compte sera de nouveau utilisable.

    antigravity_service.py [--force]

Une ligne JSON sur stdout, rien d'autre :

    {"ok": true, "provider": "antigravity", "state": "exhausted",
     "windows": [{"kind": "session", "reset_at": 1793890000, "seconds_left": 10800},
                 {"kind": "week",    "reset_at": 1794140000, "seconds_left": 180000}],
     "source": "...log", "ts": 1699..., "cached": false}

Pourquoi les logs et pas une API : Antigravity (le client `agy`) ne parle à son
service de quota que par un protocole binaire local (WebSocket protobuf, non
documenté) et par `cloudcode-pa.googleapis.com` avec un jeton OAuth qu'aucun
fichier lisible ne contient — le rafraîchissement échoue (`invalid_client`).
L'abonnement Google AI Pro n'expose donc aucun point d'entrée interrogeable.

Ce qui est lisible, en revanche : quand le quota est atteint, le CLI écrit dans
ses logs « RESOURCE_EXHAUSTED (code 429): Individual quota reached … Resets in
2h58m19s ». On en déduit l'instant de remise à zéro (horodatage de la ligne +
durée annoncée) et il suffit de comparer à maintenant. Deux fenêtres distinctes
apparaissent : une courte (~3 h, celle des modèles courants) et une longue
(~151 h, hebdomadaire, réservée aux modèles premium).

Limite assumée : le service ne dit pas « il reste 40 % », il dit « épuisé
jusqu'à telle heure » — et si aucun 429 n'a été journalisé, il se tait
(`state: "free"` veut dire « rien ne prouve le contraire », pas « c'est mesuré »).
C'est une inférence sur des logs, pas une lecture de quota ; le widget l'affiche
comme telle.

Les logs sont ceux de `~/.gemini/antigravity/log` et `~/.gemini/antigravity-cli/log`,
en lecture seule : rien n'est écrit, rien n'est modifié.
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CACHE_FILE = BASE_DIR / "antigravity_cache.json"

LOG_DIRS = [
    Path(os.path.expanduser("~/.gemini/antigravity/log")),
    Path(os.path.expanduser("~/.gemini/antigravity-cli/log")),
]
TTL = 120          # local et bon marché, mais pas utile de relire à chaque cycle

# « E1101 09:51:02.966262   72205 errorreport.go:224] … Resets in 151h24m24s. »
LIGNE = re.compile(r"^([IWEF])(\d{2})(\d{2}) (\d{2}):(\d{2}):(\d{2})\.\d+\s+\d+\s+\S+\]\s*(.*)$")
DELAI = re.compile(r"Resets in (?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?")
QUOTA = "Individual quota reached"


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
            tous.extend((instant, secondes, texte, fichier) for instant, secondes, texte in evenements(fichier))
    return tous


def analyser():
    now = time.time()
    tous = collecter()
    if not tous:
        return {"ok": True, "provider": "antigravity", "state": "free", "windows": [],
                "source": None, "detail": "aucun épuisement journalisé"}

    # Le dernier épuisement de chaque fenêtre fait foi : une fenêtre courte
    # (~3 h) et une longue (~151 h, hebdomadaire).
    fenetres = {}
    for instant, secondes, texte, fichier in tous:
        genre = "session" if secondes < 24 * 3600 else "week"
        if genre not in fenetres or instant > fenetres[genre][0]:
            fenetres[genre] = (instant, secondes, fichier)

    sortie = []
    for genre, (instant, secondes, fichier) in fenetres.items():
        remise = int(instant + secondes)
        sortie.append({
            "kind": genre,
            "reset_at": remise,
            "seconds_left": max(0, remise - int(now)),
            "logged_at": int(instant),
        })
    sortie.sort(key=lambda f: f["reset_at"])

    actives = [f for f in sortie if f["seconds_left"] > 0]
    dernier = max(tous, key=lambda e: e[0])
    return {
        "ok": True,
        "provider": "antigravity",
        "state": "exhausted" if actives else "free",
        "windows": sortie,
        "source": str(dernier[3]),
        "last_event": int(dernier[0]),
        "detail": "déduit des logs (aucun point d'entrée de quota côté abonnement)",
    }


def main(argv):
    force = "--force" in argv
    cache = lire_cache()
    if cache and not force and (time.time() - int(cache.get("ts") or 0)) < TTL:
        cache["cached"] = True
        print(json.dumps(cache, ensure_ascii=False))
        return 0

    try:
        donnees = analyser()
    except Exception as erreur:                       # noqa: BLE001
        donnees = {"ok": False, "provider": "antigravity", "error": str(erreur)[:120]}

    if donnees.get("ok"):
        donnees["ts"] = int(time.time())
        donnees["cached"] = False
        ecrire_cache(donnees)
    print(json.dumps(donnees, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
