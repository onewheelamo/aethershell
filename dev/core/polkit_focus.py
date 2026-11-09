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
MOTIFS = ("polkit", "policykit", "partitionmanager", "gparted")


def _base_hypr():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid())), "hypr")


def _candidats():
    """Les signatures à essayer, du socket le plus récent au plus ancien.

    Trier les noms de dossier (`sorted(...)[-1]`) est un tri alphabétique : la
    « dernière » signature n'était pas la vivante. Et garder
    `HYPRLAND_INSTANCE_SIGNATURE` en tête est un piège quand le service est né
    d'une unité systemd qui la fige : après un redémarrage de Hyprland, la
    variable désigne une session morte. Le socket le plus récent d'abord, la
    variable seulement à défaut.
    """
    base = _base_hypr()
    vus, ordre = set(), []
    try:
        entrees = []
        for nom in os.listdir(base):
            sock = os.path.join(base, nom, ".socket2.sock")
            if os.path.exists(sock):
                entrees.append((os.stat(sock).st_mtime, nom))
        entrees.sort(reverse=True)
    except OSError:
        entrees = []
    for _, nom in entrees:
        if nom not in vus:
            vus.add(nom)
            ordre.append(nom)
    env = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if env and env not in vus:
        ordre.append(env)
    return ordre


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
    """Force le focus, puis vérifie que la fenêtre active a bien changé.

    Hyprland 0.57 (config Lua) réévalue l'argument de `hyprctl dispatch` comme du
    Lua : `dispatch focuswindow address:0x…` échoue au parsing (« ')' expected
    near 'address' ») et ne faisait donc jamais rien. Le dispatcher passe par
    `repl` ; la forme historique reste en repli pour une version antérieure.
    Trois essais : la fenêtre peut n'être pas encore mappée.
    """
    for _ in range(3):
        _hyprctl("repl", 'hl.dispatch(hl.dsp.focus({ window = "address:%s" }))' % adresse)
        time.sleep(0.12)
        courante = _fenetre_courante()
        if str(courante.get("address", "")).lower() == adresse.lower():
            return True
        _hyprctl("dispatch", "focuswindow", "address:" + adresse)
        time.sleep(0.12)
        courante = _fenetre_courante()
        if str(courante.get("address", "")).lower() == adresse.lower():
            return True
    return False


def _suivre(s):
    """Lit le flux d'événements jusqu'à ce que Hyprland le referme."""
    tampon = b""
    while True:
        morceau = s.recv(4096)
        if not morceau:
            return
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


def veiller():
    """Suit la session Hyprland vivante.

    La signature est relue à **chaque** tour : après un redémarrage du
    compositeur, l'ancien socket est mort et le service tournait en boucle
    dessus sans jamais accrocher la nouvelle session.
    """
    while True:
        for sig in _candidats():
            chemin = os.path.join(_base_hypr(), sig, ".socket2.sock")
            if not os.path.exists(chemin):
                continue
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                    s.connect(chemin)
                    _suivre(s)
            except (OSError, KeyError):
                continue
        time.sleep(1)   # aucun socket joignable, ou le flux s'est fermé : on retente


def main():
    if not _candidats():
        print("pas de session Hyprland", file=sys.stderr)
        return 1
    veiller()
    return 0


if __name__ == "__main__":
    sys.exit(main())
