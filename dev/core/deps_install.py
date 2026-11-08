#!/usr/bin/env python3
"""Installer les paquets que `dependencies.txt` réclame et qui manquent ici.

Le panneau (onglet « Apps & Alertes ») appelle ce script ; il ne fait que ce que
`deploy.sh --deps` **affiche**, mais en installant. Rien n'est deviné : la liste
vient du fichier déployé avec le shell (`core/dependencies.txt`), chaque portée
est filtrée sur la distribution courante, et un binaire déjà présent n'est jamais
réinstallé.

L'élévation passe par `pkexec` — l'agent polkit du shell affiche la demande dans
la session, sans terminal ni mot de passe tapé dans le vide. Sans `pkexec`, le
script imprime la commande et sort en 2 : le panneau ne lance rien à l'aveugle.

Codes de sortie :
    0  tout est là, ou installation réussie
    1  installation refusée ou en échec
    2  `pkexec` absent (commande affichée), ou fichier de dépendances introuvable
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent
DEPS = RACINE / "dependencies.txt"

# Binaire → paquet, quand les deux n'ont pas le même nom. Même table que
# `pkg_for_bin` dans deploy.sh : elle doit rester alignée avec lui.
PAQUETS = {
    "arch": {"wpctl": "wireplumber", "nmcli": "networkmanager", "magick": "imagemagick"},
    "fedora": {
        "wpctl": "wireplumber",
        "nmcli": "NetworkManager",
        "powerprofilesctl": "power-profiles-daemon",
        "monitor-sensor": "iio-sensor-proxy",
        "magick": "ImageMagick",
    },
}


def distribution():
    """« arch », « fedora »… lu dans /etc/os-release, comme deploy.sh."""
    texte = ""
    try:
        texte = Path("/etc/os-release").read_text(encoding="utf-8", errors="replace")
    except OSError:
        return "inconnue"
    champs = {}
    for ligne in texte.splitlines():
        if "=" in ligne:
            cle, _, valeur = ligne.partition("=")
            champs[cle.strip()] = valeur.strip().strip('"')
    ident = champs.get("ID", "").lower()
    if ident in ("arch", "fedora"):
        return ident
    if "arch" in champs.get("ID_LIKE", ""):
        return "arch"
    if "fedora" in champs.get("ID_LIKE", "") or ident in ("rhel", "centos"):
        return "fedora"
    return ident or "inconnue"


def binaires(distro):
    """Binaires à contrôler : portée « commun » plus celle de la distribution."""
    portees = {"commun", distro}
    gardes, courante = [], None
    for ligne in DEPS.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") and not ligne.startswith("#:"):
            continue
        m = re.match(r"^#:\s*(\w+)", ligne)
        if m:
            courante = m.group(1).lower()
            continue
        if courante in portees:
            gardes.append(ligne.split()[0])
    return gardes


def commande(distro, paquets):
    if distro == "fedora":
        return ["dnf", "install", "-y"] + paquets
    return ["pacman", "-S", "--needed", "--noconfirm"] + paquets


def main():
    if not DEPS.is_file():
        print("dependencies.txt introuvable : %s" % DEPS)
        return 2
    distro = distribution()
    table = PAQUETS.get(distro, {})
    manquants = [b for b in binaires(distro) if not shutil.which(b)]
    if not manquants:
        print("tout est installé")
        return 0

    paquets = [table.get(b, b) for b in manquants]
    cmd = commande(distro, paquets)
    print("manquants : %s" % ", ".join(manquants))
    if not shutil.which("pkexec"):
        print("pkexec absent — à lancer à la main : sudo %s" % " ".join(cmd))
        return 2

    resultat = subprocess.run(["pkexec"] + cmd)
    if resultat.returncode != 0:
        print("installation interrompue (code %d)" % resultat.returncode)
        return 1
    restants = [b for b in binaires(distro) if not shutil.which(b)]
    if restants:
        print("encore absents : %s" % ", ".join(restants))
        return 1
    print("installés : %s" % ", ".join(paquets))
    return 0


if __name__ == "__main__":
    sys.exit(main())
