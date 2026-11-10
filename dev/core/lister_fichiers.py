#!/usr/bin/env python3
"""Lister les sous-dossiers et fichiers d'un chemin, pour le sélecteur de fichier du panneau.

Sert `SelecteurFichier.qml` : plutôt que `FolderListModel` (absent du moteur QML de
Quickshell sur cette machine), on lit l'arborescence ici et on la rend en JSON — même
schéma que les autres services du shell.

Les entrées cachées sont écartées.
Les dossiers sont listés en premier (pour la navigation), suivis des fichiers
filtrés par extensions (ou tous les fichiers si aucune extension n'est précisée).

Sortie : {"chemin": "...", "erreur": "", "entrees": [{"nom": "...", "chemin": "...", "est_dossier": true/false}]}
"""
import json
import os
import sys
from pathlib import Path


def lister(dossier, extensions=None):
    base = Path(dossier).expanduser()
    if not base.exists():
        # Si le chemin pointe vers un fichier inexistant ou non trouvé, essayer le dossier parent
        if base.parent.exists():
            base = base.parent
        else:
            base = Path.home()

    if not base.is_dir():
        base = base.parent

    exts = None
    if extensions:
        exts = {e.lower().lstrip(".") for e in extensions if e.strip()}

    dossiers = []
    fichiers = []

    try:
        noms = sorted(os.listdir(base), key=lambda n: n.lower())
    except (OSError, PermissionError) as e:
        return {"chemin": str(base), "erreur": str(e), "entrees": []}

    for nom in noms:
        if nom.startswith("."):
            continue
        p = base / nom
        try:
            if p.is_dir():
                dossiers.append({"nom": nom, "chemin": str(p), "est_dossier": True})
            elif p.is_file():
                if exts is None or p.suffix.lower().lstrip(".") in exts:
                    fichiers.append({"nom": nom, "chemin": str(p), "est_dossier": False})
        except OSError:
            continue

    return {"chemin": str(base), "erreur": "", "entrees": dossiers + fichiers}


def main():
    if len(sys.argv) < 2:
        print("usage : lister_fichiers.py <chemin> [ext1 ext2 ...]", file=sys.stderr)
        return 2
    dossier = sys.argv[1]
    extensions = sys.argv[2:] if len(sys.argv) > 2 else None
    result = lister(dossier, extensions)
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
