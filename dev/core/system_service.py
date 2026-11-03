import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from runtime_paths import runtime_path  # noqa: E402

TABLET_STATE_FILE = runtime_path("tablet_mode")


def run_cmd(cmd):
    try:
        if isinstance(cmd, list):
            return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8").strip()
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode("utf-8").strip()
    except Exception:
        return ""


def get_hostname():
    try:
        if os.path.exists("/etc/hostname"):
            with open("/etc/hostname", "r") as f:
                h = f.read().strip()
                if h:
                    return h.lower()
    except Exception:
        pass
    out = run_cmd(["uname", "-n"])
    return out.lower() if out else "station"


def has_battery_device():
    return len(glob.glob("/sys/class/power_supply/BAT*")) > 0


def has_backlight_device():
    return len(glob.glob("/sys/class/backlight/*")) > 0


def get_battery_limit_state():
    """Detect whether 80% battery charge limit (or Lenovo conservation_mode) is active."""
    threshold_path = "/sys/class/power_supply/BAT0/charge_control_end_threshold"
    if os.path.exists(threshold_path):
        try:
            with open(threshold_path, "r") as f:
                val = f.read().strip()
            if val.isdigit() and int(val) <= 85:
                return True
        except Exception:
            pass

    for path in glob.glob("/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode"):
        try:
            with open(path, "r") as f:
                val = f.read().strip()
            if val == "1":
                return True
        except Exception:
            pass
    return False


def _read_proc_wifi_signal(iface):
    """Read WiFi signal percentage from /proc/net/wireless without spawning a subprocess."""
    try:
        if os.path.exists("/proc/net/wireless"):
            with open("/proc/net/wireless", "r") as f:
                for line in f:
                    if line.strip().startswith(iface + ":"):
                        parts = line.split()
                        if len(parts) >= 3:
                            link = float(parts[2].rstrip("."))
                            # /proc/net/wireless link quality is typically out of 70
                            return max(0, min(100, int(round((link / 70.0) * 100))))
    except Exception:
        pass
    return 0


def _unescape_nmcli(val):
    """nmcli -t escapes ':' and '\\' inside fields."""
    return val.replace("\\:", ":").replace("\\\\", "\\")


def _split_nmcli(line, maxsplit=-1):
    """Split a nmcli terse line on unescaped ':' only."""
    parts, cur, i = [], "", 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur += line[i:i + 2]
            i += 2
            continue
        if c == ":" and (maxsplit < 0 or len(parts) < maxsplit):
            parts.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    parts.append(cur)
    return parts


WIFI_SSID_CACHE_FILE = runtime_path("wifi_ssid_cache.json")


