#!/usr/bin/env python3
"""Détecte les activités longues système pour l'Îlot Live Activity :
1. Enregistrement vidéo en cours (wf-recorder) + durée écoulée.
2. Téléchargements navigateurs actifs (*.part, *.crdownload, *.opdownload).
"""

import glob
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time


def _download_dir():
    try:
        res = subprocess.run(
            ["xdg-user-dir", "DOWNLOAD"],
            capture_output=True, text=True, timeout=1, check=False
        )
        p = res.stdout.strip()
        if p and os.path.isdir(p):
            return p
    except Exception:
        pass
    for candidate in ("~/Téléchargements", "~/Downloads"):
        p = os.path.expanduser(candidate)
        if os.path.isdir(p):
            return p
    return ""


def _probe_wf_recorder():
    try:
        res = subprocess.run(
            ["pgrep", "-xo", "wf-recorder"],
            capture_output=True, text=True, timeout=1, check=False
        )
        pid_str = res.stdout.strip()
        if not pid_str:
            return {"active": False, "elapsedSec": 0, "pid": 0}
        pid = int(pid_str.splitlines()[0])
        ps = subprocess.run(
            ["ps", "-o", "etimes=", "-p", str(pid)],
            capture_output=True, text=True, timeout=1, check=False
        )
        elapsed = int(ps.stdout.strip()) if ps.stdout.strip().isdigit() else 0
        return {"active": True, "elapsedSec": elapsed, "pid": pid}
    except Exception:
        return {"active": False, "elapsedSec": 0, "pid": 0}


def _fmt_size(nbytes):
    if nbytes < 1024 * 1024:
        return f"{max(1, nbytes // 1024)} Ko"
    if nbytes < 1024 * 1024 * 1024:
        return f"{nbytes / (1024 * 1024):.1f} Mo"
    return f"{nbytes / (1024 * 1024 * 1024):.2f} Go"


def _fmt_speed(bps):
    if bps <= 0:
        return ""
    if bps < 1024 * 1024:
        return f"{max(1, int(bps // 1024))} Ko/s"
    return f"{bps / (1024 * 1024):.1f} Mo/s"


def _load_gecko_downloads_meta():
    """Lit downloads.json des profils Gecko (Firefox, Zen, LibreWolf, Floorp, Waterfox, Flatpak)."""
    meta = {}
    patterns = (
        os.path.expanduser("~/.mozilla/firefox/*/downloads.json"),
        os.path.expanduser("~/.librewolf/*/downloads.json"),
        os.path.expanduser("~/.zen/*/downloads.json"),
        os.path.expanduser("~/.floorp/*/downloads.json"),
        os.path.expanduser("~/.waterfox/*/downloads.json"),
        os.path.expanduser("~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/downloads.json"),
        os.path.expanduser("~/.var/app/io.gitlab.librewolf-community/.librewolf/*/downloads.json"),
        os.path.expanduser("~/.var/app/app.zen_browser.zen/.zen/*/downloads.json"),
    )
    for pat in patterns:
        for path in glob.glob(pat):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                for item in data.get("list", []):
                    tgt = item.get("target") or {}
                    part = tgt.get("partFilePath") or ""
                    final = tgt.get("path") or ""
                    total = int(item.get("totalBytes") or 0)
                    if part:
                        meta[part] = {
                            "totalBytes": total,
                            "name": os.path.basename(final) if final else "",
                        }
            except Exception:
                pass
    return meta


