#!/usr/bin/env python3
"""Sonde légère d'indicateurs de confidentialité et VPN pour l'Îlot dynamique.

Retourne un JSON sur stdout :
    {"vpn": "connected"|"disconnected"|"error", "capture": "video"|"audio"|"none"}
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

VIDEO_PROCS = {"wf-recorder", "wl-screenrec", "gpu-screen-recorder", "obs"}
IGNORED_AUDIO_APPS = {"cava", "pwscope", "pavucontrol"}


def _detect_vpn() -> str:
    try:
        res = subprocess.run(
            ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"],
            capture_output=True, text=True, timeout=2.0, check=False,
        )
        if res.returncode != 0:
            return "error"
        has_activating = False
        for line in res.stdout.splitlines():
            parts = line.split(":")
            if len(parts) < 3:
                continue
            nature, state = parts[1].strip(), parts[2].strip()
            if nature in ("wireguard", "vpn", "tun"):
                if state == "activated":
                    return "connected"
                if state in ("activating", "deactivating"):
                    has_activating = True
        if has_activating:
            return "error"
    except Exception:
        return "error"

    # Repli via interfaces réseau actives (wg*, tun*, proton*, mullvad*)
    try:
        for iface in os.listdir("/sys/class/net"):
            if iface.startswith(("tun", "tap", "wg", "proton", "mullvad")):
                op_path = f"/sys/class/net/{iface}/operstate"
                try:
                    with open(op_path, "r", encoding="utf-8") as f:
                        state = f.read().strip().lower()
                    if state in ("up", "unknown"):
                        return "connected"
                except OSError:
                    pass
    except OSError:
        pass

    # Vérifie si un service VPN systemd connu est en échec
    try:
        res = subprocess.run(
            ["systemctl", "is-failed", "mullvad-daemon", "openvpn-client@*", "wg-quick@*"],
            capture_output=True, text=True, timeout=1.5, check=False,
        )
        if "failed" in res.stdout.splitlines():
            return "error"
    except Exception:
        pass

    return "disconnected"


def _detect_video_capture() -> bool:
    try:
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            comm_path = f"/proc/{entry}/comm"
            try:
                with open(comm_path, "r", encoding="utf-8") as f:
                    comm = f.read().strip()
                if comm in VIDEO_PROCS:
                    return True
            except OSError:
                continue

            fd_dir = f"/proc/{entry}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                        if target.startswith("/dev/video"):
                            return True
                    except OSError:
                        continue
            except OSError:
                continue
    except OSError:
        pass
    return False


def _detect_audio_capture() -> bool:
    try:
        res = subprocess.run(
            ["pactl", "list", "source-outputs"],
            capture_output=True, text=True, timeout=1.5, check=False,
        )
        if res.returncode != 0 or not res.stdout.strip():
            return False

        blocks = res.stdout.split("Source Output #")
        for blk in blocks[1:]:
            lower = blk.lower()
            # Ignore les moniteurs de sortie (cava, pwscope, visualiseurs)
            if ".monitor" in lower:
                continue
            if any(app in lower for app in IGNORED_AUDIO_APPS):
                continue
            return True
    except Exception:
        pass
    return False


def main() -> int:
    vpn = _detect_vpn()
    if _detect_video_capture():
        capture = "video"
    elif _detect_audio_capture():
        capture = "audio"
    else:
        capture = "none"

    sys.stdout.write(json.dumps({"vpn": vpn, "capture": capture}) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
