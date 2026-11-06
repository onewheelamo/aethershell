#!/usr/bin/env python3
"""État du premier lancement — ce que l'assistant de bienvenue doit afficher.

Sortie : un seul objet JSON sur stdout, lu par le panneau (main.qml).

    { "kb_layout": "fr",
      "dossiers": [{"nom": "Images", "xdg": "PICTURES", "chemin": "...", "existe": true}, ...],
      "programmes": [{"alias": "Terminal", "commande": "ghostty", "present": true,
                      "candidats": [{"nom": "Alacritty", "commande": "alacritty"}, ...]}, ...],
      "widgets": [{"type": "horloge", "label": "Horloge", "pose": false}, ...] }

Les candidats viennent des fichiers .desktop installés, filtrés par catégorie
freedesktop : on ne propose qu'un binaire réellement présent sur la machine, et
rien n'est écrit sans que l'utilisateur ne le valide.
"""
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE_DIR)
import config_manager as cm  # noqa: E402

DIRS = [
    ("Images", "PICTURES"),
    ("Vidéos", "VIDEOS"),
    ("Documents", "DOCUMENTS"),
    ("Musique", "MUSIC"),
]

# alias d'app_vars → catégories freedesktop qui savent le tenir. Le premier
# groupe est celui qu'on cherche ; le second sert de repli si le premier est vide
# (une machine sans FileManager déclaré propose au moins les gestionnaires).
ROLES = [
    ("Terminal", [["TerminalEmulator"]], []),
    ("Browser", [["WebBrowser"]], []),
    ("Files", [["FileManager"]], ["Utility"]),
    ("Video", [["Video"]], ["Player"]),
    ("Images", [["Viewer"]], ["Graphics"]),
    ("Editor", [["TextEditor"], ["Development"]], []),
    ("Music", [["Audio"]], []),
]

WIDGET_LABELS = {
    "horloge": "Horloge",
    "date": "Date",
    "meteo": "Météo",
    "combo": "Aperçu du jour",
    "musique": "Musique",
    "systeme": "Système",
    "reseau": "Réseau",
    "disques": "Disques",
    "homelab": "Homelab",
    "presse_papiers": "Presse-papiers",
    "deepseek": "DeepSeek",
    "ollama": "Ollama Cloud",
    "antigravity": "Antigravity",
}

DESKTOP_DIRS = [
    "/usr/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]


def xdg_dir(nom):
    """Chemin courant d'un dossier XDG (PICTURES, VIDEOS…)."""
    try:
        out = subprocess.run(["xdg-user-dir", nom], capture_output=True, text=True)
        chemin = out.stdout.strip()
        return chemin or os.path.expanduser("~")
    except OSError:
        return os.path.expanduser("~")


def binaire_present(commande):
    """Vrai si la commande (éventuellement suivie d'arguments) est exécutable."""
    commande = str(commande or "").strip()
    if not commande:
        return False
    try:
        parts = shlex.split(commande)
    except ValueError:
        parts = commande.split()
    if not parts:
        return False
    cible = parts[0]
    if cible.startswith("/"):
        return os.path.isfile(cible) and os.access(cible, os.X_OK)
    return shutil.which(cible) is not None


def parse_desktop(chemin):
    """Champs utiles d'un .desktop, ou None s'il ne doit pas apparaître."""
    champs = {}
    try:
        for ligne in chemin.read_text(encoding="utf-8", errors="replace").splitlines():
            if ligne.startswith("["):
                if champs:
                    break           # on ne lit que le premier groupe [Desktop Entry]
                continue
            if "=" not in ligne or ligne.lstrip().startswith("#"):
                continue
            cle, valeur = ligne.split("=", 1)
            champs.setdefault(cle.strip(), valeur.strip())
    except OSError:
        return None
    if champs.get("Type", "Application") != "Application":
        return None
    if champs.get("NoDisplay", "").lower() == "true" or champs.get("Hidden", "").lower() == "true":
        return None
    if not champs.get("Name") or not champs.get("Exec"):
        return None
    return champs


# Lanceurs qui ne sont pas le programme lui-même : garder « env » ou « flatpak »
# comme commande d'alias ne lancerait rien d'utile (et « env » sortait comme
# candidat pour la musique).
WRAPPERS = {"env", "sh", "bash", "flatpak", "wine", "gamemoderun", "primusrun",
            "systemd-run", "dbus-run-session", "setsid", "nohup"}


def exec_simple(exec_brut):
    """Binaire réellement lancé, sans marqueurs de champ (%U, @@u) ni lanceur."""
    try:
        parts = shlex.split(exec_brut)
    except ValueError:
        parts = exec_brut.split()
    for part in parts:
        if not part or part.startswith("-") or "=" in part:
            continue            # option ou affectation (« env FOO=bar cmd »)
        if os.path.basename(part) in WRAPPERS:
            continue
        return part
    return ""


def candidats(categories_voulues):
    """Programmes installés qui déclarent l'une des catégories demandées."""
    trouves = []
    vus = set()
    for dossier in DESKTOP_DIRS:
        base = Path(dossier)
        if not base.is_dir():
            continue
        for chemin in sorted(base.glob("*.desktop")):
            champs = parse_desktop(chemin)
            if not champs:
                continue
            cats = {c.strip() for c in champs.get("Categories", "").split(";") if c.strip()}
            if not cats.intersection(categories_voulues):
                continue
            commande = exec_simple(champs["Exec"])
            if not commande or commande in vus:
                continue
            if not binaire_present(commande):
                continue
            vus.add(commande)
            trouves.append({"nom": champs["Name"], "commande": commande})
    return trouves


def barre_courante():
    """Le bord de la barre principale d'après style_vars.json."""
    try:
        style = cm.load_json(cm.STYLE_FILE)
    except Exception:
        return "haut"
    if not isinstance(style, dict):
        return "haut"
    if style.get("bar_left") is True:
        return "cote-gauche"
    if style.get("bar_right") is True:
        return "cote-droite"
    if style.get("bar_bottom") is True:
        return "bas"
    return "haut"


def main():
    apps = cm.load_json(cm.APP_VARS_FILE)

    dossiers = []
    for nom, cle in DIRS:
        chemin = xdg_dir(cle)
        dossiers.append({"nom": nom, "xdg": cle, "chemin": chemin,
                         "existe": os.path.isdir(chemin)})

    programmes = []
    for alias, groupes, repli in ROLES:
        commande = str(apps.get(alias) or "")
        liste = []
        for groupe in groupes + ([repli] if repli else []):
            liste = candidats(groupe)
            if liste:
                break
        programmes.append({
            "alias": alias,
            "commande": commande,
            "present": binaire_present(commande),
            "candidats": liste[:6],
        })

    poses = {str(w.get("type")) for w in cm.load_widgets()}
    widgets = [{"type": t, "label": WIDGET_LABELS.get(t, t), "pose": t in poses}
               for t in cm.WIDGET_TYPES]

    print(json.dumps({
        "kb_layout": cm.get_kb_layout(),
        "dossiers": dossiers,
        "programmes": programmes,
        "widgets": widgets,
        # Barre principale actuelle : au premier lancement aucune barre annexe
        # n'est allumée, donc « haut » ; en relançant l'assistant, la page
        # retrouve le choix déjà fait.
        "barre": barre_courante(),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
