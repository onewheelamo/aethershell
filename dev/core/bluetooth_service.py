#!/usr/bin/env python3
"""Bluetooth : adaptateur, appareils appairés, connexion.

Alimente le bloc Bluetooth du panneau réseau (ReseauApplet.qml). Tout passe par
`bluetoothctl` en mode non interactif — pas de démon à nous, pas d'état
dupliqué : le service système reste la seule vérité.

    python3 bluetooth_service.py etat
    python3 bluetooth_service.py basculer | activer | desactiver
    python3 bluetooth_service.py connecter <mac>
    python3 bluetooth_service.py deconnecter <mac>
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time

DELAI = 8


def _ctl(*args, timeout=DELAI):
    if not shutil.which("bluetoothctl"):
        return ""
    try:
        return subprocess.run(["bluetoothctl"] + list(args), capture_output=True,
                              text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _ligne_adresse(ligne):
    """« Device AA:BB:CC:DD:EE:FF Nom de l'appareil » → (mac, nom)."""
    m = re.match(r"^Device\s+([0-9A-Fa-f:]{17})\s*(.*)$", ligne.strip())
    if not m:
        return None
    return m.group(1).upper(), (m.group(2).strip() or m.group(1).upper())


def _appareils(sous_commande):
    out = []
    for ligne in _ctl("devices", sous_commande).splitlines():
        paire = _ligne_adresse(ligne)
        if paire:
            out.append(paire)
    return out


def etat():
    if not shutil.which("bluetoothctl"):
        return {"present": False}

    show = _ctl("show")
    allume = bool(re.search(r"^\s*Powered:\s*yes", show, re.MULTILINE))
    if "Controller" not in show:
        return {"present": False, "erreur": "aucun adaptateur"}

    adresse = ""
    m = re.search(r"Controller\s+([0-9A-Fa-f:]{17})", show)
    if m:
        adresse = m.group(1).upper()

    connectes = {mac: nom for mac, nom in _appareils("Connected")}
    appaires = []
    for mac, nom in _appareils("Paired"):
        appaires.append({"mac": mac, "nom": nom, "connecte": mac in connectes})
    # Un appareil connecté mais non appairé (rare) ne doit pas disparaître.
    connus = {a["mac"] for a in appaires}
    for mac, nom in connectes.items():
        if mac not in connus:
            appaires.append({"mac": mac, "nom": nom, "connecte": True})

    return {
        "present": True,
        "allume": allume,
        "adresse": adresse,
        "connectes": [{"mac": m, "nom": n} for m, n in connectes.items()],
        "appaires": appaires,
    }


def _allume_maintenant():
    """Lecture courte : `bluetoothctl show` seul, pour une attente serrée."""
    return bool(re.search(r"^\s*Powered:\s*yes", _ctl("show"), re.MULTILINE))


def basculer(vouloir=None):
    e = etat()
    if not e.get("present"):
        return e
    cible = (not e["allume"]) if vouloir is None else bool(vouloir)
    _ctl("power", "on" if cible else "off", timeout=12)
    # L'adaptateur met un instant à basculer côté D-Bus : relire juste après
    # rendait l'ancien état, et le commutateur du panneau revenait tout seul.
    # On attend que BlueZ confirme, 2 s au maximum.
    fin = time.monotonic() + 2.0
    while time.monotonic() < fin:
        if _allume_maintenant() == cible:
            break
        time.sleep(0.1)
    return etat()


def connecter(mac, vouloir=True):
    _ctl("connect" if vouloir else "disconnect", mac, timeout=15)
    return etat()


def main(argv):
    action = (argv[1] if len(argv) > 1 else "etat").strip()

    if action == "etat":
        print(json.dumps(etat(), ensure_ascii=False))
        return 0
    if action in ("basculer", "activer", "desactiver"):
        vouloir = None if action == "basculer" else action == "activer"
        print(json.dumps(basculer(vouloir), ensure_ascii=False))
        return 0
    if action in ("connecter", "deconnecter") and len(argv) > 2:
        print(json.dumps(connecter(argv[2].strip(), action == "connecter"),
                         ensure_ascii=False))
        return 0

    print(json.dumps({"erreur": "action inconnue"}, ensure_ascii=False))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
