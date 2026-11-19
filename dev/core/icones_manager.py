#!/usr/bin/env python3
"""Gestionnaire de thèmes et packs d'icônes (liste, aperçu, activation, installation).

Commandes :
  icones_manager.py list
  icones_manager.py apply <theme>
  icones_manager.py install <archive>
  icones_manager.py remove <theme>
"""
from __future__ import annotations

import configparser
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ICI = Path(__file__).resolve().parent
USER_ICONS_DIR = Path(os.path.expanduser("~/.local/share/icons"))
SYS_ICONS_DIR = Path("/usr/share/icons")
QT6CT_CONF = Path(os.path.expanduser("~/.config/qt6ct/qt6ct.conf"))
GTK3_INI = Path(os.path.expanduser("~/.config/gtk-3.0/settings.ini"))
GTK4_INI = Path(os.path.expanduser("~/.config/gtk-4.0/settings.ini"))

APERCUS_CANDIDATS = (
    "utilities-terminal",
    "firefox",
    "system-file-manager",
    "preferences-system",
    "folder",
    "vlc",
    "code",
)
IGNORES = {"default", "hicolor", "locolor"}


def _lire_theme_actif():
    try:
        for line in QT6CT_CONF.read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.strip().startswith("icon_theme="):
                val = line.split("=", 1)[1].strip()
                if val:
                    return val
    except OSError:
        pass
    try:
        cp = configparser.ConfigParser()
        cp.read(GTK3_INI, encoding="utf-8")
        val = cp.get("Settings", "gtk-icon-theme-name", fallback="").strip()
        if val:
            return val
    except Exception:
        pass
    return ""


def _parse_index_theme(index_path):
    nom = index_path.parent.name
    hidden = False
    has_dirs = False
    try:
        in_main = False
        for raw in index_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if line.startswith("["):
                in_main = (line == "[Icon Theme]")
                continue
            if not in_main or "=" not in line:
                continue
            k, _, v = line.partition("=")
            k, v = k.strip(), v.strip()
            if k == "Name" and v:
                nom = v
            elif k == "Hidden" and v.lower() == "true":
                hidden = True
            elif k == "Directories" and v:
                has_dirs = True
    except OSError:
        return None
    if hidden or not has_dirs:
        return None
    # Exclure les thèmes purement curseurs (uniquement cursors/ sans icônes apps/places)
    parent = index_path.parent
    if (parent / "cursors").is_dir() and not any(
        (parent / d).is_dir() for d in ("apps", "48x48", "scalable", "places", "actions", "status")
    ):
        return None
    return nom


def _trouver_apercus(theme_dir):
    trouves = []
    exts = (".svg", ".png")
    cibles = set(APERCUS_CANDIDATS)
    for dirpath, _, filenames in os.walk(theme_dir):
        if "/cursors" in dirpath or "/16" in dirpath:
            continue
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() not in exts:
                continue
            if p.stem in cibles:
                trouves.append((APERCUS_CANDIDATS.index(p.stem), 0 if p.suffix == ".svg" else 1, str(p)))
    par_nom = {}
    for idx, prio, chemin in sorted(trouves):
        if idx not in par_nom:
            par_nom[idx] = chemin
    return [par_nom[k] for k in sorted(par_nom)][:4]


def lister_themes():
    actif = _lire_theme_actif()
    vus = {}
    for is_user, root in ((True, USER_ICONS_DIR), (False, SYS_ICONS_DIR)):
        if not root.is_dir():
            continue
        for entree in sorted(root.iterdir()):
            if not entree.is_dir() or entree.name in IGNORES or entree.name.startswith("."):
                continue
            idx = entree / "index.theme"
            if not idx.is_file():
                continue
            nom = _parse_index_theme(idx)
            if not nom:
                continue
            if entree.name in vus:
                continue
            vus[entree.name] = {
                "id": entree.name,
                "nom": nom,
                "chemin": str(entree),
                "utilisateur": is_user,
                "apercu": _trouver_apercus(entree),
            }
    themes = sorted(vus.values(), key=lambda t: (t["id"] != actif, not t["utilisateur"], t["nom"].lower()))
    return {"ok": True, "actif": actif, "themes": themes}


def _maj_qt6ct(theme):
    QT6CT_CONF.parent.mkdir(parents=True, exist_ok=True)
    lignes = []
    trouve = False
    in_app = False
    if QT6CT_CONF.is_file():
        for raw in QT6CT_CONF.read_text(encoding="utf-8", errors="ignore").splitlines():
            s = raw.strip()
            if s.startswith("["):
                if in_app and not trouve:
                    lignes.append(f"icon_theme={theme}")
                    trouve = True
                in_app = (s == "[Appearance]")
            elif in_app and s.startswith("icon_theme="):
                lignes.append(f"icon_theme={theme}")
                trouve = True
                continue
            lignes.append(raw)
    if not trouve:
        if not in_app:
            lignes.append("[Appearance]")
        lignes.append(f"icon_theme={theme}")
    QT6CT_CONF.write_text("\n".join(lignes) + "\n", encoding="utf-8")


