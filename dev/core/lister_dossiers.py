#!/usr/bin/env python3
"""Lister les sous-dossiers d'un chemin, pour le sélecteur de dossier du panneau.

Sert `SelecteurDossier.qml` : plutôt que `FolderListModel` (un module QML de plus,
absent du moteur QML de Quickshell sur cette machine), on lit l'arborescence ici et
on la rend en JSON — même schéma que les autres services du shell.

Les entrées cachées sont écartées (un sélecteur de dossier n'a pas à les montrer),
et les erreurs sont rendues explicitement plutôt qu'en liste vide silencieuse.

Sortie : {"chemin": "...", "erreur": "", "dossiers": [{"nom": "...", "chemin": "..."}]}
"""
import json
import os
import sys
from pathlib import Path


def lister(dossier):
    base = Path(dossier).expanduser()
    entrees = []
    for nom in sorted(os.listdir(base), key=lambda n: n.lower()):
        if nom.startswith("."):
            continue
        chemin = base / nom
        try:
            if chemin.is_dir():
                entrees.append({"nom": nom, "chemin": str(chemin)})
        except OSError:
            continue
    return entrees


def main():
    if len(sys.argv) < 2:
        print("usage : lister_dossiers.py <chemin>", file=sys.stderr)
        return 2
    dossier = sys.argv[1]
    try:
        dossiers = lister(dossier)
    except (OSError, PermissionError) as e:
        print(json.dumps({"chemin": dossier, "erreur": str(e), "dossiers": []},
                         ensure_ascii=False))
        return 0
    print(json.dumps({"chemin": dossier, "erreur": "", "dossiers": dossiers},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
