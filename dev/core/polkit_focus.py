#!/usr/bin/env python3
"""Donne le focus à l'invite d'authentification polkit dès qu'elle apparaît.

Hyprland applique une prévention contre le vol de focus : une fenêtre ouverte par
un service en arrière-plan (ici l'agent polkit, lancé par systemd) peut s'afficher
sans recevoir le clavier. L'invite reste alors invisible à l'usage — on tape dans
la fenêtre d'en dessous.

Ce veilleur écoute le flux d'événements de Hyprland (`socket2`), et à chaque
ouverture de fenêtre dont la classe contient « polkit », il force le focus dessus.
Rien à installer : bibliothèque standard seulement.

    python3 polkit_focus.py
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time

# Classes dont l'ouverture doit amener le clavier. L'invite polkit d'abord ; le
# gestionnaire de disques ensuite, car il est lancé depuis un popup de la barre
# qui garde un attrapeur de clavier : sa fenêtre s'ouvre parfois derrière.
MOTIFS = ("polkit", "partitionmanager", "gparted")


def _signature():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        return sig
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid())), "hypr")
    try:
        entrees = sorted(os.listdir(base))
    except OSError:
        return None
    return entrees[-1] if entrees else None


def _hyprctl(*args):
    try:
        return subprocess.run(["hyprctl"] + list(args), capture_output=True, text=True,
                              timeout=4).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _fenetre_courante():
    try:
        return json.loads(_hyprctl("activewindow", "-j") or "{}")
    except ValueError:
        return {}


def _concentrer(adresse):
    """Force le focus, puis vérifie : `focuswindow` peut être refusé si la fenêtre
    n'est pas encore mappée. Deux essais suffisent en pratique."""
    for _ in range(3):
        _hyprctl("dispatch", "focuswindow", "address:" + adresse)
        time.sleep(0.12)
        courante = _fenetre_courante()
        if str(courante.get("address", "")).lower() == adresse.lower():
            return True
    return False


def veiller(sig):
    chemin = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid())),
                          "hypr", sig, ".socket2.sock")
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(chemin)
                tampon = b""
                while True:
                    morceau = s.recv(4096)
                    if not morceau:
                        break
                    tampon += morceau
                    while b"\n" in tampon:
                        ligne, tampon = tampon.split(b"\n", 1)
                        texte = ligne.decode("utf-8", "replace")
                        # openwindow>>0x55d3…,1,classe,titre
                        if not texte.startswith("openwindow>>"):
                            continue
                        morceaux = texte[len("openwindow>>"):].split(",")
                        if len(morceaux) < 3:
                            continue
                        adresse = morceaux[0].strip()
                        classe = morceaux[2].strip().lower()
                        if any(m in classe for m in MOTIFS):
                            _concentrer(adresse)
        except (OSError, KeyError):
            pass
        time.sleep(1)   # Hyprland a redémarré ou le flux s'est fermé : on retente


def main():
    sig = _signature()
    if not sig:
        print("pas de session Hyprland", file=sys.stderr)
        return 1
    veiller(sig)
    return 0


if __name__ == "__main__":
    sys.exit(main())
