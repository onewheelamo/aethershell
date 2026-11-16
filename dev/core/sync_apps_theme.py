#!/usr/bin/env python3
"""Synchronise la palette active d'AetherShell vers GTK 3/4 et Qt5ct/Qt6ct.

Lit `style_vars.json` (même résolution que `generate_terminal_theme.py`) et met à jour :
- `~/.config/gtk-3.0/gtk.css` et `~/.config/gtk-4.0/gtk.css` (bloc géré entre marqueurs)
- `gsettings` `color-scheme` (`prefer-dark` / `prefer-light`)
- `~/.config/qt5ct/colors/aethershell.conf` et `~/.config/qt6ct/colors/aethershell.conf`
"""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


BEGIN_MARK = "/* BEGIN aethershell-theme */"
END_MARK = "/* END aethershell-theme */"


def find_style_file() -> Path:
    base_dir = Path(__file__).resolve().parent
    local_style = base_dir / "style_vars.json"
    if local_style.is_file():
        return local_style
    return Path.home() / ".config" / "quickshell" / "core" / "style_vars.json"


def is_dark(hex_c: str) -> bool:
    h = hex_c.lstrip("#")
    if len(h) != 6:
        return True
    r, g, b = int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0
    return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5


def contrast_fg(bg_hex: str) -> str:
    return "#11111b" if not is_dark(bg_hex) else "#ffffff"


def upsert_marked_block(path: Path, block: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.is_file() else ""
    wrapped = f"{BEGIN_MARK}\n{block.rstrip()}\n{END_MARK}\n"
    pattern = re.compile(
        re.escape(BEGIN_MARK) + r".*?" + re.escape(END_MARK) + r"\n?",
        re.DOTALL,
    )
    if pattern.search(existing):
        updated = pattern.sub(wrapped, existing, count=1)
    else:
        sep = "\n" if existing and not existing.endswith("\n") else ""
        updated = existing + sep + wrapped
    if updated != existing:
        path.write_text(updated, encoding="utf-8")


def sync_gtk(p: dict) -> None:
    bg = p.get("bg", "#1e1e2e")
    fg = p.get("fg", "#cdd6f4")
    accent = p.get("accent", "#b4befe")
    surface = p.get("surface", "#313244")
    surface_var = p.get("surface_variant", "#45475a")
    error = p.get("error", "#f38ba8")
    warn = p.get("warn", "#fab387")
    success = p.get("success", "#a6e3a1")
    accent_fg = contrast_fg(accent)

    css = f"""@define-color accent_color {accent};
@define-color accent_bg_color {accent};
@define-color accent_fg_color {accent_fg};
@define-color window_bg_color {bg};
@define-color window_fg_color {fg};
@define-color view_bg_color {bg};
@define-color view_fg_color {fg};
@define-color headerbar_bg_color {surface};
@define-color headerbar_fg_color {fg};
@define-color card_bg_color {surface};
@define-color card_fg_color {fg};
@define-color dialog_bg_color {surface};
@define-color dialog_fg_color {fg};
@define-color popover_bg_color {surface_var};
@define-color popover_fg_color {fg};
@define-color sidebar_bg_color {surface};
@define-color sidebar_fg_color {fg};
@define-color destructive_color {error};
@define-color warning_color {warn};
@define-color success_color {success};"""

    for ver in ("gtk-3.0", "gtk-4.0"):
        upsert_marked_block(Path.home() / ".config" / ver / "gtk.css", css)

    if shutil.which("gsettings"):
        scheme = "prefer-dark" if is_dark(bg) else "prefer-light"
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", scheme],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def sync_qt(p: dict) -> None:
    bg = p.get("bg", "#1e1e2e")
    fg = p.get("fg", "#cdd6f4")
    accent = p.get("accent", "#b4befe")
    surface = p.get("surface", "#313244")
    surface_var = p.get("surface_variant", "#45475a")
    accent_muted = p.get("accent_muted", "#89b4fa")
    accent_fg = contrast_fg(accent)

    # Palette Qt6ct/Qt5ct (Active / Disabled / Inactive — 21 rôles standard)
    active = ",".join([
        fg, surface, surface_var, surface_var, bg, bg, fg, fg, fg,
        bg, bg, bg, accent, accent_fg, accent_muted, accent_muted,
        surface, fg, surface, fg, accent,
    ])
    scheme_conf = f"[ColorScheme]\nactive_colors={active}\ndisabled_colors={active}\ninactive_colors={active}\n"

    for qt_dir in ("qt5ct", "qt6ct"):
        colors_dir = Path.home() / ".config" / qt_dir / "colors"
        colors_dir.mkdir(parents=True, exist_ok=True)
        (colors_dir / "aethershell.conf").write_text(scheme_conf, encoding="utf-8")


def main() -> int:
    style_path = find_style_file()
    if not style_path.is_file():
        return 0
    try:
        data = json.loads(style_path.read_text(encoding="utf-8"))
    except Exception:
        return 0

    palettes = data.get("palette", {})
    active = data.get("active_theme", "dynamic")
    p = palettes.get(active) or palettes.get("dynamic") or {}
    if not isinstance(p, dict):
        return 0

    sync_gtk(p)
    sync_qt(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
