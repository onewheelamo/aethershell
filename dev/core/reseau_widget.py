#!/usr/bin/env python3
"""Widget « Réseau » : ce que la barre ne peut pas dire.

L'applet de la barre tient en une icône et un pourcentage de signal. Ce service
prépare la version détaillée pour le widget de bureau : bande et canal, débits
négociés, adresse et passerelle, trafic réel, latence et VPN actif.

    python3 reseau_widget.py [--force]

Sortie : un JSON sur une ligne. Tout champ absent (pas de Wi-Fi, pas de VPN,
passerelle injoignable) est simplement omis : le widget n'affiche que ce qu'il
reçoit, et ne casse pas sur une machine filaire.
"""
from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import sys
import time

# Deux fichiers distincts : l'un garde les compteurs pour calculer le débit,
# l'autre la dernière analyse (le widget peut demander plusieurs fois par seconde).
ETAT = os.path.join(os.path.expanduser("~"), ".cache", "quickshell", "reseau_etat.json")
CACHE = os.path.join(os.path.expanduser("~"), ".cache", "quickshell", "reseau_cache.json")
DELAI = 3


def _run(cmd, timeout=DELAI):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _interface_active():
    """(interface, connexion NetworkManager) — la première connexion non virtuelle."""
    sortie = _run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"])
    for ligne in sortie.splitlines():
        morceaux = ligne.split(":")
        if len(morceaux) < 4:
            continue
        dev, nature, etat, connexion = morceaux[0], morceaux[1], morceaux[2], morceaux[3]
        if nature not in ("wifi", "ethernet"):
            continue
        if not etat.startswith("connected"):
            continue
        return dev, nature, connexion
    return "", "", ""


def _wifi(dev):
    """SSID, signal, fréquence et débits négociés, lus chez le noyau (iw)."""
    infos = {}
    lien = _run(["iw", "dev", dev, "link"])
    if "Not connected" in lien or not lien.strip():
        return infos
    m = re.search(r"SSID:\s*(.+)", lien)
    if m:
        infos["ssid"] = m.group(1).strip()
    m = re.search(r"freq:\s*([\d.]+)", lien)
    if m:
        freq = float(m.group(1))
        infos["frequence"] = round(freq)
        # 2,4 / 5 / 6 GHz : c'est le repère que tout le monde connaît.
        if freq < 3000:
            infos["bande"] = "2,4 GHz"
            infos["canal"] = round((freq - 2407) / 5)
        elif freq < 5925:
            infos["bande"] = "5 GHz"
            infos["canal"] = round((freq - 5000) / 5)
        else:
            infos["bande"] = "6 GHz"
            infos["canal"] = round((freq - 5950) / 5)
    m = re.search(r"signal:\s*(-?\d+)", lien)
    if m:
        dbm = int(m.group(1))
        infos["dbm"] = dbm
        # -50 dBm ≈ 100 %, -100 dBm ≈ 0 : l'échelle usuelle des barres Wi-Fi.
        infos["signal"] = max(0, min(100, round(2 * (dbm + 100))))
    m = re.search(r"rx bitrate:\s*([\d.]+)", lien)
    if m:
        infos["rx_mbps"] = round(float(m.group(1)), 1)
    m = re.search(r"tx bitrate:\s*([\d.]+)", lien)
    if m:
        infos["tx_mbps"] = round(float(m.group(1)), 1)
    return infos


def _adresse(dev):
    infos = {}
    sortie = _run(["ip", "-4", "addr", "show", dev])
    m = re.search(r"inet\s+([\d.]+)/(\d+)", sortie)
    if m:
        infos["ip"] = m.group(1)
        infos["prefixe"] = int(m.group(2))
    route = _run(["ip", "route", "show", "default", "dev", dev])
    m = re.search(r"via\s+([\d.]+)", route)
    if m:
        infos["passerelle"] = m.group(1)
    return infos


def _vpn():
    """Le tunnel actif : ProtonVPN apparaît comme une connexion wireguard."""
    sortie = _run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"])
    for ligne in sortie.splitlines():
        morceaux = ligne.split(":")
        if len(morceaux) < 3:
            continue
        nom, nature = morceaux[0], morceaux[1]
        if nature in ("wireguard", "vpn", "tun"):
            return nom
    return ""


def _trafic(dev):
    """Débits instantanés, calculés entre deux appels (état gardé sur disque)."""
    try:
        with open(f"/sys/class/net/{dev}/statistics/rx_bytes") as f:
            rx = int(f.read().strip())
        with open(f"/sys/class/net/{dev}/statistics/tx_bytes") as f:
            tx = int(f.read().strip())
    except (OSError, ValueError):
        return {}

    maintenant = time.time()
    precedent = None
    try:
        with open(ETAT, "r", encoding="utf-8") as f:
            precedent = json.load(f)
    except (OSError, ValueError):
        precedent = None

    infos = {"rx_total_go": round(rx / 1e9, 1), "tx_total_go": round(tx / 1e9, 1)}
    if precedent and precedent.get("dev") == dev:
        ecart = maintenant - float(precedent.get("ts") or 0)
        if 0.3 < ecart < 120:
            infos["rx_ko_s"] = max(0, round((rx - int(precedent.get("rx", 0))) / ecart / 1024))
            infos["tx_ko_s"] = max(0, round((tx - int(precedent.get("tx", 0))) / ecart / 1024))

    try:
        os.makedirs(os.path.dirname(ETAT), exist_ok=True)
        with open(ETAT, "w", encoding="utf-8") as f:
            json.dump({"dev": dev, "rx": rx, "tx": tx, "ts": maintenant}, f)
    except OSError:
        pass
    return infos


def _latence(passerelle):
    if not passerelle:
        return None
    sortie = _run(["ping", "-c", "1", "-W", "1", passerelle], timeout=3)
    # Un ping localisé écrit « temps= » et non « time= » ; la ligne de synthèse
    # (rtt min/avg/max) reste identique dans les deux cas.
    m = re.search(r"(?:time|temps)[=<]([\d.]+)\s*ms", sortie)
    if not m:
        m = re.search(r"rtt[^=]*=\s*[\d.]+/([\d.]+)/", sortie)
    return round(float(m.group(1))) if m else None


def analyser():
    dev, nature, connexion = _interface_active()
    if not dev:
        return {"ok": True, "connecte": False}

    infos = {"ok": True, "connecte": True, "interface": dev,
             "nature": nature, "connexion": connexion}
    if nature == "wifi":
        infos.update(_wifi(dev))
    infos.update(_adresse(dev))
    infos.update(_trafic(dev))
    vpn = _vpn()
    if vpn:
        infos["vpn"] = vpn
    latence = _latence(infos.get("passerelle"))
    if latence is not None:
        infos["latence_ms"] = latence
    # Nom d'hôte : utile quand la connexion n'a pas de SSID (filaire).
    try:
        infos["hote"] = socket.gethostname()
    except OSError:
        pass
    return infos


def main(argv):
    force = "--force" in argv
    if not force:
        try:
            with open(CACHE, "r", encoding="utf-8") as f:
                cache = json.load(f)
            if time.time() - float(cache.pop("analyse_ts", 0)) < 1.5:
                print(json.dumps(cache, ensure_ascii=False))
                return 0
        except (OSError, ValueError):
            pass

    donnees = analyser()
    try:
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w", encoding="utf-8") as f:
            json.dump(dict(donnees, analyse_ts=time.time()), f)
    except OSError:
        pass
    print(json.dumps(donnees, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