def _load_chromium_downloads_meta():
    """Lit la table downloads de History (Chrome, Chromium, Brave, Opera, Vivaldi, Edge)."""
    meta = {}
    patterns = (
        os.path.expanduser("~/.config/google-chrome/*/History"),
        os.path.expanduser("~/.config/chromium/*/History"),
        os.path.expanduser("~/.config/BraveSoftware/Brave-Browser/*/History"),
        os.path.expanduser("~/.config/opera/History"),
        os.path.expanduser("~/.config/opera/*/History"),
        os.path.expanduser("~/.config/vivaldi/*/History"),
        os.path.expanduser("~/.config/microsoft-edge/*/History"),
        os.path.expanduser("~/.var/app/com.google.Chrome/config/google-chrome/*/History"),
        os.path.expanduser("~/.var/app/org.chromium.Chromium/config/chromium/*/History"),
        os.path.expanduser("~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/*/History"),
        os.path.expanduser("~/.var/app/com.opera.Opera/config/opera/History"),
    )
    for pat in patterns:
        for db in glob.glob(pat):
            tmp = ""
            try:
                fd, tmp = tempfile.mkstemp(suffix=".sqlite")
                os.close(fd)
                shutil.copy2(db, tmp)
                con = sqlite3.connect(tmp)
                rows = con.execute(
                    "SELECT current_path, target_path, total_bytes FROM downloads WHERE state = 0"
                ).fetchall()
                con.close()
                for cur_p, tgt_p, total in rows:
                    if cur_p:
                        meta[cur_p] = {
                            "totalBytes": int(total or 0),
                            "name": os.path.basename(tgt_p) if tgt_p else "",
                        }
            except Exception:
                pass
            finally:
                if tmp and os.path.exists(tmp):
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
    return meta


def _probe_downloads():
    dl_dir = _download_dir()
    if not dl_dir:
        return []
    now = time.time()
    suffixes = (".part", ".crdownload", ".opdownload")
    raw_entries = []
    try:
        for entry in os.scandir(dl_dir):
            if not entry.is_file():
                continue
            low = entry.name.lower()
            if not any(low.endswith(s) for s in suffixes):
                continue
            st = entry.stat()
            if now - st.st_mtime > 45:
                continue
            raw_entries.append((entry, st, low))
    except Exception:
        return []

    if not raw_entries:
        return []

    meta = {}
    if any(low.endswith(".part") for _, _, low in raw_entries):
        meta.update(_load_gecko_downloads_meta())
    if any(low.endswith(".crdownload") or low.endswith(".opdownload") for _, _, low in raw_entries):
        meta.update(_load_chromium_downloads_meta())

    cache_path = "/tmp/aether_dl_probe_cache.json"
    prev_cache = {}
    try:
        if os.path.exists(cache_path):
            with open(cache_path, "r", encoding="utf-8") as cf:
                prev_cache = json.load(cf)
                if not isinstance(prev_cache, dict):
                    prev_cache = {}
    except Exception:
        prev_cache = {}

    new_cache = {}
    found = []
    try:
        for entry, st, _ in raw_entries:
            clean_name = entry.name
            for s in suffixes:
                if clean_name.lower().endswith(s):
                    clean_name = clean_name[:-len(s)]
                    break
            m = meta.get(entry.path) or {}
            if m.get("name"):
                clean_name = m["name"]
            total_bytes = int(m.get("totalBytes") or 0)
            progress = -1
            if total_bytes > 0:
                progress = max(0, min(100, round(100 * st.st_size / total_bytes)))

            speed_bps = 0.0
            prev = prev_cache.get(entry.path)
            if isinstance(prev, dict):
                dt = now - float(prev.get("ts", 0))
                ds = st.st_size - int(prev.get("size", 0))
                if dt > 0.2 and ds > 0:
                    speed_bps = ds / dt
                elif dt <= 6.0 and float(prev.get("speedBps", 0)) > 0:
                    speed_bps = float(prev.get("speedBps", 0))

            eta_sec = -1
            if total_bytes > st.st_size and speed_bps > 0:
                eta_sec = int(round((total_bytes - st.st_size) / speed_bps))

            new_cache[entry.path] = {"size": st.st_size, "ts": now, "speedBps": speed_bps}
            found.append({
                "name": clean_name or entry.name,
                "size": st.st_size,
                "totalBytes": total_bytes,
                "progress": progress,
                "sizeStr": _fmt_size(st.st_size),
                "totalStr": _fmt_size(total_bytes) if total_bytes > 0 else "",
                "speedBps": round(speed_bps),
                "speedStr": _fmt_speed(speed_bps),
                "etaSec": eta_sec,
            })
        with open(cache_path, "w", encoding="utf-8") as cf:
            json.dump(new_cache, cf)
    except Exception:
        pass
    found.sort(key=lambda x: x["name"].lower())
    return found


