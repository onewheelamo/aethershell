#!/usr/bin/env python3
"""Applet « Calendrier » : la date dans la barre, et l'événement qui arrive.

Le popup (mois, agenda du jour, ajout d'événement, Nextcloud) reste celui de
l'îlot central (`popup_cle: "calendar"`) : le migrer aurait voulu dire déplacer
six cents lignes de QML pour un résultat identique. L'applet, lui, apporte ce que
la barre ne montrait pas : **le prochain rendez-vous**, quand il y en a un.

Règle d'affichage, dans cet ordre :

  1. un événement aujourd'hui qui n'est pas encore passé → « 14:30 Réunion » ;
  2. un événement « toute la journée » aujourd'hui → son intitulé ;
  3. sinon → la date courte (« mer. 5 nov. »).

Les données viennent de `nextcloud_service.py` (cache 2 h côté service) ; un
cache local de deux minutes évite de relancer le service à chaque ouverture de
popup.
"""
from __future__ import annotations

import datetime
import json
import subprocess
import sys
import time
from pathlib import Path

from applet_contrat import compact, presenter, sortir

ICI = Path(__file__).resolve().parent
CACHE = ICI / "calendrier_applet_cache.json"
CACHE_TTL = 120
DELAI = 20

JOURS = ("lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim.")
MOIS = ("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août",
        "sept.", "oct.", "nov.", "déc.")
LONGUEUR_TITRE = 24


def _court(texte, limite=LONGUEUR_TITRE):
    texte = str(texte or "").strip()
    if len(texte) <= limite:
        return texte
    return texte[: limite - 1].rstrip() + "…"


def date_courte(moment=None):
    m = moment or datetime.datetime.now()
    return f"{JOURS[m.weekday()]} {m.day} {MOIS[m.month - 1]}"


def _mois(annee, mois):
    """Événements du mois, tels que les rend nextcloud_service.py."""
    try:
        res = subprocess.run(
            [sys.executable, str(ICI / "nextcloud_service.py"), "month",
             str(annee), str(mois)],
            capture_output=True, text=True, timeout=DELAI,
        )
        if res.returncode != 0:
            return {}
        return (json.loads(res.stdout.strip() or "{}").get("days") or {})
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {}


def _prochain(days, maintenant):
    """L'événement à annoncer : celui qui n'est pas passé, sinon « journée »."""
    cle = maintenant.strftime("%Y-%m-%d")
    evenements = days.get(cle) or []
    if not evenements:
        return None
    heure = maintenant.strftime("%H:%M")
    a_venir, journee = [], []
    for e in evenements:
        if e.get("all_day"):
            journee.append(e)
            continue
        if str(e.get("sort_key") or "00:00") >= heure:
            a_venir.append(e)
    if a_venir:
        a_venir.sort(key=lambda e: e.get("sort_key") or "")
        return ("heure", a_venir[0])
    if journee:
        return ("journee", journee[0])
    return None


def analyser(force=False):
    maintenant = datetime.datetime.now()
    if not force:
        try:
            lu = json.loads(CACHE.read_text(encoding="utf-8"))
            if 0 <= time.time() - float(lu.get("ts", 0)) < CACHE_TTL:
                return lu
        except (OSError, ValueError):
            pass

    days = _mois(maintenant.year, maintenant.month)
    prochain = _prochain(days, maintenant)
    if prochain is None:
        valeur, libelle, sortes = date_courte(maintenant), "", ""
    elif prochain[0] == "heure":
        e = prochain[1]
        valeur = f"{e.get('time') or e.get('sort_key') or ''} {_court(e.get('summary'))}".strip()
        libelle = str(e.get("summary") or "")
        sortes = "heure"
    else:
        e = prochain[1]
        valeur = _court(e.get("summary"))
        libelle = "aujourd'hui"
        sortes = "journee"

    donnees = {
        "ok": True,
        "ts": time.time(),
        "compact": compact(valeur, libelle),
        "date": date_courte(maintenant),
        "genre": sortes,
        "source": "nextcloud" if days else "vide",
    }
    try:
        CACHE.write_text(json.dumps(donnees, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    return donnees


def main(argv):
    force = "--force" in argv
    donnees = analyser(force=force)
    presenter(donnees, "calendrier", "calendar", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
