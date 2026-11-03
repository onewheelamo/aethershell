"""Helpers shared by config_manager.py and tablet_mode_daemon.py.

Hyprland monitor rules are replaced as a whole: sending only `transform` (or only `mode`)
can reset the other fields (position, scale...). `apply_monitor` therefore re-sends the
current position and scale unless they are explicitly overridden.
"""
import json
import re
import subprocess

OUTPUT_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,32}$")
MODE_RE = re.compile(r"^(preferred|highres|highrr|\d{3,5}x\d{3,5}(@\d{1,3}(\.\d+)?)?)$")
SCALE_RE = re.compile(r"^\d(\.\d{1,2})?$")


def hyprctl_json(*args):
    try:
        out = subprocess.check_output(["hyprctl", *args, "-j"], stderr=subprocess.DEVNULL, timeout=5)
        return json.loads(out.decode("utf-8"))
    except Exception:
        return None


def get_monitor(output_name, include_disabled=False):
    for m in hyprctl_json("monitors") or []:
        if m.get("name") == output_name:
            return m
    if include_disabled:
        for m in hyprctl_json("monitors", "all") or []:
            if m.get("name") == output_name:
                return m
    return None


def _mode_key(mode):
    """'1920x1080@60.00Hz' / '1920x1080@60' -> ('1920x1080', 60.0); keywords -> None."""
    m = re.match(r"^(\d+x\d+)(?:@([\d.]+)(?:Hz)?)?$", str(mode))
    if not m:
        return None
    return m.group(1), (round(float(m.group(2)), 1) if m.group(2) else None)


def mode_supported(monitor, mode):
    """True if `mode` is a keyword or is listed in the monitor's availableModes."""
    key = _mode_key(mode)
    if key is None:
        return True
    avail = [_mode_key(a) for a in (monitor or {}).get("availableModes", [])]
    avail = [a for a in avail if a]
    if not avail:
        return True  # unknown capabilities: let Hyprland decide
    res, rate = key
    return any(res == r and (rate is None or abs(rate - hz) < 0.6) for r, hz in avail)


def apply_monitor(output_name, mode=None, scale=None, transform=None, position=None, only_if_active=False):
    """Apply a full monitor rule, keeping current position/scale/mode unless overridden.

    Returns True if the rule was sent. Invalid arguments are rejected (never injected
    in the Lua string).
    If only_if_active is True and the monitor is currently disabled / not in active outputs,
    the call is a no-op (returns False) to avoid unintendedly waking up disabled screens (e.g. dock mode).
    """
    if not OUTPUT_RE.match(str(output_name)):
        return False
    if mode is not None and not MODE_RE.match(str(mode)):
        return False
    if scale is not None and not SCALE_RE.match(str(scale)):
        return False

    active_cur = get_monitor(output_name, include_disabled=False)
    if only_if_active and active_cur is None:
        return False

    cur = active_cur or get_monitor(output_name, include_disabled=True)
    if mode is not None and not mode_supported(cur, mode):
        return False
    cur_transform = int(cur.get("transform", 0)) if cur else 0

    if position is None:
        cur_x = cur.get("x") if cur else None
        cur_y = cur.get("y") if cur else None
        position = f"{cur_x}x{cur_y}" if (cur_x is not None and cur_y is not None) else "auto"
    if scale is None:
        scale = cur.get("scale", 1) if cur else 1
    if transform is None:
        transform = cur_transform
    if mode is None:
        # width/height are only trusted when the monitor is not rotated by 90/270 deg
        cur_w = cur.get("width") if cur else None
        cur_h = cur.get("height") if cur else None
        if cur and cur_w and cur_h and cur_transform % 2 == 0:
            rate = round(float(cur.get("refreshRate", 60)), 2)
            mode = f"{cur_w}x{cur_h}@{rate}"
        else:
            mode = "preferred"

    lua = (
        f'hl.monitor({{ output = "{output_name}", mode = "{mode}", '
        f'position = "{position}", scale = {scale}, transform = {int(transform)} }})'
    )
    subprocess.run(["hyprctl", "eval", lua], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return True
