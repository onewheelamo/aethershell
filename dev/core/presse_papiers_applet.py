#!/usr/bin/env python3
"""Applet « Presse-papiers » : combien d'entrées dans l'historique.

L'historique vient de `cliphist` (db dans ~/.cache/cliphist). Ce service ne
copie rien lui-même : il liste, compte, et rend un aperçu tronqué de chaque
entrée — l'applet, le popup et le widget s'en servent.

    python3 presse_papiers_applet.py            # contrat de l'applet
    python3 presse_papiers_applet.py liste [n]  # pour le popup et le widget
    python3 presse_papiers_applet.py copier <id>
    python3 presse_papiers_applet.py vider
"""
from __future__ import annotations

import json
import subprocess
import sys
import os
import pathlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

APERCU = 72
DELAI = 5


def _run(cmd, timeout=DELAI, entrees=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                              input=entrees)
    except (OSError, subprocess.TimeoutExpired):
        return None


def entrees(limite=40):
    """[(id, texte)] — les plus récentes d'abord, telles que cliphist les rend.

    `limite` à 0 (ou None) rend tout l'historique : l'appelant qui a besoin du
    compte total ne doit pas le déduire de la page qu'il a demandée.
    """
    res = _run(["cliphist", "list"])
    if res is None:
        return []
    out = []
    for ligne in res.stdout.splitlines():
        if not ligne.strip():
            continue
        morceaux = ligne.split("\t", 1)
        if len(morceaux) != 2:
            continue
        ident, texte = morceaux[0].strip(), morceaux[1]
        texte = texte.replace("\n", " ").strip()
        if texte == "":
            continue
        out.append((ident, texte))
        if limite and len(out) >= limite:
            break
    return out


def decrire(paires):
    """La forme publiée au QML : id, aperçu tronqué, longueur d'origine."""
    out = []
    for ident, texte in paires:
        out.append({
            "id": ident,
            "apercu": (texte[:APERCU - 1] + "…") if len(texte) > APERCU else texte,
            "longueur": len(texte),
        })
    return out


def liste(limite=40):
    return decrire(entrees(limite))


def copier(ident):
    """Remet une entrée dans le presse-papiers (décodage cliphist → wl-copy)."""
    res = _run(["cliphist", "decode", str(ident)])
    if res is None or res.returncode != 0:
        return False
    collant = _run(["wl-copy"], entrees=res.stdout)
    return collant is not None and collant.returncode == 0


def analyser():
    # Le compte affiché est celui de **tout** l'historique, pas de la page
    # qu'on en montre : il restait figé à 40 (et à 6 côté widget) sur une base
    # qui en contenait cinq cents.
    toutes = entrees(0)

    # Les épinglés ne sont pas dans cliphist (ils survivent à sa rotation) : on
    # les compte à part, et le compteur dit « 7 + 1 » plutôt que de les fondre
    # dans un total qui ne veut plus rien dire.
    epingles = 0
    try:
        import json as _json
        chemin = pathlib.Path(os.environ.get("XDG_CACHE_HOME", str(pathlib.Path.home() / ".cache")))
        d = _json.loads((chemin / "quickshell" / "presse_epingles.json").read_text(encoding="utf-8"))
        epingles = len(d) if isinstance(d, dict) else 0
    except (OSError, ValueError):
        epingles = 0
    valeur = f"{len(toutes)} + {epingles}" if epingles else str(len(toutes))

    return {
        "ok": True,
        "compact": compact(valeur, "presse-papiers", alerte=False),
        "detail": {"entrees": decrire(toutes[:40])},
        "applet": "presse-papiers",
        "icone": "selection",
        "alerte": False,
    }


def main(argv):
    action = (argv[1] if len(argv) > 1 else "").strip()

    if action == "liste":
        limite = int(argv[2]) if len(argv) > 2 and argv[2].isdigit() else 40
        toutes = entrees(0)
        print(json.dumps({"ok": True, "total": len(toutes),
                          "entrees": decrire(toutes[:limite])}, ensure_ascii=False))
        return 0

    if action == "copier" and len(argv) > 2:
        ok = copier(argv[2])
        print(json.dumps({"ok": ok}, ensure_ascii=False))
        return 0 if ok else 1

    if action == "vider":
        _run(["cliphist", "wipe"])
        print(json.dumps({"ok": True}, ensure_ascii=False))
        return 0

    donnees = analyser()
    presenter(donnees, "presse-papiers", "selection", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
