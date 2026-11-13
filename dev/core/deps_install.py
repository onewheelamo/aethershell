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
# `pkg_for_bin` dans install.sh : elle doit rester alignée avec lui.
PAQUETS = {
    "arch": {
        "wpctl": "wireplumber",
        "nmcli": "networkmanager",
        "magick": "imagemagick",
        "inotifywait": "inotify-tools",
        "notify-send": "libnotify",
        "pactl": "libpulse",
        "powerprofilesctl": "power-profiles-daemon",
        "monitor-sensor": "iio-sensor-proxy",
        "cc": "gcc",
        "wl-copy": "wl-clipboard",
        "bluetoothctl": "bluez-utils",
        "matugen": "matugen-bin",
    },
    "fedora": {
        "wpctl": "wireplumber",
        "nmcli": "NetworkManager",
        "powerprofilesctl": "power-profiles-daemon",
        "monitor-sensor": "iio-sensor-proxy",
        "magick": "ImageMagick",
        "inotifywait": "inotify-tools",
        "notify-send": "libnotify",
        "pactl": "pulseaudio-utils",
        "cc": "gcc",
        "wl-copy": "wl-clipboard",
        "bluetoothctl": "bluez",
    },
    "debian": {
        "wpctl": "wireplumber",
        "nmcli": "network-manager",
        "powerprofilesctl": "power-profiles-daemon",
        "monitor-sensor": "iio-sensor-proxy",
        "magick": "imagemagick",
        "inotifywait": "inotify-tools",
        "notify-send": "libnotify-bin",
        "pactl": "pulseaudio-utils",
        "cc": "gcc",
        "wl-copy": "wl-clipboard",
        "bluetoothctl": "bluez",
    },
}

AUR_PAQUETS = {"quickshell", "matugen-bin", "awww", "hyprshot", "hyprsunset"}


def distribution():
    """« arch », « fedora », « debian »… lu dans /etc/os-release, comme install.sh."""
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
    id_like = champs.get("ID_LIKE", "").lower()
    if ident in ("arch", "fedora"):
        return ident
    if ident in ("debian", "ubuntu", "linuxmint", "pop", "elementary", "zorin", "kali"):
        return "debian"
    if "arch" in id_like:
        return "arch"
    if "fedora" in id_like or ident in ("rhel", "centos"):
        return "fedora"
    if "debian" in id_like or "ubuntu" in id_like:
        return "debian"
    return ident or "inconnue"


def forme_poste():
    """« laptop » si batterie ou châssis portable détecté, sinon « desktop »."""
    ps_dir = Path("/sys/class/power_supply")
    if ps_dir.is_dir() and any(ps_dir.glob("BAT*")):
        return "laptop"
    chassis = Path("/sys/class/dmi/id/chassis_type")
    if chassis.is_file():
        try:
            if chassis.read_text(encoding="utf-8", errors="replace").strip() in {"8", "9", "10", "14", "30", "31", "32"}:
                return "laptop"
        except OSError:
            pass
    return "desktop"


def binaires(distro, forme=None):
    """Binaires à contrôler : portée « commun », distro et forme du poste (laptop/desktop)."""
    if forme is None:
        forme = forme_poste()
    portees = {"commun", distro}
    if forme == "laptop":
        portees.update({"laptop", "portable"})
    elif forme == "desktop":
        portees.update({"desktop", "fixe"})
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


def binaire_present(binaire, distro):
    if shutil.which(binaire):
        return True
    if binaire == "magick" and distro == "debian" and shutil.which("convert"):
        return True
    return False


def commande(distro, paquets):
    if distro == "fedora":
        return ["dnf", "install", "-y"] + paquets
    if distro == "debian":
        return ["apt-get", "install", "-y"] + paquets
    if distro == "arch" and any(p in AUR_PAQUETS for p in paquets):
        for helper in ("yay", "paru"):
            if shutil.which(helper):
                return [helper, "-S", "--needed", "--noconfirm"] + paquets
    return ["pacman", "-S", "--needed", "--noconfirm"] + paquets


def main():
    if not DEPS.is_file():
        print("dependencies.txt introuvable : %s" % DEPS)
        return 2
    distro = distribution()
    table = PAQUETS.get(distro, {})
    manquants = [b for b in binaires(distro) if not binaire_present(b, distro)]
    if not manquants:
        print("tout est installé")
        return 0

    paquets = list(dict.fromkeys(table.get(b, b) for b in manquants))
    cmd = commande(distro, paquets)
    print("manquants : %s" % ", ".join(manquants))
    besoin_pkexec = cmd[0] not in ("yay", "paru")
    if besoin_pkexec and not shutil.which("pkexec"):
        print("pkexec absent — à lancer à la main : sudo %s" % " ".join(cmd))
        return 2

    exec_cmd = (["pkexec"] + cmd) if besoin_pkexec else cmd
    resultat = subprocess.run(exec_cmd)
    if resultat.returncode != 0:
        print("installation interrompue (code %d)" % resultat.returncode)
        return 1
    restants = [b for b in binaires(distro) if not binaire_present(b, distro)]
    if restants:
        print("encore absents : %s" % ", ".join(restants))
        return 1
    print("installés : %s" % ", ".join(paquets))
    return 0


if __name__ == "__main__":
    sys.exit(main())