def _pkg_needs_input(root_pid):
    """Détecte si un processus descendant au premier plan attend une saisie terminal."""
    if not root_pid:
        return False
    try:
        res = subprocess.run(
            ["ps", "-eo", "pid=,ppid=,stat=,wchan:24="],
            capture_output=True, text=True, timeout=1, check=False
        )
        children = {}
        info = {}
        for line in res.stdout.splitlines():
            parts = line.split()
            if len(parts) < 4:
                continue
            pid = int(parts[0]) if parts[0].isdigit() else 0
            ppid = int(parts[1]) if parts[1].isdigit() else 0
            stat = parts[2]
            wchan = parts[3]
            if pid <= 0:
                continue
            children.setdefault(ppid, []).append(pid)
            info[pid] = (stat, wchan)

        queue = [root_pid]
        seen = set()
        while queue:
            cur = queue.pop(0)
            if cur in seen:
                continue
            seen.add(cur)
            stat, wchan = info.get(cur, ("", ""))
            if "+" in stat and wchan in ("n_tty_read", "wait_woken", "tty_read"):
                return True
            for ch in children.get(cur, []):
                if ch not in seen:
                    queue.append(ch)
    except Exception:
        pass
    return False


def _probe_arch_remaining_pkgs():
    try:
        res = subprocess.run(
            ["pacman", "-Qu"],
            capture_output=True, text=True, timeout=1.5, check=False
        )
        if res.returncode == 0:
            return len([l for l in res.stdout.splitlines() if l.strip()])
    except Exception:
        pass
    return -1


def _probe_pkg_update():
    arch_ignored = {
        "-c", "--check", "-l", "--list", "-n", "--news",
        "-s", "--services", "--tray", "--gen-config",
        "--show-config", "--edit-config", "-h", "--help", "-V", "--version",
    }
    pkg_verbs = {"upgrade", "update", "full-upgrade", "dist-upgrade", "distro-sync", "system-upgrade", "install"}
    pkg_ignored = {"check-update", "makecache", "info", "search", "list", "show", "policy", "-h", "--help", "-V", "--version"}

    try:
        res = subprocess.run(
            ["ps", "-eo", "pid=,etimes=,args="],
            capture_output=True, text=True, timeout=1, check=False
        )
        for line in res.stdout.splitlines():
            parts = line.strip().split(None, 2)
            if len(parts) < 3:
                continue
            pid_s, etimes_s, args_s = parts
            tokens = args_s.split()
            head = [os.path.basename(t) for t in tokens[:3]]
            matched_tool = ""

            if "arch-update" in head:
                if any(t in arch_ignored for t in tokens):
                    continue
                matched_tool = "arch-update"
            elif any(t in ("dnf", "dnf5", "apt", "apt-get", "nala") for t in head):
                tool = next(t for t in head if t in ("dnf", "dnf5", "apt", "apt-get", "nala"))
                if any(t in pkg_ignored for t in tokens):
                    continue
                if not any(t in pkg_verbs for t in tokens):
                    continue
                matched_tool = tool

            if matched_tool:
                pid = int(pid_s) if pid_s.isdigit() else 0
                elapsed = int(etimes_s) if etimes_s.isdigit() else 0
                needs_input = _pkg_needs_input(pid)

                remaining = -1
                initial = -1
                progress = -1
                eta_sec = -1
                if matched_tool == "arch-update":
                    remaining = _probe_arch_remaining_pkgs()
                    cache_path = "/tmp/aether_pkg_probe_cache.json"
                    try:
                        cache = {}
                        if os.path.exists(cache_path):
                            with open(cache_path, "r", encoding="utf-8") as cf:
                                cache = json.load(cf) or {}
                        if str(cache.get("pid")) == str(pid) and int(cache.get("initial", -1)) > 0:
                            initial = max(int(cache["initial"]), remaining)
                        elif remaining >= 0:
                            initial = remaining
                        with open(cache_path, "w", encoding="utf-8") as cf:
                            json.dump({"pid": pid, "initial": initial}, cf)
                    except Exception:
                        pass
                    if initial > 0 and remaining >= 0 and remaining < initial:
                        done = initial - remaining
                        progress = max(0, min(99, round(100 * done / initial)))
                        if remaining > 0:
                            eta_sec = int(round(elapsed * remaining / done))

                return {
                    "active": True,
                    "elapsedSec": elapsed,
                    "pid": pid,
                    "tool": matched_tool,
                    "needsInput": needs_input,
                    "remainingPkgs": remaining,
                    "initialPkgs": initial,
                    "progress": progress,
                    "etaSec": eta_sec,
                }
    except Exception:
        pass
    return {"active": False, "elapsedSec": 0, "pid": 0, "tool": "", "needsInput": False, "remainingPkgs": -1, "initialPkgs": -1, "progress": -1, "etaSec": -1}


