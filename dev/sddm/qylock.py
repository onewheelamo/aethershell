#!/usr/bin/env python3
"""Thèmes SDDM de qylock, récupérés à la demande — jamais versionnés.

Amont : https://github.com/Darkkal44/qylock (GPL-3.0). Ses 39 thèmes pèsent
~595 Mo, essentiellement des fonds vidéo : les copier dans notre dépôt n'aurait
aucun sens (notre repo fait 30 Mo et voyage par rsync). Ce script ne télécharge
que les thèmes demandés, dans ~/.local/share/qylock-themes/<nom>/.

Ensuite :
  bash dev/sddm/install.sh --qylock <nom…>   pose les thèmes dans /usr/share
                                             (une invite polkit), sans toucher
                                             à la sélection courante
  panneau → Connexion                         les liste, les prévisualise,
                                             « Appliquer » sélectionne

Actions :
  qylock.py list                  thèmes du dépôt, récupérés et installés
  qylock.py fetch <nom…>          télécharge les thèmes nommés
  qylock.py fetch --static <nom…> idem en refusant un fond vidéo
  qylock.py fetch --all           tout le dépôt (~595 Mo, demande confirmation)

Le cache de l'arbre GitHub vit dans ~/.cache/quickshell/qylock-tree.json ;
QYLOCK_REFRESH=1 le rafraîchit après une mise à jour amont.
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import NoReturn

REPO = "Darkkal44/qylock"
TREE_URL = f"https://api.github.com/repos/{REPO}/git/trees/main?recursive=1"
RAW_URL = f"https://raw.githubusercontent.com/{REPO}/main/{{path}}"

CACHE = Path.home() / ".local/share/qylock-themes"
TREE_CACHE = Path.home() / ".cache/quickshell/qylock-tree.json"
SYS_THEMES = Path("/usr/share/sddm/themes")


def die(msg) -> NoReturn:
    print(f"qylock: {msg}", file=sys.stderr)
    sys.exit(1)


def human(n):
    return f"{n / 1e6:.1f} Mo" if n >= 1e6 else f"{n / 1e3:.0f} ko"


def tree():
    """Arbre du dépôt amont, mis en cache (une requête par mise à jour)."""
    if TREE_CACHE.exists() and not os.environ.get("QYLOCK_REFRESH"):
        try:
            return json.loads(TREE_CACHE.read_text())["tree"]
        except Exception:
            pass
    try:
        with urllib.request.urlopen(TREE_URL, timeout=30) as r:
            data = json.load(r)
    except Exception as ex:
        die(f"arbre GitHub illisible : {ex}")
    if "tree" not in data:
        die(f"réponse GitHub inattendue : {str(data)[:120]}")
    TREE_CACHE.parent.mkdir(parents=True, exist_ok=True)
    TREE_CACHE.write_text(json.dumps(data))
    return data["tree"]


def index():
    """{nom du thème: [entrées de fichiers]} depuis themes/<nom>/…"""
    out = {}
    for e in tree():
        if e.get("type") != "blob":
            continue
        parts = e["path"].split("/")
        if len(parts) < 3 or parts[0] != "themes":
            continue
        out.setdefault(parts[1], []).append(e)
    return out


def label(name):
    return name.replace("-", " ").replace("_", " ").strip().capitalize()


def variant_dirs(root):
    """Dossiers réellement installables : ceux qui portent un metadata.desktop.

    La plupart des thèmes sont un dossier plat ; `clockwork` en contient trois
    (neo-orbital, orbital, tape), chacun un thème complet. SDDM ne sait
    sélectionner qu'un dossier de premier niveau, donc l'installation les
    aplatit en `<parent>-<variante>`.
    """
    if not root.is_dir():
        return []
    found = [root] if (root / "metadata.desktop").exists() else []
    for sub in sorted(root.iterdir()):
        if sub.is_dir() and (sub / "metadata.desktop").exists():
            found.append(sub)
    return found


def state(name):
    """récupéré / installé, mesurés sur disque."""
    root = CACHE / name
    got = bool(variant_dirs(root))
    dirs = variant_dirs(root)
    installed = bool(dirs) and all(
        (SYS_THEMES / installed_name(name, d)).exists() for d in dirs)
    return got, installed


def installed_name(theme, path):
    """Nom du dossier dans /usr/share : plat, préfixé si le thème est imbriqué."""
    root = CACHE / theme
    return theme if path == root else f"{theme}-{path.name}"


def cmd_list():
    idx = index()
    rows = []
    for name in sorted(idx, key=label):
        files = idx[name]
        size = sum(f.get("size", 0) for f in files)
        video = any(f["path"].endswith((".mp4", ".webm", ".mkv")) for f in files)
        got, installed = state(name)
        rows.append({"name": name, "label": label(name), "size": size,
                     "video": video, "fetched": got, "installed": installed,
                     "variants": len(variant_dirs(CACHE / name))})
    print(json.dumps({"ok": True, "cache": str(CACHE), "themes": rows},
                     ensure_ascii=False, indent=1))


def fetch(name, entries, static_only):
    if static_only and any(e["path"].endswith((".mp4", ".webm", ".mkv")) for e in entries):
        die(f"{name} : fond vidéo, refusé par --static")
    total = sum(e.get("size", 0) for e in entries)
    print(f"▶ {label(name)} — {len(entries)} fichiers, {human(total)}")
    dest = CACHE / name
    failed = []
    for e in entries:
        rel = e["path"].split("/", 2)[2]
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() and target.stat().st_size == e.get("size", 0):
            continue
        # Les noms amont contiennent des espaces et des parenthèses (« A Glow
        # (1).jpg ») : sans encodage urllib refuse l'URL. safe="/" garde les
        # séparateurs de chemin.
        url = RAW_URL.format(path=urllib.parse.quote(e["path"], safe="/"))
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                target.write_bytes(r.read())
        except Exception as ex:
            # Un fichier amont manquant ne doit pas arrêter les 38 autres thèmes.
            print(f"  ✗ {rel} : {ex}", file=sys.stderr)
            failed.append(rel)
            continue
        print(f"  {rel} ({human(e.get('size', 0))})")
    vdirs = variant_dirs(dest)
    if not vdirs:
        for need in ("Main.qml", "metadata.desktop"):
            if not (dest / need).exists():
                die(f"{name} : {need} manquant après téléchargement")
    else:
        for d in vdirs:
            for need in ("Main.qml", "metadata.desktop"):
                if not (d / need).exists():
                    die(f"{name} ({d.name}) : {need} manquant après téléchargement")
    print(f"  → {dest}")
    return failed


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return
    action = args[0]
    idx = index()

    if action == "list":
        cmd_list()
        return

    if action != "fetch":
        die(f"action inconnue : {action}")

    rest = args[1:]
    static = "--static" in rest
    everything = "--all" in rest
    names = [a for a in rest if not a.startswith("--")]

    if everything:
        names = sorted(idx)
        total = sum(sum(f.get("size", 0) for f in idx[n]) for n in names)
        print(f"⚠ {len(names)} thèmes, {human(total)} au total "
              f"(dont des fonds vidéo jusqu'à 78 Mo)")
        if sys.stdin.isatty():
            if input("continuer ? [o/N] ").strip().lower() not in ("o", "oui", "y"):
                die("annulé")
        else:
            die("--all demande une confirmation interactive")
    if not names:
        die("aucun thème nommé (voir : qylock.py list)")

    unknown = [n for n in names if n not in idx]
    if unknown:
        die(f"thème inconnu : {', '.join(unknown)}")

    failures = []
    for n in names:
        failures += fetch(n, idx[n], static)
    if failures:
        print(f"\n⚠ {len(failures)} fichier(s) non récupéré(s) — relancer la commande "
              f"reprend là où ça s'est arrêté.", file=sys.stderr)
    print(f"\ninstaller : bash dev/sddm/install.sh --qylock {' '.join(names)}")


if __name__ == "__main__":
    main()
