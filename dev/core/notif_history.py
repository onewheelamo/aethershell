#!/usr/bin/env python3
"""Historique des notifications du shell — indépendant du panneau.

Chaque notification reçue y laisse une trace, même si son application la ferme
ensuite ou si elle est effacée du centre de notifications : c'est ce qui permet
de retrouver une notification effacée par erreur.

Format : JSON Lines (`~/.cache/quickshell/notifications-history.jsonl`), une
entrée par ligne, la plus récente **en fin de fichier**. L'ajout est un simple
append ; supprimer ou vider réécrit le fichier. Plafond : MAX_ENTRIES, les plus
anciennes tombent.

Usage :
    notif_history.py add < entrée.json     # ajoute (lit le JSON sur stdin)
    notif_history.py list                  # JSON array, le plus récent d'abord
    notif_history.py delete <id>
    notif_history.py clear
    notif_history.py count
"""
import json
import os
import sys
from pathlib import Path

FILE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "notifications-history.jsonl"
MAX_ENTRIES = 200


def read_all():
    """Entrées du plus ancien au plus récent ; une ligne illisible est ignorée."""
    if not FILE.exists():
        return []
    out = []
    try:
        for line in FILE.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except Exception:
                continue
            if isinstance(entry, dict) and entry.get("id"):
                out.append(entry)
    except OSError:
        return []
    return out


def write_all(entries):
    FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILE.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        for entry in entries:
            fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
    os.replace(tmp, FILE)


def add(entry):
    entries = read_all()
    ids = {str(e.get("id")) for e in entries}
    ident = str(entry.get("id") or "")
    if not ident or ident in ids:
        base = str(entry.get("ts_ms") or int(__import__("time").time() * 1000))
        ident, n = base, 1
        while ident in ids:
            n += 1
            ident = f"{base}-{n}"
        entry["id"] = ident
    entries.append(entry)
    if len(entries) > MAX_ENTRIES:
        entries = entries[-MAX_ENTRIES:]
    write_all(entries)
    return entry["id"]


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "list"
    if action == "add":
        payload = sys.stdin.read()
        try:
            entry = json.loads(payload) if payload.strip() else {}
        except Exception:
            print("ajout refusé : JSON illisible", file=sys.stderr)
            return 1
        print(add(entry))
        return 0
    if action == "list":
        print(json.dumps(read_all()[::-1], ensure_ascii=False))
        return 0
    if action == "count":
        print(len(read_all()))
        return 0
    if action == "delete" and len(sys.argv) > 2:
        target = str(sys.argv[2])
        entries = read_all()
        kept = [e for e in entries if str(e.get("id")) != target]
        write_all(kept)
        print(len(entries) - len(kept))
        return 0
    if action == "clear":
        write_all([])
        print("ok")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
