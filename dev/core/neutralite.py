#!/usr/bin/env python3
"""Vérifie que le dépôt ne dépend d'aucun utilisateur ni d'aucune machine.

AetherShell doit s'installer sur la machine de quelqu'un d'autre. Une seule
référence en dur — `/home/quentin`, `C:\\Users\\…`, le nom d'hôte du poste qui a
servi à développer — et l'installation échoue chez lui, ou pire, elle écrit dans
un dossier qui n'existe pas.

Ce programme lit **les fichiers suivis** (`git ls-files`) et signale :

1. un chemin absolu de dossier personnel (`/home/<nom>`, `/Users/<nom>`) dont le
   nom n'est pas un espace réservé (`utilisateur`, `<utilisateur>`, `x`, `user`) ;
2. l'identifiant de la personne qui lance la vérification (`getpass.getuser()`) ;
3. le nom d'hôte de la machine (`socket.gethostname()`, et son premier label).

Sur une autre machine, il vérifie donc *son* utilisateur et *son* hôte : la règle
est structurelle, elle ne nomme personne dans le dépôt.

À faire dans le code, à la place :

    shell     "$HOME", "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    Python    Path.home(), os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    QML       Quickshell.env("HOME"), Quickshell.env("XDG_RUNTIME_DIR")
    systemd   %h (directive d'unité), jamais /home/<nom>

Usage :
    neutralite.py                       # vérifie et rend 1 si quelque chose est trouvé
    neutralite.py --liste               # liste ce qui serait signalé, sans juger
    neutralite.py --utilisateur=quentin --hote=portable   # éprouve le contrôle
"""

import getpass
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

# Noms de dossier personnel acceptés : des espaces réservés de documentation.
RESERVES = {"utilisateur", "<utilisateur>", "user", "x", "nom", "username",
            "you", "toi", "votre-nom", "$user", "$home"}

# Fichiers où le nom de la personne est légitime : l'attribution de licence.
# (Le programme lui-même est épargné plus bas : il cite les motifs.)
ATTRIBUTION = {"LICENSE", "COPYING"}

# Noms d'hôte trop banals pour être cherchés : « portable », « localhost » ou
# « archlinux » sont des mots du code et de la documentation (« la détection
# portable se base sur la batterie »). Les signaler noierait le vrai problème.
HOTES_GENERIQUES = {"localhost", "portable", "laptop", "desktop", "pc", "machine",
                    "ordinateur", "archlinux", "fedora", "local", "home", "host"}

# Une ligne peut porter une dérogation explicite : `neutralite:ok — <raison>`.
# Sert aux compatibilités assumées, par exemple un ancien nom de clé encore lu.
PRAGMA = "neutralite:ok"

# Fichiers dont le contenu est binaire ou illisible : on les saute.
SAUTE = re.compile(r"\.(png|jpe?g|webp|gif|ico|ttf|otf|woff2?|mp4|webm|pdf|zip|gz|xz|so|pyc)$", re.I)


def fichiers_suivis(racine: Path):
    sortie = subprocess.run(["git", "-C", str(racine), "ls-files", "-z"],
                            capture_output=True)
    for nom in sortie.stdout.split(b"\0"):
        if not nom:
            continue
        chemin = racine / nom.decode("utf-8", "surrogateescape")
        if SAUTE.search(chemin.name):
            continue
        yield chemin


def motifs(utilisateur: str, hotes: set[str]):
    """Les expressions à chercher, avec leur explication."""
    m = [
        ("chemin personnel en dur",
         re.compile(r"/(?:home|Users)/([A-Za-z0-9._-]+)"),
         "utiliser $HOME / Path.home() / Quickshell.env(\"HOME\")"),
    ]
    if utilisateur and utilisateur not in RESERVES:
        m.append((f"nom d'utilisateur « {utilisateur} »",
                  re.compile(rf"\b{re.escape(utilisateur)}\b", re.I),
                  "aucune référence à la personne qui développe"))
    for hote in sorted(hotes):
        if hote and len(hote) > 2 and hote.lower() not in HOTES_GENERIQUES:
            m.append((f"nom d'hôte « {hote} »",
                      re.compile(rf"\b{re.escape(hote)}\b", re.I),
                      "aucune référence à la machine qui a servi au développement"))
    return m


def main(argv):
    racine = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                                 capture_output=True, text=True).stdout.strip() or ".")
    utilisateur = getpass.getuser()
    hotes = {socket.gethostname(), socket.gethostname().split(".")[0]}
    liste_seule = "--liste" in argv
    # Pour éprouver le contrôle depuis une autre identité (tests, CI) : on ne
    # peut pas changer d'utilisateur dans ce programme, mais on peut lui dire
    # lequel simuler.
    for argument in argv:
        if argument.startswith("--utilisateur="):
            utilisateur = argument.split("=", 1)[1]
        elif argument.startswith("--hote="):
            hotes = {argument.split("=", 1)[1]}

    trouves = []
    for chemin in fichiers_suivis(racine):
        try:
            texte = chemin.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        relatif = chemin.relative_to(racine)
        for numero, ligne in enumerate(texte.splitlines(), 1):
            for nom, motif, remede in motifs(utilisateur, hotes):
                m = motif.search(ligne)
                if not m:
                    continue
                if nom == "chemin personnel en dur" and m.group(1).lower() in RESERVES:
                    continue
                # Le programme lui-même cite les motifs : on l'épargne.
                if str(relatif).endswith("neutralite.py") or chemin.name in ATTRIBUTION:
                    continue
                if PRAGMA in ligne:
                    continue
                trouves.append((str(relatif), numero, nom, m.group(0)[:40], remede))

    if liste_seule:
        for chemin, numero, nom, extrait, _ in trouves:
            print(f"{chemin}:{numero}: {nom} — {extrait}")
        return 0

    if not trouves:
        print(f"neutralite : rien à signaler pour « {utilisateur} » "
              f"sur « {socket.gethostname()} ».")
        return 0

    print(f"neutralite : {len(trouves)} référence(s) à éviter "
          f"(utilisateur « {utilisateur} », hôte « {socket.gethostname()} ») :\n")
    for chemin, numero, nom, extrait, remede in trouves:
        print(f"  {chemin}:{numero}")
        print(f"    {nom} — {extrait!r}")
        print(f"    à faire : {remede}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
