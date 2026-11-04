#!/usr/bin/env python3
"""Génère le thème de connexion de la session (sddm-astronaut re-coloré).

Sorties, dans dev/sddm/out/ :
  Themes/palette.conf    — configuration complète du thème (couleurs Matugen)
  Backgrounds/wallpaper.png — wallpaper courant assombri, à la taille de l'écran

Sources, jamais dupliquées :
  ~/.config/quickshell/core/style_vars.json  (palette active)
  `awww query`                                (wallpaper réellement affiché)
  `hyprctl monitors -j`                       (taille logique de l'écran focalisé)

Aucun fichier n'est écrit hors de dev/sddm/out/ : l'installation dans
/usr/share/sddm/themes/ est le rôle de install.sh (elle demande polkit).

Usage : python3 dev/sddm/generate.py [--no-background]
        GREETER_SCREEN=2880x1800 python3 dev/sddm/generate.py   (hors session)
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

DEV = Path(__file__).resolve().parent
OUT = DEV / "out"
STYLE_VARS = Path.home() / ".config/quickshell/core/style_vars.json"
SCREEN_FALLBACK = (1920, 1080)


def screen_size():
    """Taille logique de l'écran focalisé, pour que le greeter ne soit pas calé
    sur le moniteur du desktop. `GREETER_SCREEN=WxH` force la valeur : hors
    session (ssh, tty) Hyprland n'a aucun moniteur à interroger."""
    forced = os.environ.get("GREETER_SCREEN", "").strip()
    if re.fullmatch(r"[0-9]{3,5}x[0-9]{3,5}", forced):
        w, h = forced.split("x")
        return int(w), int(h)
    if not shutil.which("hyprctl"):
        return SCREEN_FALLBACK
    try:
        out = subprocess.run(["hyprctl", "monitors", "-j"],
                             capture_output=True, text=True, timeout=5).stdout
        monitors = json.loads(out or "[]")
    except Exception:
        return SCREEN_FALLBACK
    if not monitors:
        return SCREEN_FALLBACK
    mon = next((m for m in monitors if m.get("focused")), monitors[0])
    w, h = int(mon.get("width") or 0), int(mon.get("height") or 0)
    if w <= 0 or h <= 0:
        return SCREEN_FALLBACK
    # `width`/`height` sont logiques : le greeter, lui, s'affiche hors
    # compositeur et ne reçoit aucun facteur d'échelle, donc on repasse en
    # pixels physiques (1920 logique à l'échelle 1,5 = 2880 réels).
    try:
        scale = float(mon.get("scale") or 1.0)
    except (TypeError, ValueError):
        scale = 1.0
    if scale <= 0:
        scale = 1.0
    return round(w * scale), round(h * scale)


SCREEN = screen_size()


def die(msg):
    print(f"generate.py: {msg}", file=sys.stderr)
    sys.exit(1)


def load_palette():
    if not STYLE_VARS.exists():
        die(f"{STYLE_VARS} introuvable")
    data = json.loads(STYLE_VARS.read_text())
    palettes = data.get("palette") or {}
    name = data.get("active_theme") or "dynamic"
    palette = palettes.get(name) or palettes.get("dynamic")
    if not palette:
        die("aucune palette dans style_vars.json")
    return name, palette


def wallpaper():
    """Chemin du wallpaper affiché, via awww ; None si le démon est absent."""
    if not shutil.which("awww"):
        return None
    try:
        out = subprocess.run(["awww", "query"], capture_output=True, text=True,
                             timeout=5).stdout
    except subprocess.TimeoutExpired:
        return None
    marker = "currently displaying: image: "
    for line in out.splitlines():
        if marker in line:
            return Path(line.split(marker, 1)[1].strip())
    return None


def with_alpha(hexcolor, alpha):
    """#RRGGBB + alpha 0..1 → #AARRGGBB (format accepté par QML)."""
    h = hexcolor.lstrip("#")
    a = f"{round(max(0.0, min(1.0, alpha)) * 255):02X}"
    return f"#{a}{h.upper()}"


