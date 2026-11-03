import json
import os
import shutil
import signal
import time
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from monitor_utils import apply_monitor  # noqa: E402
from runtime_paths import runtime_path  # noqa: E402

STATE_FILE = runtime_path("tablet_mode")


def mode_for_transform(transform):
    """Single source of truth: any rotation other than normal counts as tablet use."""
    return "laptop" if int(transform) % 4 == 0 else "tablet"


def set_mode(mode, transform=None):
    """
    Set laptop or tablet mode on convertible devices (e.g. Lenovo Yoga portable).
    `transform` (0-3) wins over `mode`; without it, laptop=0 and tablet=2.
    """
    if transform is None:
        transform = 2 if mode == "tablet" else 0
    transform = int(transform) % 4
    clean_mode = mode_for_transform(transform)

    apply_monitor("eDP-1", transform=transform, only_if_active=True)

    try:
        with open(STATE_FILE, "w") as f:
            f.write(clean_mode)
    except Exception:
        pass
    return {"mode": clean_mode, "transform": transform}


def get_current_mode():
    if not os.path.exists(STATE_FILE):
        return "laptop"
    try:
        with open(STATE_FILE, "r") as f:
            return f.read().strip() or "laptop"
    except Exception:
        return "laptop"


RETRY_MIN_DELAY = 3
RETRY_MAX_DELAY = 120
HEALTHY_SESSION_SECONDS = 30
MAX_QUICK_FAILURES = 5

ORIENTATION_MAP = {
    "normal": ("laptop", 0),
    "bottom-up": ("tablet", 2),
    "left-up": ("tablet", 1),
    "right-up": ("tablet", 3),
}
assert all(mode_for_transform(tf) == mode for mode, tf in ORIENTATION_MAP.values())


def _watch_once():
    """Run one `monitor-sensor` session. Returns True if an accelerometer was claimed, False otherwise."""
    proc = subprocess.Popen(
        ["monitor-sensor", "--accel"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    has_accel = False
    try:
        for line in proc.stdout:
            if "Accelerometer mounted" in line or "=== Has accelerometer" in line:
                has_accel = True
            elif "Failed to claim accelerometer" in line or "No iio-sensor-proxy" in line:
                return False
            elif "Accelerometer orientation changed:" in line:
                has_accel = True
                orient = line.split(":", 1)[1].strip()
                if orient in ORIENTATION_MAP:
                    mode, tf = ORIENTATION_MAP[orient]
                    set_mode(mode, tf)
    finally:
        # Never leave an orphan monitor-sensor behind
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
    return has_accel


def watch_accelerometer():
    """Listen to iio-sensor-proxy (`monitor-sensor`) on a convertible laptop.

    Restarts monitor-sensor if it exits (e.g. iio-sensor-proxy restarted) and shuts
    down cleanly on SIGTERM/SIGINT, or stops if no accelerometer is present.
    """
    if not shutil.which("monitor-sensor"):
        return

    def _stop(_signum, _frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    # Explicit "no accelerometer" -> _watch_once() returns False: stop for good.
    # Any other quick exit (iio-sensor-proxy restarting, crash...) is retried with an
    # exponential backoff and abandoned after several consecutive quick failures.
    delay = RETRY_MIN_DELAY
    quick_failures = 0
    while True:
        started = time.monotonic()
        if not _watch_once():
            break
        if time.monotonic() - started >= HEALTHY_SESSION_SECONDS:
            delay = RETRY_MIN_DELAY
            quick_failures = 0
        else:
            quick_failures += 1
            if quick_failures >= MAX_QUICK_FAILURES:
                print("tablet_mode_daemon: monitor-sensor keeps exiting, giving up", file=sys.stderr)
                break
            delay = min(delay * 2, RETRY_MAX_DELAY)
        time.sleep(delay)


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action in ("laptop", "tablet"):
        print(json.dumps(set_mode(action)))
    elif action == "toggle":
        next_mode = "laptop" if get_current_mode() == "tablet" else "tablet"
        print(json.dumps(set_mode(next_mode)))
    elif action == "daemon":
        watch_accelerometer()
    else:
        print(json.dumps({"mode": get_current_mode()}))