def _maj_gtk_ini(chemin, theme):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    cp = configparser.ConfigParser()
    if chemin.is_file():
        cp.read(chemin, encoding="utf-8")
    if "Settings" not in cp:
        cp["Settings"] = {}
    cp["Settings"]["gtk-icon-theme-name"] = theme
    with open(chemin, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)


def appliquer_theme(theme):
    theme = str(theme or "").strip()
    if not theme:
        return {"ok": False, "error": "nom de thème vide"}
    _maj_qt6ct(theme)
    _maj_gtk_ini(GTK3_INI, theme)
    _maj_gtk_ini(GTK4_INI, theme)
    if shutil.which("gsettings"):
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", theme],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
    app_idx = ICI / "app_index.py"
    if app_idx.is_file():
        subprocess.run([sys.executable, str(app_idx), "--quiet"], check=False)
    res = lister_themes()
    res["message"] = f"Thème « {theme} » appliqué"
    return res


def _extraire_sur(archive_path, dest_dir):
    nom = archive_path.name.lower()
    dest_real = dest_dir.resolve()
    if nom.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as zf:
            for member in zf.infolist():
                cible = (dest_real / member.filename).resolve()
                if not str(cible).startswith(str(dest_real)):
                    raise ValueError("Chemin invalide dans l'archive")
            zf.extractall(dest_real)
    elif nom.endswith((".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tar")):
        with tarfile.open(archive_path, "r:*") as tf:
            for member in tf.getmembers():
                cible = (dest_real / member.name).resolve()
                if not str(cible).startswith(str(dest_real)):
                    raise ValueError("Chemin invalide dans l'archive")
            tf.extractall(dest_real)
    elif nom.endswith(".tar.zst") and shutil.which("tar"):
        subprocess.run(["tar", "--zstd", "-xf", str(archive_path), "-C", str(dest_real)], check=True)
    else:
        raise ValueError("Format non supporté (attendu .tar.gz, .tar.xz, .tar.zst ou .zip)")


def installer_pack(archive):
    archive_path = Path(os.path.expanduser(str(archive or "").strip()))
    if not archive_path.is_file():
        return {"ok": False, "error": f"Archive introuvable : {archive_path}"}

    USER_ICONS_DIR.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path(tempfile.mkdtemp(prefix=".tmp_icon_pack_", dir=str(USER_ICONS_DIR)))
    installes = []
    try:
        _extraire_sur(archive_path, tmp_dir)
        candidats = []
        for idx in sorted(tmp_dir.rglob("index.theme")):
            # Ne pas prendre un sous-dossier si son parent immédiat est déjà un thème
            if any(p in candidats for p in idx.parent.parents):
                continue
            if _parse_index_theme(idx):
                candidats.append(idx.parent)
        for src in candidats:
            dest = USER_ICONS_DIR / src.name
            if dest.exists():
                shutil.rmtree(dest)
            shutil.move(str(src), str(dest))
            installes.append(src.name)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

    if not installes:
        return {"ok": False, "error": "Aucun thème d'icônes valide (index.theme) trouvé dans l'archive."}
    res = lister_themes()
    res["installed"] = installes
    res["message"] = "Installé : " + ", ".join(installes)
    return res


def supprimer_theme(theme):
    theme = str(theme or "").strip()
    cible = (USER_ICONS_DIR / theme).resolve()
    if not theme or cible.parent != USER_ICONS_DIR.resolve() or not cible.is_dir():
        return {"ok": False, "error": "Seuls les thèmes installés dans ~/.local/share/icons peuvent être supprimés."}
    shutil.rmtree(cible)
    res = lister_themes()
    res["message"] = f"Thème « {theme} » supprimé"
    return res


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "list"
    if action == "list":
        res = lister_themes()
    elif action == "apply" and len(sys.argv) > 2:
        res = appliquer_theme(sys.argv[2])
    elif action == "install" and len(sys.argv) > 2:
        res = installer_pack(sys.argv[2])
    elif action == "remove" and len(sys.argv) > 2:
        res = supprimer_theme(sys.argv[2])
    else:
        res = {"ok": False, "error": "Action inconnue"}
    print(json.dumps(res, ensure_ascii=False))


if __name__ == "__main__":
    main()