def build_conf(palette):
    p = {k: v for k, v in palette.items()}
    accent, fg = p["accent"], p["fg"]
    surface, variant, bg = p["surface"], p["surface_variant"], p["bg"]

    colors = {
        # titres et horloge
        "TimeTextColor": fg,
        "DateTextColor": with_alpha(fg, 0.70),
        "HeaderTextColor": accent,
        # panneaux
        "FormBackgroundColor": surface,
        "BackgroundColor": bg,
        "DimBackgroundColor": bg,
        # champs — le thème peint ces fonds à 20 % d'opacité : une teinte claire
        # se lit, une teinte sombre disparaît sur un wallpaper de nuit.
        "LoginFieldBackgroundColor": p.get("accent_muted", accent),
        "PasswordFieldBackgroundColor": p.get("accent_muted", accent),
        "LoginFieldTextColor": fg,
        "PasswordFieldTextColor": fg,
        "UserIconColor": p.get("accent_muted", accent),
        "PasswordIconColor": p.get("accent_muted", accent),
        "PlaceholderTextColor": with_alpha(fg, 0.55),
        "WarningColor": p["error"],
        # bouton principal
        "LoginButtonTextColor": bg,
        "LoginButtonBackgroundColor": accent,
        # boutons secondaires
        "SystemButtonsIconsColor": with_alpha(fg, 0.70),
        "SessionButtonTextColor": with_alpha(fg, 0.60),
        "VirtualKeyboardButtonTextColor": with_alpha(fg, 0.60),
        # listes déroulantes
        "DropdownTextColor": bg,
        "DropdownSelectedBackgroundColor": accent,
        "DropdownBackgroundColor": p.get("accent_muted", accent),
        "HighlightTextColor": bg,
        "HighlightBackgroundColor": accent,
        "HighlightBorderColor": "transparent",
        # survols
        "HoverUserIconColor": accent,
        "HoverPasswordIconColor": accent,
        "HoverSystemButtonsIconsColor": accent,
        "HoverSessionButtonTextColor": accent,
        "HoverVirtualKeyboardButtonTextColor": accent,
    }

    w, h = SCREEN
    lines = [
        "[General]",
        "#################### Généré par dev/sddm/generate.py — ne pas éditer ####################",
        "",
        f'ScreenWidth="{w}"',
        f'ScreenHeight="{h}"',
        'ScreenPadding=""',
        "",
        'Font="Inter"',
        'FontSize="13"',
        'KeyboardSize="0.4"',
        'RoundCorners="24"',
        "",
        'Locale="fr_FR.UTF-8"',
        'HourFormat="HH:mm"',
        'DateFormat="dddd d"',
        'HeaderText=""',
        "",
        "#################### Fond ####################",
        "",
        'Background="Backgrounds/wallpaper.png"',
        'BackgroundPlaceholder=""',
        'BackgroundSpeed="1.0"',
        'PauseBackground=""',
        # 0.45 écrasait un wallpaper nocturne ; 0.20 garde l'image vivante et
        # laisse le panneau flouté se détacher.
        'DimBackground="0.20"',
        'CropBackground="true"',
        'BackgroundHorizontalAlignment="center"',
        'BackgroundVerticalAlignment="center"',
        "",
        "#################### Couleurs ####################",
        "",
    ]
    lines += [f'{key}="{value}"' for key, value in colors.items()]
    lines += [
        "",
        "#################### Formulaire ####################",
        "",
        'PartialBlur="true"',
        'FullBlur=""',
        'BlurMax="32"',
        'Blur="1.6"',
        'HaveFormBackground="true"',
        'FormPosition="center"',
        'VirtualKeyboardPosition="left"',
        "",
        "#################### Comportement ####################",
        "",
        'HideVirtualKeyboard="true"',
        'HideSystemButtons="false"',
        'HideLoginButton="false"',
        'UseRealName="false"',
        'ForceLastUser="true"',
        'PasswordFocus="true"',
        'HideCompletePassword="true"',
        'AllowEmptyPassword="false"',
        'BypassSystemButtonsChecks="false"',
        'RightToLeftLayout="false"',
        "",
        "#################### Libellés ####################",
        "",
        'TranslatePlaceholderUsername=""',
        'TranslatePlaceholderPassword="Mot de passe"',
        'TranslateLogin="Se connecter"',
        'TranslateLoginFailedWarning="Mot de passe incorrect"',
        'TranslateCapslockWarning="Verr. Maj activée"',
        'TranslateSuspend="Veille"',
        'TranslateHibernate="Hiberner"',
        'TranslateReboot="Redémarrer"',
        'TranslateShutdown="Éteindre"',
        'TranslateSessionSelection="Session"',
        'TranslateVirtualKeyboardButtonOn="Clavier"',
        'TranslateVirtualKeyboardButtonOff="Clavier"',
        "",
    ]
    return "\n".join(lines)


def build_background():
    src = wallpaper()
    if not src or not src.exists():
        print("generate.py: wallpaper introuvable, fond inchangé", file=sys.stderr)
        return False
    if not shutil.which("magick"):
        print("generate.py: magick absent, fond inchangé", file=sys.stderr)
        return False
    dst = OUT / "Backgrounds/wallpaper.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    w, h = SCREEN
    # Recadré à l'écran puis assombri à ~55 % : le formulaire doit rester lisible.
    subprocess.run([
        "magick", str(src), "-resize", f"{w}x{h}^", "-gravity", "center",
        "-extent", f"{w}x{h}", "-modulate", "55,100,100", str(dst),
    ], check=True)
    print(f"fond : {src} → {dst.relative_to(DEV)}")
    return True


def main():
    with_bg = "--no-background" not in sys.argv
    name, palette = load_palette()
    themes = OUT / "Themes"
    themes.mkdir(parents=True, exist_ok=True)
    conf = themes / "palette.conf"
    conf.write_text(build_conf(palette))
    print(f"palette : {name}")
    print(f"écran   : {SCREEN[0]}x{SCREEN[1]}")
    print(f"conf    : {conf.relative_to(DEV)}")
    if with_bg:
        build_background()


if __name__ == "__main__":
    main()
