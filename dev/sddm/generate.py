#!/usr/bin/env python3
"""Génère le thème de connexion portable (sddm-astronaut re-coloré).

Sorties, dans dev/sddm/out/ :
  Themes/portable.conf    — configuration complète du thème (couleurs Matugen)
  Backgrounds/portable.png — wallpaper courant assombri, 1920×1080

Sources, jamais dupliquées :
  ~/.config/quickshell/core/style_vars.json  (palette active)
  `awww query`                                (wallpaper réellement affiché)

Aucun fichier n'est écrit hors de dev/sddm/out/ : l'installation dans
/usr/share/sddm/themes/ est le rôle de install.sh (elle demande polkit).

Usage : python3 dev/sddm/generate.py [--no-background]
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

DEV = Path(__file__).resolve().parent
OUT = DEV / "out"
STYLE_VARS = Path.home() / ".config/quickshell/core/style_vars.json"
SCREEN = (1920, 1080)


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
        'Background="Backgrounds/portable.png"',
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
    dst = OUT / "Backgrounds/portable.png"
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
    conf = themes / "portable.conf"
    conf.write_text(build_conf(palette))
    print(f"palette : {name}")
    print(f"conf    : {conf.relative_to(DEV)}")
    if with_bg:
        build_background()


if __name__ == "__main__":
    main()
