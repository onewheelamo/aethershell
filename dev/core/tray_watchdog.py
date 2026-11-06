#!/usr/bin/env python3
"""Rétablit les items du systray dont l'application ne s'est pas ré-enregistrée.

    tray_watchdog.py [--once] [--interval SECONDES]

Certaines applications ne réagissent pas à l'apparition d'un **nouveau**
StatusNotifierWatcher : leur item reste vivant sur le bus, mais n'est plus dans la
liste du watcher, donc le shell ne l'affiche plus jusqu'au redémarrage de
l'application. C'est le cas de ProtonVPN, qui disparaît de la barre à chaque
redémarrage de Quickshell, alors que le moniteur de casque et les Flatpak se
réenregistrent d'eux-mêmes.

Le gardien compare les services `org.kde.StatusNotifierItem-*` du bus à la liste
du watcher et rappelle `RegisterStatusNotifierItem` pour les seuls absents —
opération sans effet quand l'item est déjà enregistré, donc aucun doublon.

Il sort de lui-même si le watcher n'a plus de propriétaire (shell arrêté) ou s'il
est orphelin (parent pid 1), pour ne pas survivre à la session qu'il surveille.
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

WATCHER = "org.kde.StatusNotifierWatcher"
PATH = "/StatusNotifierWatcher"
IFACE = "org.kde.StatusNotifierWatcher"


def busctl(*args):
    return subprocess.run(["busctl", "--user", *args], capture_output=True, text=True)


def watcher_items():
    """Liste des items enregistrés, telle que le shell la voit."""
    out = busctl("get-property", WATCHER, PATH, IFACE, "RegisteredStatusNotifierItems")
    if out.returncode != 0:
        return None  # watcher absent
    return [tok.strip('"') for tok in out.stdout.split() if tok.startswith('"')]


def live_items():
    """Services SNI vivants sur le bus : ceux que le shell devrait voir."""
    out = busctl("list", "--no-legend")
    services = []
    for line in out.stdout.splitlines():
        parts = line.split()
        if not parts:
            continue
        name = parts[0]
        # Un item s'enregistre soit sous un nom de service, soit sous son nom unique.
        # Les seconds se réenregistrent seuls (cas des Flatpak et du moniteur de
        # casque) : on ne touche qu'aux noms de service.
        if name.startswith("org.kde.StatusNotifierItem-"):
            services.append(name)
    return services


def watcher_alive():
    out = busctl("status", WATCHER)
    return out.returncode == 0 and "PID=" in out.stdout


def heal(verbose=False):
    registered = watcher_items()
    if registered is None:
        return None
    # Le watcher rend « nom/chemin » ou le nom du service : on compare sur le nom.
    have = set()
    for entry in registered:
        have.add(entry.split("/")[0])
    healed = []
    for service in live_items():
        if service in have:
            continue
        out = busctl("call", WATCHER, PATH, IFACE, "RegisterStatusNotifierItem", "s", service)
        if out.returncode == 0:
            healed.append(service)
            if verbose:
                print(f"ré-enregistré : {service}", flush=True)
    return healed


def main():
    argv = sys.argv[1:]
    once = "--once" in argv
    interval = 10
    if "--interval" in argv:
        idx = argv.index("--interval")
        if idx + 1 < len(argv):
            interval = max(2, int(argv[idx + 1]))

    parent = os.getppid()
    # Le gardien est lancé par le shell au démarrage, souvent **avant** que le
    # StatusNotifierWatcher ne soit publié sur le bus. Sortir au premier constat
    # d'absence le rendait inutile pour toute la session — c'est ce qui laissait
    # ProtonVPN sans icône. On laisse donc au shell le temps d'apparaître.
    absences = 0
    while True:
        if os.getppid() == 1 and parent != 1:
            return 0  # orphelin : la session qui nous a lancés est partie
        if not watcher_alive():
            absences += 1
            if absences >= 6:      # ~30 s de patience, puis le shell a disparu
                return 0
        else:
            absences = 0
            heal(verbose=True)
        if once:
            return 0
        time.sleep(interval if absences == 0 else 3)


if __name__ == "__main__":
    sys.exit(main())
