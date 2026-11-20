#!/usr/bin/env python3
"""Lanceur Matrix (`unimatrix -af -l aAksS -s 96`) en fond animé ou écran de veille.

Modes :
  - Par défaut (`as matrix`) : terminal sans bordures en plein écran total
    **derrière** les surfaces Quickshell (`org.aether.matrix-bg`).
  - Écran de veille (`as matrix ss` ou `as matrix 10 ss`) : terminal sans
    bordures en plein écran total **devant** tout l'écran (`org.aether.matrix-ss`),
    qui se ferme au moindre mouvement de souris ou frappe clavier.
  - Arrêt (`as matrix stop`) : ferme l'instance active et annule tout délai.
"""
from __future__ import annotations

import argparse
import fcntl
import os
import pty
import select
import shutil
import signal
import struct
import subprocess
import sys
import termios
import threading
import time
import tty
from pathlib import Path

PID_FILE = Path("/tmp/aether_matrix.pid")
UNIMATRIX_CMD = ["unimatrix", "-af", "-l", "aAksS", "-s", "96"]


def _trouver_terminal():
    for cand in ("ghostty", "kitty", "foot", "alacritty"):
        if shutil.which(cand):
            return cand
    return "xterm"


def _arreter_precedent():
    if not PID_FILE.exists():
        return
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8").strip())
        os.killpg(pid, signal.SIGTERM)
    except (OSError, ValueError):
        try:
            pid = int(PID_FILE.read_text(encoding="utf-8").strip())
            os.kill(pid, signal.SIGTERM)
        except (OSError, ValueError):
            pass
    try:
        PID_FILE.unlink()
    except OSError:
        pass


def _cursor_pos():
    try:
        res = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True, timeout=0.4)
        if res.returncode == 0 and "," in res.stdout:
            x_s, y_s = res.stdout.strip().split(",", 1)
            return int(x_s.strip()), int(y_s.strip())
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return None


def _run_screensaver():
    """Exécute `unimatrix` dans un PTY et quitte dès qu'une touche ou la souris bouge."""
    if not sys.stdin.isatty():
        os.execvp(UNIMATRIX_CMD[0], UNIMATRIX_CMD)

    master_fd, slave_fd = pty.openpty()

    def _sync_winsize(*_args):
        try:
            ws = fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\x00" * 8)
            fcntl.ioctl(master_fd, termios.TIOCSWINSZ, ws)
        except OSError:
            pass

    _sync_winsize()
    signal.signal(signal.SIGWINCH, _sync_winsize)

    proc = subprocess.Popen(
        UNIMATRIX_CMD,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        close_fds=True,
        start_new_session=True,
    )
    os.close(slave_fd)

    stop_event = threading.Event()

    def _watch_mouse():
        # Courte grâce au démarrage pour que l'ouverture du terminal ne déclenche rien.
        time.sleep(0.45)
        initial = _cursor_pos()
        if initial is None:
            return
        while not stop_event.is_set() and proc.poll() is None:
            cur = _cursor_pos()
            if cur is not None and (abs(cur[0] - initial[0]) > 2 or abs(cur[1] - initial[1]) > 2):
                stop_event.set()
                break
            time.sleep(0.08)

    mouse_thread = threading.Thread(target=_watch_mouse, daemon=True)
    mouse_thread.start()

    old_tty = termios.tcgetattr(sys.stdin.fileno())
    try:
        tty.setraw(sys.stdin.fileno())
        stdin_fd = sys.stdin.fileno()
        stdout_fd = sys.stdout.fileno()
        while not stop_event.is_set() and proc.poll() is None:
            rlist, _, _ = select.select([master_fd, stdin_fd], [], [], 0.08)
            if master_fd in rlist:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                os.write(stdout_fd, data)
            if stdin_fd in rlist:
                try:
                    _ = os.read(stdin_fd, 64)
                except OSError:
                    pass
                stop_event.set()
                break
    finally:
        stop_event.set()
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old_tty)
        try:
            os.close(master_fd)
        except OSError:
            pass
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except OSError:
                proc.terminate()
            try:
                proc.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                proc.kill()
    return 0


def _cmd_terminal(ss, inner_cmd):
    if shutil.which("kitten"):
        kitty_theme = Path.home() / ".config" / "kitty" / "aethershell-theme.conf"
        cfg_args = ["--config", str(kitty_theme)] if kitty_theme.is_file() else []
        if ss:
            return [
                "kitten", "panel",
                *cfg_args,
                "--edge=center",
                "--layer=overlay",
                "--exclusive-zone=-1",
                "--focus-policy=exclusive",
                "--grab-keyboard=yes",
                "-o", "window_padding_width=0",
                "-o", "hide_window_decorations=yes",
                "--",
            ] + inner_cmd
        return [
            "kitten", "panel",
            *cfg_args,
            "--edge=background",
            "--focus-policy=not-allowed",
            "-o", "window_padding_width=0",
            "-o", "hide_window_decorations=yes",
            "--",
        ] + inner_cmd

    classe = "org.aether.matrix-ss" if ss else "org.aether.matrix-bg"
    term = _trouver_terminal()
    if term == "ghostty":
        return [
            "ghostty",
            f"--class={classe}",
            "--window-decoration=false",
            "-e",
        ] + inner_cmd
    if term == "kitty":
        return ["kitty", "--class", classe, "-o", "hide_window_decorations=yes"] + inner_cmd
    if term == "foot":
        return ["foot", "--app-id", classe] + inner_cmd
    if term == "alacritty":
        return ["alacritty", "--class", classe, "-o", "window.decorations=\"None\"", "-e"] + inner_cmd
    return [term, "-e"] + inner_cmd


def _lancer(ss=False, delay_min=0):
    _arreter_precedent()

    # Délai éventuel (ex. « as matrix 10 ss ») : on détache un processus fils qui
    # attend puis lance le terminal, en enregistrant son PGID dans PID_FILE.
    if delay_min > 0:
        pid = os.fork()
        if pid > 0:
            return 0
        os.setsid()
        PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
        time.sleep(delay_min * 60)

    inner = [sys.executable, str(Path(__file__).resolve()), "--run-ss"] if ss else UNIMATRIX_CMD
    cmd = _cmd_terminal(ss, inner)
    proc = subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    PID_FILE.write_text(str(proc.pid), encoding="utf-8")
    return 0


def main():
    ap = argparse.ArgumentParser(description="Fond animé / écran de veille Matrix (unimatrix)")
    ap.add_argument("--ss", action="store_true", help="Mode écran de veille (devant tout, quitte sur souris/clavier)")
    ap.add_argument("--delay", type=float, default=0.0, help="Délai avant lancement en minutes")
    ap.add_argument("--stop", action="store_true", help="Arrêter le fond/veille Matrix actif ou en attente")
    ap.add_argument("--run-ss", action="store_true", help="Exécuteur interne PTY pour le mode écran de veille")
    args = ap.parse_args()

    if args.run_ss:
        return _run_screensaver()
    if args.stop:
        _arreter_precedent()
        return 0
    return _lancer(ss=args.ss, delay_min=max(0.0, args.delay))


if __name__ == "__main__":
    raise SystemExit(main())
