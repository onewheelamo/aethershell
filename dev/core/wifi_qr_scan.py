#!/usr/bin/env python3
"""Scan de QR code Wi-Fi via webcam (zbarcam, ou ffmpeg + zbarimg).

Commandes :
    wifi_qr_scan.py status   -> {"available": bool, "devices": [...], "tool": "..."}
    wifi_qr_scan.py scan     -> {"ok": true, "password": "...", "ssid": "..."}
"""

from __future__ import annotations

import glob
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def list_video_devices() -> list[str]:
    """Retourne les périphériques V4L2 accessibles en lecture."""
    devs = sorted(glob.glob("/dev/video*"))
    dispos = []
    for d in devs:
        nom = Path(d).name
        sys_dir = Path("/sys/class/video4linux") / nom
        if not sys_dir.exists():
            continue
        # Filtre les nœuds metadata-only quand index > 0 si V4L2 le signale, mais
        # garde tout périphérique lisible si index == 0 ou inconnu.
        idx_file = sys_dir / "index"
        if idx_file.is_file():
            try:
                if int(idx_file.read_text().strip()) % 2 == 1:
                    # Sur UVC Linux, les index impairs sont souvent des flux metadata
                    pass
            except Exception:
                pass
        if os.access(d, os.R_OK):
            dispos.append(d)
    return dispos


def detect_tool() -> str:
    if shutil.which("zbarcam"):
        return "zbarcam"
    if shutil.which("ffmpeg") and shutil.which("zbarimg"):
        return "ffmpeg+zbarimg"
    return ""


def parse_wifi_qr(raw: str) -> dict:
    """Parse le format standard `WIFI:T:WPA;S:SSID;P:PASS;H:false;;`."""
    text = raw.strip()
    if not text.upper().startswith("WIFI:"):
        return {"ssid": "", "password": text}

    body = text[5:]
    fields: dict[str, str] = {}
    i = 0
    n = len(body)
    while i < n:
        colon = body.find(":", i)
        if colon == -1:
            break
        key = body[i:colon].upper()
        i = colon + 1
        val_chars = []
        while i < n:
            ch = body[i]
            if ch == "\\" and i + 1 < n:
                val_chars.append(body[i + 1])
                i += 2
                continue
            if ch == ";":
                i += 1
                break
            val_chars.append(ch)
            i += 1
        fields[key] = "".join(val_chars)

    return {
        "ssid": fields.get("S", ""),
        "password": fields.get("P", ""),
        "auth": fields.get("T", ""),
    }


def cmd_status() -> int:
    devs = list_video_devices()
    tool = detect_tool()
    print(json.dumps({
        "available": bool(devs and tool),
        "devices": devs,
        "tool": tool,
    }))
    return 0


def _scan_with_zbarcam(dev: str, timeout: int) -> str | None:
    cmd = ["zbarcam", "--raw", "--oneshot", "-Sdisable", "-Sqrcode.enable", dev]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        out = r.stdout.strip()
        if out:
            return out.splitlines()[0].strip()
    except subprocess.TimeoutExpired:
        return None
    except Exception:
        return None
    return None


def _scan_with_ffmpeg(dev: str, timeout: int) -> str | None:
    """Fallback sans fenêtre vidéo si zbarcam n'est pas disponible."""
    import tempfile

    with tempfile.TemporaryDirectory(prefix="aether_qr_") as tmp:
        pattern = os.path.join(tmp, "f_%03d.png")
        try:
            subprocess.run(
                [
                    "ffmpeg", "-y", "-f", "v4l2", "-i", dev,
                    "-t", str(min(timeout, 12)), "-vf", "fps=2", pattern,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=min(timeout, 12) + 3,
            )
        except Exception:
            pass
        for img in sorted(glob.glob(os.path.join(tmp, "f_*.png"))):
            try:
                r = subprocess.run(
                    ["zbarimg", "--raw", "-q", img],
                    capture_output=True, text=True, timeout=3,
                )
                out = r.stdout.strip()
                if out:
                    return out.splitlines()[0].strip()
            except Exception:
                continue
    return None


def cmd_scan(timeout: int = 35) -> int:
    devs = list_video_devices()
    if not devs:
        print(json.dumps({"ok": False, "error": "Aucune webcam détectée"}))
        return 1
    tool = detect_tool()
    if not tool:
        print(json.dumps({"ok": False, "error": "Outil zbarcam/zbarimg manquant"}))
        return 1

    raw = None
    for dev in devs[:4]:
        if tool == "zbarcam":
            raw = _scan_with_zbarcam(dev, timeout)
        else:
            raw = _scan_with_ffmpeg(dev, timeout)
        if raw:
            break

    if not raw:
        print(json.dumps({"ok": False, "error": "Scan annulé ou aucun QR code lu"}))
        return 1

    parsed = parse_wifi_qr(raw)
    print(json.dumps({
        "ok": True,
        "ssid": parsed.get("ssid", ""),
        "password": parsed.get("password", ""),
    }))
    return 0


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        return cmd_status()
    if cmd == "scan":
        return cmd_scan()
    print(json.dumps({"ok": False, "error": f"Commande inconnue : {cmd}"}))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
