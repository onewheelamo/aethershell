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


def _read_qt6ct_theme():
    conf = Path(os.path.expanduser("~/.config/qt6ct/qt6ct.conf"))
    try:
        for line in conf.read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.strip().startswith("icon_theme="):
                val = line.split("=", 1)[1].strip()
                if val:
                    return val
    except OSError:
        pass
    return ""


def _build_icon_map():
    """Indexe les fichiers d'icônes (.svg/.png) par nom sans extension."""
    active = _read_qt6ct_theme()
    themes = []
    for t in (active, "Papirus-Dark", "Papirus", "breeze-dark", "breeze", "Adwaita", "AdwaitaLegacy", "hicolor"):
        if t and t not in themes:
            themes.append(t)

    roots = [
        Path(os.path.expanduser("~/.local/share/icons")),
        Path(os.path.expanduser("~/.local/share/flatpak/exports/share/icons")),
        Path("/var/lib/flatpak/exports/share/icons"),
        Path("/usr/share/icons"),
    ]
    exts = (".svg", ".png", ".xpm")
    size_prio = ("scalable", "48x48", "64x64", "32x32", "48", "64", "32", "24x24", "24", "22x22", "22", "16x16", "16")
    icons = {}

    def _score(path_obj, theme_idx):
        p_str = str(path_obj)
        s = theme_idx * 100
        if "/apps" in p_str:
            s -= 20
        for idx, sz in enumerate(size_prio):
            if f"/{sz}/" in p_str:
                s += idx
                break
        else:
            s += 30
        if path_obj.suffix.lower() == ".svg":
            s -= 2
        return s

    best_score = {}
    for t_idx, theme in enumerate(themes):
        for root in roots:
            tdir = root / theme
            if not tdir.is_dir():
                continue
            for dirpath, _, filenames in os.walk(tdir):
                for fn in filenames:
                    p = Path(dirpath) / fn
                    if p.suffix.lower() not in exts:
                        continue
                    stem = p.stem
                    sc = _score(p, t_idx)
                    if stem not in best_score or sc < best_score[stem]:
                        best_score[stem] = sc
                        icons[stem] = str(p)

    pix = Path("/usr/share/pixmaps")
    if pix.is_dir():
        for p in pix.iterdir():
            if p.is_file() and p.suffix.lower() in exts and p.stem not in icons:
                icons[p.stem] = str(p)
    return icons


def _resolve_icon(raw_icon, icon_map):
    ic = (raw_icon or "").strip()
    if not ic:
        return ""
    if ic.startswith("/") and Path(ic).is_file():
        return ic
    stem = Path(ic).stem if "." in Path(ic).name else ic
    return icon_map.get(ic) or icon_map.get(stem) or ic


def main():
    quiet = "--quiet" in sys.argv
    icon_map = _build_icon_map()
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
                "icon": _resolve_icon(fields.get("Icon", ""), icon_map),
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
