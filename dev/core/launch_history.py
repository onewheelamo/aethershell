#!/usr/bin/env python3
"""Historique des lancements de la pilule spotlight.

`core/launch_history.json` : liste la plus récente en tête, dédoublonnée par
commande. Écrit par la pilule (uniquement si `launch_history` est vrai dans
style_vars.json), lu par elle à l'ouverture, vidé depuis le panneau.

Usage :
    launch_history.py add "<nom>" "<commande>" [icône]
    launch_history.py clear
    launch_history.py list
"""
import json
import os
import sys
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
HISTORY_FILE = os.path.join(BASE_DIR, "launch_history.json")
MAX_ENTRIES = 25


def load():
    try:
        with open(HISTORY_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def save(entries):
    tmp = HISTORY_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, indent=1)
    os.replace(tmp, HISTORY_FILE)


def add(name, command, icon=""):
    entries = [e for e in load() if e.get("exec") != command]
    entries.insert(0, {
        "name": name,
        "exec": command,
        "icon": icon,
        "t": int(time.time()),
    })
    save(entries[:MAX_ENTRIES])


def clear():
    save([])


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    action = sys.argv[1]
    if action == "add" and len(sys.argv) > 3:
        icon = sys.argv[4] if len(sys.argv) > 4 else ""
        add(sys.argv[2], sys.argv[3], icon)
    elif action == "clear":
        clear()
    elif action == "list":
        print(json.dumps(load(), ensure_ascii=False, indent=1))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
