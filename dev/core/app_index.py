#!/usr/bin/env python3
"""Construit l'index des applications pour la pilule spotlight.

Écrit `core/app_index.json` : une entrée par fichier .desktop visible, avec le
nom localisé (fr), la commande nettoyée des marqueurs %f/%u/%U…, l'icône et la
catégorie principale. Le QML ne fait plus que filtrer cet index — pas de parseur
de .desktop en QML, et un index qu'on peut inspecter à la main.

Usage : app_index.py [--quiet]
"""
import json
import os
import re
import sys
from pathlib import Path

DIRS = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]

# Catégories qu'on affiche à droite du nom (la première trouvée gagne).
CATEGORY_LABELS = [
    ("WebBrowser", "Navigateur"),
    ("Development", "Développement"),
    ("Graphics", "Graphisme"),
    ("AudioVideo", "Média"),
    ("Audio", "Audio"),
    ("Video", "Vidéo"),
    ("Office", "Bureautique"),
    ("Network", "Réseau"),
    ("System", "Système"),
    ("Settings", "Réglages"),
    ("Utility", "Utilitaire"),
    ("Game", "Jeu"),
    ("FileManager", "Fichiers"),
    ("TerminalEmulator", "Terminal"),
]

DROP_MARKS = re.compile(r"\s*%[fFuUdDnNickvm]")
DROP_FLATPAK_MARKS = re.compile(r"(?:^|\s)@@u?\s+@@(?=\s|$)")


def parse_desktop(path):
    fields = {}
    section = None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            continue
        if section != "Desktop Entry":
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        fields.setdefault(key.strip(), value.strip())
    return fields


def pick_name(fields):
    for key in ("Name[fr]", "Name[fr_FR]", "Name"):
        value = fields.get(key)
        if value:
            return value
    return None


def clean_exec(exec_line):
    cmd = DROP_MARKS.sub("", exec_line)
    cmd = DROP_FLATPAK_MARKS.sub("", cmd).strip()
    return cmd


def category_label(categories):
    for needle, label in CATEGORY_LABELS:
        if needle in categories:
            return label
    return ""


def main():
    quiet = "--quiet" in sys.argv
    seen = {}
    for directory in DIRS:
        base = Path(directory)
        if not base.is_dir():
            continue
        for path in sorted(base.glob("*.desktop")):
            fields = parse_desktop(path)
            if not fields:
                continue
            if fields.get("NoDisplay", "").lower() == "true":
                continue
            if fields.get("Hidden", "").lower() == "true":
                continue
            name = pick_name(fields)
            exec_line = fields.get("Exec")
            if not name or not exec_line:
                continue
            if not fields.get("Type", "Application") == "Application":
                continue
            key = name.lower()
            if key in seen:
                continue
            seen[key] = {
                "name": name,
                "exec": clean_exec(exec_line),
                "icon": fields.get("Icon", ""),
                "comment": fields.get("Comment[fr]") or fields.get("Comment", ""),
                "category": category_label(fields.get("Categories", "")),
                "desktop": path.name,
            }

    apps = sorted(seen.values(), key=lambda a: a["name"].lower())
    target = Path(__file__).resolve().parent / "app_index.json"
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(apps, ensure_ascii=False, indent=1), encoding="utf-8")
    tmp.replace(target)
    if not quiet:
        print(f"app_index: {len(apps)} applications -> {target}")


if __name__ == "__main__":
    main()