def _ancestor_pids(pid):
    ancestors = set()
    cur = int(pid or 0)
    for _ in range(16):
        if cur <= 1 or cur in ancestors:
            break
        ancestors.add(cur)
        try:
            res = subprocess.run(
                ["ps", "-o", "ppid=", "-p", str(cur)],
                capture_output=True, text=True, timeout=1, check=False
            )
            nxt = res.stdout.strip()
            cur = int(nxt) if nxt.isdigit() else 0
        except Exception:
            break
    return ancestors


def _hypr_dispatch(lua_expr, legacy_args):
    res = subprocess.run(
        ["hyprctl", "dispatch", lua_expr],
        capture_output=True, text=True, check=False
    )
    if res.returncode != 0 or "error:" in (res.stdout + res.stderr).lower():
        subprocess.run(["hyprctl", "dispatch"] + legacy_args, check=False)


def _focus_hypr_client(client):
    if not client or not client.get("address"):
        return False
    addr = client["address"]
    ws = client.get("workspace") or {}
    ws_id = ws.get("id", 0)
    if isinstance(ws_id, int) and ws_id > 0:
        _hypr_dispatch(f"hl.dsp.focus({{ workspace = {ws_id} }})", ["workspace", str(ws_id)])
    _hypr_dispatch(f'hl.dsp.focus({{ window = "address:{addr}" }})', ["focuswindow", f"address:{addr}"])
    return True


def _focus_activity(kind, pid=0):
    try:
        res = subprocess.run(
            ["hyprctl", "clients", "-j"],
            capture_output=True, text=True, timeout=2, check=False
        )
        clients = json.loads(res.stdout or "[]")
    except Exception:
        return False
    if not isinstance(clients, list):
        return False

    if kind == "update":
        ancestors = _ancestor_pids(pid)
        for c in clients:
            if c.get("pid") in ancestors:
                return _focus_hypr_client(c)
        for c in clients:
            t = str(c.get("title", "")).lower()
            if any(k in t for k in ("arch-update", "dnf", "apt", "nala")):
                return _focus_hypr_client(c)
        return False

    if kind == "download":
        browsers = ("firefox", "zen", "librewolf", "floorp", "waterfox", "chromium", "chrome", "brave", "vivaldi", "opera", "microsoft-edge")
        matches = [
            c for c in clients
            if any(b in str(c.get("class", "")).lower() or b in str(c.get("initialClass", "")).lower() for b in browsers)
        ]
        matches.sort(key=lambda c: (
            1 if str((c.get("workspace") or {}).get("name", "")).startswith("special:") else 0,
            c.get("focusHistoryID", 999)
        ))
        if matches:
            return _focus_hypr_client(matches[0])
        return False

    return False


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--focus":
        kind = sys.argv[2]
        pid = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 0
        ok = _focus_activity(kind, pid)
        print(json.dumps({"ok": ok}))
        return
    print(json.dumps({
        "recording": _probe_wf_recorder(),
        "pkgUpdate": _probe_pkg_update(),
        "downloads": _probe_downloads(),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
