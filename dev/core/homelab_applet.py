#!/usr/bin/env python3
"""Applet « Homelab » : ce qui tourne, ce qui est tombé, et qui répond.

Trois sources, toutes locales :
  • conteneurs docker (en cours / total) — `docker ps` et `docker ps -a` ;
  • unités systemd en échec (système et session) — `systemctl --failed` ;
  • hôtes à surveiller, listés dans core/homelab.json :
        {"hotes": [{"nom": "nas", "url": "192.0.2.12"}, ...]}

Sans fichier de configuration, l'applet se rabat sur les deux premières sources :
il dit déjà quelque chose d'utile, sans rien inventer sur un parc qu'il ne connaît
pas.

    python3 homelab_applet.py [--force]
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

BASE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(BASE, "homelab.json")
DELAI = 4


def _run(cmd, timeout=DELAI):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def conteneurs():
    if not _run(["sh", "-c", "command -v docker"]).strip():
        return {}
    actifs = [l for l in _run(["docker", "ps", "-q"]).splitlines() if l.strip()]
    tous = [l for l in _run(["docker", "ps", "-aq"]).splitlines() if l.strip()]
    if not tous:
        return {"en_cours": 0, "total": 0}
    return {"en_cours": len(actifs), "total": len(tous)}


def unites_en_echec():
    n = 0
    noms = []
    for portee in (["--failed"], ["--user", "--failed"]):
        sortie = _run(["systemctl"] + portee + ["--no-legend", "--plain"])
        for ligne in sortie.splitlines():
            morceaux = ligne.split()
            if not morceaux:
                continue
            n += 1
            if len(noms) < 5:
                noms.append(morceaux[0])
    return {"nombre": n, "noms": noms}


def hotes():
    """Ceux du fichier de configuration, avec leur latence ou leur absence."""
    try:
        with open(CONFIG, "r", encoding="utf-8") as f:
            conf = json.load(f)
    except (OSError, ValueError):
        return []

    out = []
    for h in (conf.get("hotes") or []):
        if not isinstance(h, dict):
            continue
        nom = str(h.get("nom") or h.get("url") or "").strip()
        cible = str(h.get("url") or h.get("nom") or "").strip()
        if not cible:
            continue
        res = _run(["ping", "-c", "1", "-W", "1", cible], timeout=3)
        m = re.search(r"(?:time|temps)[=<]([\d.]+)\s*ms", res)
        if not m:
            m = re.search(r"rtt[^=]*=\s*[\d.]+/([\d.]+)/", res)
        out.append({
            "nom": nom,
            "url": cible,
            "joignable": bool(m),
            "latence_ms": round(float(m.group(1))) if m else None,
        })
    return out


def analyser():
    cont = conteneurs()
    unites = unites_en_echec()
    h = hotes()

    injoignables = [x for x in h if not x["joignable"]]
    alerte = bool(injoignables) or unites["nombre"] > 0

    if injoignables:
        valeur = str(len(injoignables))
        libelle = "hôte(s) injoignable(s)"
    elif unites["nombre"] > 0:
        valeur = str(unites["nombre"])
        libelle = "service(s) en échec"
    elif cont:
        valeur = str(cont.get("en_cours", 0))
        libelle = "conteneur(s)"
    else:
        valeur = ""
        libelle = ""

    barres = []
    if cont:
        total = max(1, int(cont.get("total", 0)))
        pct = round(100 * int(cont.get("en_cours", 0)) / total)
        barres.append({
            "cle": "conteneurs", "nom": "Conteneurs", "icone": "rocket",
            "valeur": pct, "remplissage": pct,
            "texte": str(cont.get("en_cours", 0)) + "/" + str(cont.get("total", 0)),
            "niveau": "ok", "alerte": False,
        })
    if h:
        joignables = [x for x in h if x["joignable"]]
        pct = round(100 * len(joignables) / len(h))
        barres.append({
            "cle": "hotes", "nom": "Hôtes", "icone": "cloud-check",
            "valeur": pct, "remplissage": pct,
            "texte": str(len(joignables)) + "/" + str(len(h)),
            "niveau": "critique" if pct < 100 else "ok",
            "alerte": pct < 100,
        })

    return {
        "ok": True,
        "compact": compact(valeur, libelle, alerte, barres=barres or None),
        "detail": {"conteneurs": cont, "unites": unites, "hotes": h},
        "applet": "homelab",
        "icone": "cloud-check",
        "alerte": alerte,
    }


def main(argv):
    donnees = analyser()
    presenter(donnees, "homelab", "cloud-check", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