def _cached_wifi_ssid(iface, conn_name):
    """
    SSID of the active access point, resolved with a single `nmcli dev wifi list`
    only when (iface, connection profile) changed since the previous poll.
    Each poll is a fresh process, so the cache lives in a small /tmp file.
    """
    key = f"{iface}|{conn_name}"
    try:
        with open(WIFI_SSID_CACHE_FILE, "r") as f:
            cache = json.load(f)
        if cache.get("key") == key and cache.get("ssid"):
            return cache["ssid"]
    except Exception:
        pass
    ssid, _ = _active_wifi_ssid_signal(iface)
    if ssid:
        try:
            fd = os.open(WIFI_SSID_CACHE_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                json.dump({"key": key, "ssid": ssid}, f)
        except Exception:
            pass
    return ssid


def _active_wifi_ssid_signal(iface):
    """Return (ssid, signal) of the access point in use on iface, or (None, None)."""
    out = run_cmd(["nmcli", "-t", "-f", "IN-USE,SIGNAL,SSID", "dev", "wifi", "list",
                   "ifname", iface, "--rescan", "no"])
    for line in out.splitlines():
        parts = _split_nmcli(line, 2)
        if len(parts) == 3 and parts[0] == "*":
            sig = int(parts[1]) if parts[1].isdigit() else None
            return _unescape_nmcli(parts[2]), sig
    return None, None


def get_volume_info():
    """Return {"level": int, "muted": bool} (PipeWire wpctl first, fallback to amixer)."""
    vol_pct = 0
    muted = False
    wp_out = run_cmd(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
    if wp_out:
        muted = "[MUTED]" in wp_out
        m = re.search(r"([0-9]+(?:\.[0-9]+)?)", wp_out)
        if m:
            vol_pct = int(round(float(m.group(1)) * 100))
    else:
        am_out = run_cmd(["amixer", "sget", "Master"])
        m_vol = re.search(r"\[(\d+)%\]", am_out)
        if m_vol:
            vol_pct = int(m_vol.group(1))
        muted = "[off]" in am_out
    return {"level": vol_pct, "muted": muted}


def get_brightness_pct():
    bright_pct = 100
    bl_dirs = sorted(glob.glob("/sys/class/backlight/*"))
    try:
        with open(os.path.join(bl_dirs[0], "brightness"), "r") as f:
            cur_b = int(f.read().strip())
        with open(os.path.join(bl_dirs[0], "max_brightness"), "r") as f:
            max_b = int(f.read().strip())
        if max_b > 0:
            bright_pct = int(round((cur_b / max_b) * 100))
    except Exception:
        bright = run_cmd(["brightnessctl", "g"])
        max_bright = run_cmd(["brightnessctl", "m"])
        if bright.isdigit() and max_bright.isdigit() and int(max_bright) > 0:
            bright_pct = int(round((int(bright) / int(max_bright)) * 100))
    return bright_pct


def get_system_info():
    hostname = get_hostname()
    has_bat = has_battery_device()
    has_bri = has_backlight_device()

    # 1. Battery (only relevant if has_bat is True)
    bat_cap = 0
    bat_status = "NoBattery"
    limit_80 = False
    if has_bat:
        bat_dirs = sorted(glob.glob("/sys/class/power_supply/BAT*"))
        bat_dir = bat_dirs[0]
        try:
            with open(os.path.join(bat_dir, "capacity"), "r") as f:
                s = f.read().strip()
                bat_cap = int(s) if s.isdigit() else 0
        except Exception:
            bat_cap = 0
        try:
            with open(os.path.join(bat_dir, "status"), "r") as f:
                bat_status = f.read().strip() or "Unknown"
        except Exception:
            bat_status = "Unknown"
        limit_80 = get_battery_limit_state()

    # 2. Volume (PipeWire wpctl first, fallback to amixer)
    volume = get_volume_info()
    vol_pct, muted = volume["level"], volume["muted"]

    # 3. Brightness (read directly from /sys/class/backlight to avoid extra subprocesses)
    bright_pct = get_brightness_pct() if has_bri else 100

    # 4. Active Network connection (Single fast nmcli dev status call + /proc/net/wireless)
    wifi_connected = False
    wifi_ssid = ""
    wifi_signal = 0
    net_type = "none"

    dev_status = run_cmd(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"])
    eth_fallback = None
    for line in dev_status.splitlines():
        parts = _split_nmcli(line, 3)
        if len(parts) == 4 and parts[2] == "connected":
            dev_name, dev_type, _, conn_name = parts
            conn_name = _unescape_nmcli(conn_name)
            if dev_type == "wifi":
                ssid = _cached_wifi_ssid(dev_name, conn_name)
                wifi_connected = True
                wifi_ssid = ssid or conn_name  # profile name only as a fallback
                wifi_signal = _read_proc_wifi_signal(dev_name)  # no subprocess
                net_type = "wifi"
                break
            elif dev_type == "ethernet" and eth_fallback is None:
                eth_fallback = conn_name or "Ethernet"

    if not wifi_connected and eth_fallback is not None:
        wifi_connected = True
        wifi_ssid = eth_fallback
        wifi_signal = 100
        net_type = "ethernet"

    # 5. Tablet mode state (per-user runtime dir)
    tablet_mode = False
    if has_bat and os.path.exists(TABLET_STATE_FILE):
        try:
            with open(TABLET_STATE_FILE, "r") as f:
                tablet_mode = f.read().strip() == "tablet"
        except Exception:
            pass

    return {
        "hostname": hostname,
        "has_battery": has_bat,
        "has_backlight": has_bri,
        "battery": {
            "level": bat_cap,
            "status": bat_status,
            "limit_80": limit_80,
        },
        "volume": {
            "level": vol_pct,
            "muted": muted,
        },
        "brightness": bright_pct,
        "wifi": {
            "connected": wifi_connected,
            "ssid": wifi_ssid,
            "signal": wifi_signal,
            "type": net_type,
        },
        "tablet_mode": tablet_mode,
    }


def set_battery_limit(limit=80):
    """
    Set battery charge limit to 80% (or enable Lenovo ideapad conservation_mode)
    when limit <= 80, or restore 100% when limit > 80.
    """
    enable_limit = int(limit) <= 80
    target_pct = 80 if enable_limit else 100
    cons_val = 1 if enable_limit else 0

    cmds = []
    if os.path.exists("/sys/class/power_supply/BAT0/charge_control_end_threshold"):
        cmds.append(
            f"echo {target_pct} | sudo -n tee /sys/class/power_supply/BAT0/charge_control_end_threshold >/dev/null 2>&1"
        )
    for path in glob.glob("/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode"):
        cmds.append(f"echo {cons_val} | sudo -n tee {path} >/dev/null 2>&1")

    for c in cmds:
        subprocess.run(c, shell=True, check=False)

    return {"status": "ok", "limit_80": get_battery_limit_state(), "requested": target_pct}


def set_volume(pct):
    val = max(0, min(150, int(float(pct))))
    subprocess.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{val}%"], check=False)
    return True


def toggle_mute():
    subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], check=False)
    return True


def set_brightness(pct):
    if not has_backlight_device():
        return False
    val = max(5, min(100, int(float(pct))))
    subprocess.run(["brightnessctl", "set", f"{val}%"], stdout=subprocess.DEVNULL, check=False)
    return True


def get_wifi_networks(rescan=True):
    rescan_flag = "auto" if rescan else "no"
    output = run_cmd(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", rescan_flag])
    by_ssid = {}

    for line in output.splitlines():
        if not line:
            continue
        in_use = line.startswith("*:")
        rest = line[2:] if (line.startswith("*:") or line.startswith(" :")) else line
        parts = rest.rsplit(":", 2)
        if len(parts) < 3:
            continue
        raw_ssid, sig_str, security = parts[0], parts[1], parts[2]
        ssid = raw_ssid.replace("\\:", ":").strip()
        if not ssid:
            continue
        signal = int(sig_str) if sig_str.isdigit() else 0
        secured = bool(security and security != "--")

        existing = by_ssid.get(ssid)
        if not existing or in_use or signal > existing["signal"]:
            by_ssid[ssid] = {
                "ssid": ssid,
                "signal": signal,
                "in_use": in_use or (existing["in_use"] if existing else False),
                "security": security or "Ouvert",
                "secured": secured,
            }

    networks = list(by_ssid.values())
    networks.sort(key=lambda x: (1 if x["in_use"] else 0, x["signal"]), reverse=True)
    return networks


def connect_wifi(ssid, password=""):
    try:
        if password:
            cmd = ["nmcli", "dev", "wifi", "connect", ssid, "password", password]
        else:
            cmd = ["nmcli", "dev", "wifi", "connect", ssid]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        ok = res.returncode == 0
        msg = (res.stdout or res.stderr or "").strip()
        return {"success": ok, "ssid": ssid, "message": msg}
    except Exception as e:
        return {"success": False, "ssid": ssid, "message": str(e)}


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "info"
    if action == "info":
        print(json.dumps(get_system_info()))
    elif action == "wifi":
        rescan = "--no-rescan" not in sys.argv
        print(json.dumps(get_wifi_networks(rescan=rescan)))
    elif action == "wifi_connect" and len(sys.argv) > 2:
        ssid_arg = sys.argv[2]
        pwd_arg = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(connect_wifi(ssid_arg, pwd_arg)))
    elif action == "limit":
        lim = int(sys.argv[2]) if len(sys.argv) > 2 else 80
        print(json.dumps(set_battery_limit(lim)))
    elif action == "volume" and len(sys.argv) > 2:
        set_volume(sys.argv[2])
        print(json.dumps({"volume": get_volume_info()}))
    elif action == "mute":
        toggle_mute()
        print(json.dumps({"volume": get_volume_info()}))
    elif action == "brightness" and len(sys.argv) > 2:
        set_brightness(sys.argv[2])
        print(json.dumps({"brightness": get_brightness_pct()}))
    else:
        print(json.dumps(get_system_info()))
