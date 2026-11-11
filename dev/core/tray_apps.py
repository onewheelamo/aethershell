#!/usr/bin/env python3
"""Double clic sur une icône du systray : ouvrir la fenêtre de l'application.

`activate()` (l'appel StatusNotifierItem) ne suffit pas : les items publiés avec
`ItemIsMenu = true` — Proton VPN, par exemple — n'ont pas de handler Activate du
tout, l'appel ne fait rien. On décide donc ici, dans cet ordre :

  1. **une fenêtre existe déjà** (l'app tourne en arrière-plan, réduite ou sur un
     autre bureau) → on la met au premier plan via Hyprland ;
  2. **sinon** → on lance son entrée .desktop, en se plaçant dans `$HOME` comme
     le fait la pilule spotlight ;
  3. **rien de tout ça** → code 3, et le QML retombe sur `activate()`.

Le rapprochement se fait par jetons normalisés (minuscules alphanumériques, mots
génériques retirés) : `Proton Pass_status_icon_1` → {proton, pass}, qui ne
rencontre que la fenêtre de Proton Pass.

Usage :
    tray_apps.py <id-item> [<titre-item>] [--dry-run]
"""
import json
import subprocess
import sys
from pathlib import Path

# La règle de rapprochement classe ↔ .desktop vit dans `app_classes.py` : elle
# sert aussi à l'applet des fenêtres minimisées, et deux copies divergeraient au
# premier correctif.
from app_classes import couvre, jetons

INDEX = Path(__file__).resolve().parent / "app_index.json"


def fenetres():
    """Fenêtres ouvertes, vues par Hyprland."""
    try:
        sortie = subprocess.run(["hyprctl", "clients", "-j"],
                                capture_output=True, text=True, check=True).stdout
        return json.loads(sortie)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        return []


def choisir_fenetre(recherche, clients):
    """Fenêtre la plus proche (la plus récemment utilisée à égalité), ou None."""
    candidates = []
    for c in clients:
        candidat = jetons(c.get("class", "")) | jetons(c.get("title", ""))
        if couvre(recherche, candidat):
            # Moins de jetons en trop = rapprochement plus précis ; à égalité,
            # l'historique de focus de Hyprland tranche (0 = la plus récente).
            candidates.append((len(candidat), c.get("focusHistoryID", 9999), c))
    if not candidates:
        return None
    candidates.sort(key=lambda t: (t[0], t[1]))
    return candidates[0][2]


def entrees_desktop():
    try:
        return json.loads(INDEX.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []


def choisir_desktop(recherche, index):
    """Entrée .desktop dont le nom de fichier reconnaît tous les jetons cherchés.

    `proton.vpn.app.gtk` → `proton.vpn.app.gtk.desktop` ; `Strawberry` →
    `org.strawberrymusicplayer.strawberry.desktop`. La contrainte « tous les
    jetons » évite que `proton` seul ramène Proton Pass ; le tri préfère le nom
    exact, puis celui qui ajoute le moins de mots (`proton.vpn.app.gtk` ne doit
    pas tomber sur `proton-pass`).
    """
    distinctifs = {j for j in recherche if len(j) >= 3}
    if not distinctifs:
        return None
    candidates = []
    for e in index:
        stem = jetons(str(e.get("desktop", "")).removesuffix(".desktop"))
        if couvre(distinctifs, stem):
            candidates.append((0 if stem == distinctifs else 1, len(stem - distinctifs), e))
    if not candidates:
        return None
    candidates.sort(key=lambda t: (t[0], t[1]))
    return candidates[0][2]


def lancer(commande):
    # Même forme que la pilule : un lanceur part de $HOME, pas du dossier du
    # shell (hérité de Quickshell). `setsid` détache l'application.
    subprocess.Popen(["setsid", "sh", "-c", 'cd "$HOME" && exec ' + commande],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    sec = "--dry-run" in sys.argv
    if not args:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2

    item_id = args[0]
    titre = args[1] if len(args) > 1 else ""
    recherche = jetons(item_id) | jetons(titre)

    win = choisir_fenetre(recherche, fenetres())
    if win:
        adresse = win.get("address", "")
        if sec:
            print("focus %s (%s)" % (adresse, win.get("class", "")))
            return 0
        subprocess.run(["hyprctl", "dispatch",
                        'hl.dsp.focus({ window = "address:%s" })' % adresse],
                       check=False)
        return 0

    entree = choisir_desktop(recherche, entrees_desktop())
    if entree:
        if sec:
            print("lance %s → %s" % (entree.get("desktop"), entree.get("exec")))
            return 0
        lancer(str(entree.get("exec", "")))
        return 0

    if sec:
        print("rien (activate() au choix du QML)")
    return 3


if __name__ == "__main__":
    sys.exit(main())
