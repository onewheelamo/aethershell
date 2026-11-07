"""
═══════════════════════════════════════════════════════════════════════════════
CONFIGURATION MANAGER BACKEND (config_manager.py)
═══════════════════════════════════════════════════════════════════════════════
Core backend service bridging Quickshell QML interfaces and Hyprland's modular
Lua configurations (~/.config/hypr/*.lua).

Architecture Overview:
  • Section 1: Constants, Paths, Color Keys, Matugen Schemes & Keysyms
  • Section 2: Core Utility Functions & Safe Lua String/Identifier Serializers
  • Section 3: Keyboard Layout & First-Run Onboarding (input.lua & binds.lua)
  • Section 4: Appearance & Styling (style_vars.json, general.lua, Matugen)
  • Section 5: System & Display Management (monitors.lua, HDMI/eDP profiles)
  • Section 6: Keybindings Management (binds.lua parsing & AST updates)
  • Section 7: Dynamic Variables & Applications (app_vars.json <-> programs.lua)
  • Section 8: Autostart Management (autostart.json <-> exec.lua)
  • Section 9: Full State Aggregator & CLI Entry Point
═══════════════════════════════════════════════════════════════════════════════
"""

import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import llm_providers  # noqa: E402
import monitor_utils  # noqa: E402
import tablet_mode_daemon  # noqa: E402

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: CONSTANTS, PATHS, SCHEMES & KEYSYMS
# ─────────────────────────────────────────────────────────────────────────────
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEV_ROOT = os.path.dirname(BASE_DIR)
STYLE_FILE = os.path.join(BASE_DIR, "style_vars.json")
WIDGETS_FILE = os.path.join(BASE_DIR, "widgets.json")
APP_VARS_FILE = os.path.join(BASE_DIR, "app_vars.json")
# Cible du clic sur une notification (hint/table/types) : fichier d'état, préservé
# au déploiement, relu par core/notif_target.py à chaque notification.
NOTIF_TARGETS_FILE = os.path.join(BASE_DIR, "notif_targets.json")
AUTOSTART_FILE = os.path.join(BASE_DIR, "autostart.json")
ROFI_GEN_SCRIPT = os.path.join(BASE_DIR, "generate_rofi_theme.sh")
COLORS_GEN_SCRIPT = os.path.join(BASE_DIR, "generate_colors.sh")
SYSTEM_SERVICE = os.path.join(BASE_DIR, "system_service.py")

# Detect whether we are running in ~/.config/quickshell/core or in dev/core
if BASE_DIR.startswith(os.path.expanduser("~/.config/quickshell")):
    HYPR_DIR = os.path.expanduser("~/.config/hypr")
else:
    HYPR_DIR = os.path.join(DEV_ROOT, "hypr_modular")

COLOR_KEYS = {"bg", "fg", "accent", "accent_muted", "surface", "surface_variant", "error", "warn", "info", "success"}

# Matugen color-scheme types accepted by `matugen image -t`
MATUGEN_SCHEMES = {
    "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
    "scheme-neutral", "scheme-monochrome", "scheme-fruit-salad",
    "scheme-content", "scheme-fidelity", "scheme-rainbow",
}

# Explicit Workspace 1..10 keysym nomenclature per keyboard layout
WORKSPACE_KEYS_BY_LAYOUT = {
    "fr": ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "minus", "egrave", "underscore", "ccedilla", "agrave"],
    "be": ["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "section", "egrave", "exclam", "ccedilla", "agrave"],
    "us": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "gb": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "de": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "es": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    "ch": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
}


LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}
KEY_COMBO_RE = re.compile(r"^[A-Za-z0-9_:+ -]{1,60}$")


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: UTILITY FUNCTIONS & SAFE LUA SERIALIZERS
# ─────────────────────────────────────────────────────────────────────────────

def lua_str(value):
    """Return `value` as a safe double-quoted Lua string literal."""
    out = []
    for ch in str(value):
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            continue
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_ident(alias):
    """Turn an app alias into a valid, non-reserved Lua identifier ('' if impossible)."""
    ident = re.sub(r"[^a-z0-9_]", "_", str(alias).strip().lower()).strip("_")
    if not ident:
        return ""
    if ident[0].isdigit():
        ident = "app_" + ident
    if ident in LUA_KEYWORDS:
        ident = "app_" + ident
    return ident


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r") as f:
        return json.load(f)


def save_json(path, data):
    tmp_path = f"{path}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, "w") as f:
            json.dump(data, f, indent=4)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        raise


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
    return out.lower() if out else "machine"


def is_laptop_system():
    """Un portable a une batterie ; une tour n'en a pas. Le nom de la machine
    n'entre plus dans cette décision (il n'a rien à faire dans un dépôt partagé)."""
    return bool(glob.glob("/sys/class/power_supply/BAT*"))


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: KEYBOARD LAYOUT & FIRST-RUN ONBOARDING (input.lua & binds.lua)
# ─────────────────────────────────────────────────────────────────────────────

def get_kb_layout():
    """Read current kb_layout from input.lua (default: 'fr')."""
    input_path = os.path.join(HYPR_DIR, "input.lua")
    if os.path.exists(input_path):
        try:
            with open(input_path, "r") as f:
                txt = f.read()
            m = re.search(r'kb_layout\s*=\s*"([^"]+)"', txt)
            if m:
                return m.group(1).strip().lower()
        except Exception:
            pass
    style_data = load_json(STYLE_FILE)
    return style_data.get("kb_layout", "fr")


def set_kb_layout(layout, mark_first_run_done=True):
    """
    Update kb_layout in input.lua AND convert workspace 1..5 explicit key names in binds.lua
    so that AZERTY ('fr'/'be') uses ampersand..parenleft and QWERTY ('us', etc.) uses 1..5.
    """
    clean_layout = re.sub(r"[^a-zA-Z_-]", "", str(layout).strip().lower()) or "fr"
    ws_keys = WORKSPACE_KEYS_BY_LAYOUT.get(clean_layout, WORKSPACE_KEYS_BY_LAYOUT["us"])

    # 1. Update input.lua
    input_path = os.path.join(HYPR_DIR, "input.lua")
    if os.path.exists(input_path):
        try:
            with open(input_path, "r") as f:
                txt = f.read()
            txt = re.sub(r'(kb_layout\s*=\s*")[^"]+(")', rf"\g<1>{clean_layout}\g<2>", txt)
            with open(input_path, "w") as f:
                f.write(txt)
        except Exception as e:
            print(f"Error updating input.lua: {e}")

    # 2. Update explicit workspace key names in binds.lua while preserving exact nomenclature format
    binds_path = os.path.join(HYPR_DIR, "binds.lua")
    if os.path.exists(binds_path):
        try:
            with open(binds_path, "r") as f:
                btxt = f.read()
            for idx, new_key in enumerate(ws_keys, start=1):
                # Le préfixe (modificateurs éventuels) est conservé tel quel et les
                # motifs sont indépendants du modificateur : la version précédente
                # n'acceptait que « CTRL + » pour le déplacement silencieux, alors
                # que binds.lua écrit ce bind avec SHIFT — la touche gardait donc
                # son nom AZERTY sur un clavier QWERTY.
                for motif in (
                    rf'(hl\.bind\(\s*mainMod\s*\.\.\s*"[^"]*\+\s*)([^"+]+)'
                    rf'("\s*,\s*hl\.dsp\.focus\(\{{\s*workspace\s*=\s*{idx}\s*\}}\s*\))',
                    rf'(hl\.bind\(\s*mainMod\s*\.\.\s*"[^"]*\+\s*)([^"+]+)'
                    rf'("\s*,\s*hl\.dsp\.window\.move\(\{{\s*workspace\s*=\s*{idx}\b[^}}]*\}}\s*\))',
                ):
                    btxt = re.sub(motif, rf"\g<1>{new_key}\g<3>", btxt)
            with open(binds_path, "w") as f:
                f.write(btxt)
        except Exception as e:
            print(f"Error updating workspace binds in binds.lua: {e}")

    # 3. Persist state in style_vars.json (watched by Theme.qml)
    style_data = load_json(STYLE_FILE)
    style_data["kb_layout"] = clean_layout
    if mark_first_run_done:
        style_data["first_run_completed"] = True
    save_json(STYLE_FILE, style_data)

    # 4. Apply live in Hyprland (Lua config evaluation + reload for binds)
    subprocess.run(
        ["hyprctl", "eval", f'hl.config({{ input = {{ kb_layout = "{clean_layout}" }} }})'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    subprocess.run(
        ["hyprctl", "reload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return True


def complete_first_run():
    style_data = load_json(STYLE_FILE)
    style_data["first_run_completed"] = True
    if "kb_layout" not in style_data:
        style_data["kb_layout"] = get_kb_layout()
    save_json(STYLE_FILE, style_data)
    return True


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: APPEARANCE & STYLING (Gaps, Rounding, Wallpaper, Matugen, Opacity)
# ─────────────────────────────────────────────────────────────────────────────

def get_hypr_gaps():
    """Read current gaps_in, gaps_out, border_size from general.lua."""
    gen_path = os.path.join(HYPR_DIR, "general.lua")
    res = {"gaps_in": 2, "gaps_out": 8, "border_size": 2}
    if not os.path.exists(gen_path):
        return res
    try:
        with open(gen_path, "r") as f:
            txt = f.read()
        for key in ("gaps_in", "gaps_out", "border_size"):
            m = re.search(rf"{key}\s*=\s*(\d+)", txt)
            if m:
                res[key] = int(m.group(1))
    except Exception:
        pass
    return res


def get_hypr_rounding():
    """Read current decoration.rounding from general.lua or style_vars.json."""
    gen_path = os.path.join(HYPR_DIR, "general.lua")
    if os.path.exists(gen_path):
        try:
            with open(gen_path, "r") as f:
                txt = f.read()
            m = re.search(r"\brounding\s*=\s*(\d+)", txt)
            if m:
                return int(m.group(1))
        except Exception:
            pass
    style_data = load_json(STYLE_FILE)
    return int(style_data.get("hypr_rounding", 2))


def get_hypr_rounding_power():
    """Forme des coins : decoration.rounding_power (2 = arc de cercle).

    En dessous de 2, Hyprland redresse le coin jusqu'à la droite à 45° (1 donne
    un chanfrein) ; au-dessus, il l'arrondit en « squircle ».
    """
    gen_path = os.path.join(HYPR_DIR, "general.lua")
    if os.path.exists(gen_path):
        try:
            with open(gen_path, "r") as f:
                txt = f.read()
            m = re.search(r"\brounding_power\s*=\s*([\d.]+)", txt)
            if m:
                return max(1, min(2, int(round(float(m.group(1))))))
        except Exception:
            pass
    style_data = load_json(STYLE_FILE)
    return max(1, min(2, int(round(float(style_data.get("hypr_rounding_power", 2))))))


def update_hypr_gaps(key, val):
    """Update gaps_in, gaps_out, or border_size in general.lua and apply live via hyprctl eval."""
    if key not in ("gaps_in", "gaps_out", "border_size"):
        return False
    ival = max(0, min(60, int(float(val))))
    gen_path = os.path.join(HYPR_DIR, "general.lua")
    if os.path.exists(gen_path):
        try:
            with open(gen_path, "r") as f:
                txt = f.read()
            txt = re.sub(rf"({key}\s*=\s*)\d+", rf"\g<1>{ival}", txt)
            with open(gen_path, "w") as f:
                f.write(txt)
        except Exception as e:
            print(f"Error updating general.lua: {e}")

    subprocess.run(
        ["hyprctl", "eval", f"hl.config({{ general = {{ {key} = {ival} }} }})"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return True


# ─────────────────────────────────────────────────────────────────────────────
# Flou des surfaces Quickshell (layer rules) : bloc Lua généré dans general.lua
# ─────────────────────────────────────────────────────────────────────────────
# Les layer rules ne sont pas pilotables à chaud en 0.57 (`hyprctl keyword
# layerrule` répond « unknown request ») : le panneau réécrit donc ce bloc entre
# ses marqueurs, puis recharge Hyprland. Les namespaces viennent de main.qml.
SHELL_BLUR_BEGIN = "-- BEGIN shell-blur"
SHELL_BLUR_END = "-- END shell-blur"
# Les barres annexes (`shell-bar-bas`, `shell-bar-cote-*`) doivent y figurer :
# le panneau reecrit ce bloc des qu'un reglage de flou change, et une entree
# ajoutee a la main dans general.lua disparaitrait a ce moment-la.
SHELL_BLUR_NAMESPACES = ("shell-bar", "shell-bar-bas", "shell-bar-cote-gauche",
                         "shell-bar-cote-droite", "shell-osd", "shell-config",
                         "shell-onboarding", "shell-spotlight",
                         "shell-spotlight-rest", "shell-cheatsheet",
                         "shell-tray-menu", "shell-shotbar",
                         "shell-menu-session", "shell-menu-widget")
SHELL_BLUR_KEYS = ("shell_blur_enabled", "shell_blur_alpha", "shell_blur_popups")
# Colors proposées au visualiseur : des jetons du thème, pas des valeurs libres —
# une couleur en dur ne suivrait pas un changement de palette.
VIZ_COULEURS = ("accent", "accentMuted", "fg", "warn", "success")

# Positions prédéfinies de la capsule du lanceur (pas de position libre) :
# bord haut/bas, centre ou tiers gauche/droit.
LAUNCHER_POSITIONS = (
    "bas-centre",
    "haut-centre",
    "bas-gauche",
    "bas-droit",
    "haut-gauche",
    "haut-droit",
)


def build_shell_blur_block(enabled, alpha, popups, extra_namespaces=()):
    """Return the Lua block (markers included) for the given shell blur settings.

    `extra_namespaces` porte les widgets de bureau qui demandent le flou : un
    widget = un namespace (`shell-widget-<id>`), donc un `layer_rule` à part. La
    force du flou reste globale (decoration.blur.size/passes) ; par widget on ne
    choisit que « flou ou pas », et l'opacité du widget doit rester au-dessus du
    seuil `ignore_alpha`, sinon le flou disparaît (comportement voulu).
    """
    flag = lambda b: "true" if b else "false"
    all_ns = list(SHELL_BLUR_NAMESPACES) + [ns for ns in extra_namespaces if ns not in SHELL_BLUR_NAMESPACES]
    namespaces = ", ".join(f'"{ns}"' for ns in all_ns)
    return "\n".join((
        SHELL_BLUR_BEGIN,
        "local shell_blur = {",
        f"    enabled = {flag(enabled)},  -- flou derrière les surfaces du shell",
        f"    alpha   = {alpha:.2f},   -- sous ce seuil d'opacité, pas de flou (ignore_alpha)",
        f"    popups  = {flag(popups)},  -- flou derrière les popups ancrés (calendrier, wifi…)",
        "}",
        "if shell_blur.enabled then",
        f"    for _, ns in ipairs({{ {namespaces} }}) do",
        "        hl.layer_rule({",
        "            match        = { namespace = ns },",
        "            blur         = true,",
        "            blur_popups  = shell_blur.popups,",
        "            ignore_alpha = shell_blur.alpha,",
        "        })",
        "    end",
        "end",
        SHELL_BLUR_END,
    ))


def apply_shell_blur(data=None):
    """Rewrite the shell-blur block of general.lua from style_vars.json, then reload Hyprland."""
    src = data if data is not None else load_json(STYLE_FILE)
    enabled = bool(src.get("shell_blur_enabled", True))
    alpha = round(max(0.0, min(1.0, float(src.get("shell_blur_alpha", 0.4)))), 2)
    popups = bool(src.get("shell_blur_popups", True))
    widget_namespaces = [f"shell-widget-{w.get('id')}" for w in load_widgets()
                         if w.get("blur", True) and w.get("id")]
    changed = False
    path = os.path.join(HYPR_DIR, "general.lua")
    if not os.path.exists(path):
        return False
    try:
        with open(path, "r", encoding="utf-8") as f:
            txt = f.read()
        pattern = re.compile(re.escape(SHELL_BLUR_BEGIN) + r".*?" + re.escape(SHELL_BLUR_END), re.S)
        if not pattern.search(txt):
            print("shell blur block not found in general.lua", file=sys.stderr)
            return False
        new_txt, count = pattern.subn(build_shell_blur_block(enabled, alpha, popups, widget_namespaces), txt)
        if count and new_txt != txt:
            with open(path, "w", encoding="utf-8") as f:
                f.write(new_txt)
            changed = True
    except Exception as e:
        print(f"Error updating shell blur block: {e}", file=sys.stderr)
        return False
    # Ne recharger que si le bloc a réellement changé : chaque `hyprctl reload`
    # recrée les surfaces et ramène le workspace 1 au premier plan, ce qui
    # déplaçait l'utilisateur à chaque réglage d'opacité.
    if changed:
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return True


def get_wallpaper_dir():
    """Return configured wallpaper directory (default: '$HOME/Images/wallpapers/')."""
    style_data = load_json(STYLE_FILE)
    wdir = str(style_data.get("wallpaper_dir", "")).strip()
    if wdir:
        return wdir
    for cfg in (
        os.path.expanduser("~/.config/quickshell/hyprquickpaper/config.json"),
        os.path.join(DEV_ROOT, "hyprquickpaper", "config.json"),
    ):
        if os.path.exists(cfg):
            try:
                val = str(load_json(cfg).get("wallpaper_path", "")).strip()
                if val:
                    return val
            except Exception:
                pass
    return "$HOME/Images/wallpapers/"


def set_wallpaper_dir(path_str):
    """Persist wallpaper directory in style_vars.json AND sync hyprquickpaper/config.json."""
    raw = str(path_str).strip()
    if not raw:
        return False
    # Normalize ~ at the start into $HOME for compatibility with hyprquickpaper/config.json
    if raw == "~":
        clean_dir = "$HOME/"
    elif raw.startswith("~/"):
        clean_dir = "$HOME/" + raw[2:]
    else:
        clean_dir = raw
    if not clean_dir.endswith("/"):
        clean_dir += "/"

    style_data = load_json(STYLE_FILE)
    style_data["wallpaper_dir"] = clean_dir
    save_json(STYLE_FILE, style_data)

    for cfg_path in (
        os.path.join(DEV_ROOT, "hyprquickpaper", "config.json"),
        os.path.expanduser("~/.config/quickshell/hyprquickpaper/config.json"),
    ):
        if os.path.exists(cfg_path):
            try:
                cfg = load_json(cfg_path)
                cfg["wallpaper_path"] = clean_dir
                save_json(cfg_path, cfg)
            except Exception as e:
                print(f"Error updating {cfg_path}: {e}", file=sys.stderr)
    return True


def get_screenshots_dir():
    """Return the configured screenshot directory (default: '$HOME/Images/Screenshots/')."""
    style_data = load_json(STYLE_FILE)
    sdir = str(style_data.get("screenshots_dir", "")).strip()
    return sdir or "$HOME/Images/Screenshots/"


def set_screenshots_dir(path_str):
    """Persist the screenshot directory in style_vars.json (read by core/screenshot.sh).

    Même normalisation que `wallpaper_dir` : `~` devient `$HOME`, le chemin finit
    par un `/`, et la valeur reste lisible telle quelle dans le panneau.
    """
    raw = str(path_str).strip()
    if not raw:
        return False
    if raw == "~":
        clean_dir = "$HOME/"
    elif raw.startswith("~/"):
        clean_dir = "$HOME/" + raw[2:]
    else:
        clean_dir = raw
    if not clean_dir.endswith("/"):
        clean_dir += "/"

    style_data = load_json(STYLE_FILE)
    style_data["screenshots_dir"] = clean_dir
    save_json(STYLE_FILE, style_data)
    return True


def set_panel_section(name, expanded):
    data = load_json(STYLE_FILE)
    sections = data.get("panel_sections", {})
    sections[name] = bool(expanded)
    data["panel_sections"] = sections
    save_json(STYLE_FILE, data)


def update_style_var(key, value):
    if key == "wallpaper_dir":
        return set_wallpaper_dir(value)
    if key == "screenshots_dir":
        return set_screenshots_dir(value)
    if key == "do_not_disturb":
        # Drapeau du centre de notifications : les toasts se taisent, l'historique
        # continue de se remplir. Écrit par le panneau, relu par Theme.qml.
        data = load_json(STYLE_FILE)
        data[key] = str(value).strip().lower() in ("1", "true", "oui", "yes", "on")
        save_json(STYLE_FILE, data)
        return True

    data = load_json(STYLE_FILE)
    shell_blur_changed = False
    if key == "global_radius":
        data[key] = max(0, min(30, int(float(value))))
    elif key == "hypr_rounding":
        ival = max(0, min(35, int(float(value))))
        data[key] = ival
        gen_path = os.path.join(HYPR_DIR, "general.lua")
        if os.path.exists(gen_path):
            try:
                with open(gen_path, "r") as f:
                    txt = f.read()
                txt = re.sub(r"(\brounding\s*=\s*)\d+", rf"\g<1>{ival}", txt)
                with open(gen_path, "w") as f:
                    f.write(txt)
            except Exception as e:
                print(f"Error updating general.lua: {e}")
        subprocess.run(
            ["hyprctl", "eval", f"hl.config({{ decoration = {{ rounding = {ival} }} }})"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    elif key == "hypr_rounding_power":
        # 1 = coin coupé en droite, 2 = arc de cercle : au-delà, la différence ne
        # se voit pas, et le panneau ne propose que ces deux valeurs.
        fval = max(1, min(2, int(round(float(value)))))
        data[key] = fval
        gen_path = os.path.join(HYPR_DIR, "general.lua")
        if os.path.exists(gen_path):
            try:
                with open(gen_path, "r") as f:
                    txt = f.read()
                txt = re.sub(r"(\brounding_power\s*=\s*)[\d.]+", rf"\g<1>{fval:g}", txt)
                with open(gen_path, "w") as f:
                    f.write(txt)
            except Exception as e:
                print(f"Error updating general.lua: {e}")
        subprocess.run(
            ["hyprctl", "eval", f"hl.config({{ decoration = {{ rounding_power = {fval:g} }} }})"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    elif key == "global_opacity":
        data[key] = round(max(0.3, min(1.0, float(value))), 2)
    elif key == "shell_opacity":
        data[key] = round(max(0.2, min(1.0, float(value))), 2)
    elif key == "bar_border":
        data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "viz_fps":
        data[key] = max(10, min(60, int(float(value))))
    elif key == "viz_cols":
        data[key] = max(16, min(256, int(float(value))))
    elif key == "viz_sensibilite":
        data[key] = round(max(0.05, min(4.0, float(value))), 2)
    elif key == "viz_lissage":
        data[key] = round(max(0.0, min(0.99, float(value))), 2)
    elif key == "viz_epaisseur":
        data[key] = round(max(0.5, min(4.0, float(value))), 1)
    elif key == "viz_couleur" and str(value) in VIZ_COULEURS:
        data[key] = str(value)
    elif key == "bar_gaps_transparent":
        # Espaces entre les îlots de la barre du haut : booléen, relu par
        # Theme.qml (barGapsTransparent), qui découpe le fond en trois zones.
        data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "cheatsheet_opacity":
        data[key] = round(max(0.2, min(1.0, float(value))), 2)
    elif key == "bar_height":
        data[key] = max(28, min(60, int(float(value))))
    elif key == "resize_step":
        data[key] = max(1, min(200, int(float(value))))
        save_json(STYLE_FILE, data)
        # binds.lua lit resize_step au chargement : il faut recharger Hyprland
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return True
    elif key in ("bar_bottom", "bar_left", "bar_right"):
        # Barres supplémentaires : un booléen, écrit tel quel dans style_vars.
        data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "show_config_button":
        if isinstance(value, bool):
            data[key] = value
        else:
            data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "matugen_scheme" and str(value) in MATUGEN_SCHEMES:
        data["matugen_scheme"] = str(value)
    elif key == "matugen_contrast":
        data["matugen_contrast"] = max(-1.0, min(1.0, float(value)))
    elif key == "launch_history":
        data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "blur_enabled":
        data[key] = str(value).lower() in ("true", "1", "yes")
    elif key == "blur_size":
        data[key] = max(1, min(20, int(float(value))))
    elif key == "blur_passes":
        data[key] = max(1, min(8, int(float(value))))
    elif key == "blur_vibrancy":
        data[key] = max(0.0, min(1.0, float(value)))
    elif key in SHELL_BLUR_KEYS:
        if key == "shell_blur_alpha":
            data[key] = round(max(0.0, min(1.0, float(value))), 2)
        else:
            data[key] = str(value).lower() in ("true", "1", "yes")
        shell_blur_changed = True
    elif key == "launcher_position" and str(value) in LAUNCHER_POSITIONS:
        data[key] = str(value)
    elif key == "active_theme" and value in data.get("palette", {}):
        data["active_theme"] = value
    elif key in COLOR_KEYS:
        active = data.get("active_theme", "dynamic")
        val_str = str(value).strip()
        if not val_str.startswith("#"):
            val_str = "#" + val_str
        if re.match(r"^#[0-9a-fA-F]{6}$", val_str):
            data.setdefault("palette", {}).setdefault(active, {})[key] = val_str.lower()
    save_json(STYLE_FILE, data)
    if shell_blur_changed:
        apply_shell_blur(data)
    if os.path.exists(ROFI_GEN_SCRIPT):
        subprocess.run(["bash", ROFI_GEN_SCRIPT], check=False)
    return True


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4B: NOTIFICATION TOAST PREFERENCES
# ─────────────────────────────────────────────────────────────────────────────
# Applications dont les notifications vont directement au centre, sans toast.
# La liste vit dans style_vars.json pour survivre aux redéploiements.
QUIET_NOTIF_KEY = "quiet_notif_apps"


def get_quiet_notif_apps():
    data = load_json(STYLE_FILE)
    apps = data.get(QUIET_NOTIF_KEY)
    return [a for a in apps if isinstance(a, str)] if isinstance(apps, list) else []


def set_quiet_notif_app(name, quiet):
    """Add or remove an application from the silent list. Returns the new list."""
    data = load_json(STYLE_FILE)
    apps = get_quiet_notif_apps()
    name = str(name).strip()
    if not name:
        return apps
    if quiet and name not in apps:
        apps.append(name)
    elif not quiet and name in apps:
        apps.remove(name)
    data[QUIET_NOTIF_KEY] = apps
    save_json(STYLE_FILE, data)
    return apps


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: SYSTEM & DISPLAY MANAGEMENT (Monitors, Resolutions, Refresh Rates)
# ─────────────────────────────────────────────────────────────────────────────

def filter_clean_modes(avail):
    """Extract, deduplicate and cleanly sort monitor modes (including 1080p, 1440p, 4k)."""
    parsed = []
    seen = set()
    for m in avail or []:
        match = re.match(r"^(\d+)x(\d+)(?:@([\d.]+)(?:Hz)?)?$", str(m))
        if not match:
            continue
        w, h = int(match.group(1)), int(match.group(2))
        hz = float(match.group(3)) if match.group(3) else 60.0
        round_hz = int(round(hz))
        # Keep >= 720p modes (filter ancient/irrelevant sub-HD resolutions)
        if h < 720:
            continue
        key = (w, h, round_hz)
        if key not in seen:
            seen.add(key)
            parsed.append((w, h, round_hz))
    # Sort descending by width, height, and refresh rate
    parsed.sort(key=lambda x: (x[0], x[1], x[2]), reverse=True)
    modes = [f"{w}x{h}@{hz}" for w, h, hz in parsed]
    if "preferred" not in modes:
        modes.insert(0, "preferred")
    return modes


def get_primary_monitor(hostname=None):
    """Detect primary monitor name from style_vars.json or hardware-<host>.lua."""
    style_data = load_json(STYLE_FILE)
    if style_data.get("primary_monitor"):
        return style_data["primary_monitor"]

    if not hostname:
        hostname = get_hostname()
    hw_path = os.path.join(HYPR_DIR, f"hardware-{hostname}.lua")
    if os.path.exists(hw_path):
        try:
            with open(hw_path, "r") as f:
                content = f.read()
            m = re.search(r'hl\.workspace_rule\(\{[^{}]*workspace\s*=\s*["\']1["\'][^{}]*monitor\s*=\s*["\']([^"\']+)["\']', content)
            if m:
                return m.group(1)
        except Exception:
            pass
    return "eDP-1" if is_laptop_system() else "HDMI-A-1"


def get_monitors_info():
    """Return active Hyprland monitors, available modes, hardware profile, and timezone/NTP info."""
    monitors = []
    host = get_hostname()
    prim = get_primary_monitor(host)
    out = run_cmd(["hyprctl", "monitors", "-j"])
    if out:
        try:
            raw = json.loads(out)
            for m in raw:
                avail = m.get("availableModes") or []
                clean_modes = filter_clean_modes(avail)
                name = m.get("name", "")
                monitors.append(
                    {
                        "name": name,
                        "description": m.get("description", ""),
                        "width": m.get("width", 1920),
                        "height": m.get("height", 1080),
                        "refreshRate": int(round(float(m.get("refreshRate", 60)))),
                        "x": m.get("x", 0),
                        "y": m.get("y", 0),
                        "scale": m.get("scale", 1.0),
                        "transform": m.get("transform", 0),
                        "availableModes": clean_modes,
                        "is_primary": (name == prim),
                    }
                )
        except Exception:
            pass

    tz = run_cmd(["timedatectl", "show", "-p", "Timezone", "--value"]) or "Europe/Paris"
    ntp = run_cmd(["timedatectl", "show", "-p", "NTPSynchronized", "--value"]) == "yes"
    return {
        "hostname": host,
        "is_laptop": is_laptop_system(),
        "monitors": monitors,
        "primary": prim,
        "timezone": tz,
        "ntp": ntp,
    }


def set_primary_monitor(output_name):
    """Set output_name as primary monitor: bind workspaces 1..5 and persist in hardware-<host>.lua + style_vars.json."""
    if not monitor_utils.OUTPUT_RE.match(str(output_name)):
        return False

    # 1. Update style_vars.json
    style_data = load_json(STYLE_FILE)
    style_data["primary_monitor"] = output_name
    save_json(STYLE_FILE, style_data)

    # 2. Update hardware-<host>.lua
    host = get_hostname()
    hw_path = os.path.join(HYPR_DIR, f"hardware-{host}.lua")
    if not os.path.exists(hw_path):
        hw_path = os.path.join(HYPR_DIR, "hardware-" + _distro_fichier() + ".lua")

    ws_names = {1: "一", 2: "二", 3: "三", 4: "四", 5: "五"}
    new_rules = [f"-- Workspaces assignés à l'écran principal ({output_name})"]
    for ws, kanji in ws_names.items():
        dflt = ", default = true" if ws == 1 else ""
        new_rules.append(
            f'hl.workspace_rule({{ workspace = "{ws}", monitor = "{output_name}"{dflt}, persistent = true, default_name = "{kanji}" }})'
        )
    new_block = "\n".join(new_rules)

    if os.path.exists(hw_path):
        try:
            with open(hw_path, "r") as f:
                txt = f.read()
            rule_re = re.compile(r'-- Workspaces assignés à l\'écran principal[^\n]*\n(?:hl\.workspace_rule\([^\n]+\)\n?)+')
            if rule_re.search(txt):
                txt = rule_re.sub(new_block, txt)
            else:
                indiv_re = re.compile(r'(?:hl\.workspace_rule\(\{[^{}]*workspace\s*=\s*["\'][1-5]["\'][^{}]*\}\)\n?)+')
                if indiv_re.search(txt):
                    txt = indiv_re.sub(new_block + "\n", txt)
                else:
                    txt = txt.rstrip() + "\n\n" + new_block + "\n"
            with open(hw_path, "w") as f:
                f.write(txt)
        except Exception:
            pass

    # 3. Reload Hyprland and focus the new primary monitor using Hyprland 0.57+ Lua dispatchers
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["hyprctl", "eval", f'hl.dsp.focus({{ monitor = "{output_name}" }})'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["hyprctl", "eval", 'hl.dsp.focus({ workspace = 1 })'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return True


def set_monitor_profile(profile):
    """
    Apply multi-monitor / TV presets for Lenovo Yoga (eDP-1) + External TV (DP-1):
      - 'dual'   : TV (DP-1 1920x1080@60 at 0x0) + Laptop (eDP-1 preferred at 1920x0)
      - 'tv'     : TV only (disable eDP-1, enable DP-1 at 0x0)
      - 'laptop' : Laptop only (disable DP-1, enable eDP-1 preferred at 0x0)
    """
    all_mons = monitor_utils.hyprctl_json("monitors", "all") or []
    ext_mon = None
    for m in all_mons:
        name = m.get("name", "")
        if name and not name.startswith("eDP"):
            ext_mon = name
            break
    if not ext_mon:
        ext_mon = "DP-1"

    if profile == "dual":
        cmds = [
            f'hl.monitor({{ output = "{ext_mon}", disabled = false, mode = "1920x1080@60", position = "0x0", scale = 1, bitdepth = 10 }})',
            'hl.monitor({ output = "eDP-1", disabled = false, mode = "preferred", position = "1920x0", scale = 1, transform = 0 })',
            f'hl.dsp.focus({{ monitor = "{ext_mon}" }})',
            'hl.dsp.focus({ workspace = 1 })',
        ]
        target_prim = ext_mon
    elif profile == "tv":
        cmds = [
            f'hl.monitor({{ output = "{ext_mon}", disabled = false, mode = "1920x1080@60", position = "0x0", scale = 1, bitdepth = 10 }})',
            'hl.monitor({ output = "eDP-1", disabled = true })',
            f'hl.dsp.focus({{ monitor = "{ext_mon}" }})',
            'hl.dsp.focus({ workspace = 1 })',
        ]
        target_prim = ext_mon
    elif profile == "laptop":
        cmds = [
            f'hl.monitor({{ output = "{ext_mon}", disabled = true }})',
            'hl.monitor({ output = "eDP-1", disabled = false, mode = "preferred", position = "0x0", scale = 1, transform = 0 })',
            'hl.dsp.focus({ monitor = "eDP-1" })',
            'hl.dsp.focus({ workspace = 1 })',
        ]
        target_prim = "eDP-1"
    else:
        return False

    for c in cmds:
        subprocess.run(["hyprctl", "eval", c], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

    try:
        style_data = load_json(STYLE_FILE)
        if style_data.get("primary_monitor") != target_prim:
            style_data["primary_monitor"] = target_prim
            save_json(STYLE_FILE, style_data)
    except Exception:
        pass

    return True


def _update_monitor_block(txt, output_name, mode_str, scale):
    """Update `mode` and `scale` independently inside the hl.monitor({...}) block of `output_name`."""
    block_re = re.compile(
        rf'hl\.monitor\(\{{[^{{}}]*?output\s*=\s*"{re.escape(output_name)}"[^{{}}]*?\}}\)'
    )

    def fix(m):
        block = m.group(0)
        if re.search(r'\bmode\s*=\s*"[^"]*"', block):
            block = re.sub(r'(\bmode\s*=\s*)"[^"]*"', lambda x: f'{x.group(1)}"{mode_str}"', block, count=1)
        if re.search(r'\bscale\s*=\s*[0-9.]+', block):
            block = re.sub(r'(\bscale\s*=\s*)[0-9.]+', lambda x: f"{x.group(1)}{scale}", block, count=1)
        else:
            block = re.sub(r'\s*\}\)$', f", scale = {scale} }})", block)
        return block

    return block_re.sub(fix, txt)


def set_monitor_mode(output_name, mode_str, scale="1"):
    """Set resolution/refresh rate for a specific output (e.g. HDMI-A-1 or DP-1) and persist in hardware-<host>.lua.

    The current position of the monitor is preserved (never reset to 0x0).
    """
    scale = str(scale)
    if not monitor_utils.apply_monitor(output_name, mode=mode_str, scale=scale):
        return False

    host = get_hostname()
    hw_path = os.path.join(HYPR_DIR, f"hardware-{host}.lua")
    if not os.path.exists(hw_path):
        hw_path = os.path.join(HYPR_DIR, "hardware-" + _distro_fichier() + ".lua")

    if os.path.exists(hw_path):
        try:
            with open(hw_path, "r") as f:
                txt = f.read()
            txt = _update_monitor_block(txt, output_name, mode_str, scale)
            with open(hw_path, "w") as f:
                f.write(txt)
        except Exception:
            pass
    return True


def set_screen_rotation(transform_id):
    """Rotate internal screen eDP-1 (0=Normal, 1=90°, 2=180°, 3=270°). Shares its logic with the tablet daemon."""
    tablet_mode_daemon.set_mode(None, int(transform_id) % 4)
    return True


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6: KEYBINDINGS MANAGEMENT (binds.lua)
# ─────────────────────────────────────────────────────────────────────────────

def get_binds_list():
    """Parse binds.lua and return a list of shortcut dicts.

    Chaque entrée porte `mod`, `key`, `dispatcher`, `target`, plus `description`
    (option `{ description = "…" }` du bind, vide si absente) et `category`
    (dernier commentaire de section). L'écran des raccourcis ne montre que les
    binds qui ont une description : c'est la liste « des plus utiles », entretenue
    dans binds.lua et jamais dupliquée ailleurs.
    """
    path = os.path.join(HYPR_DIR, "binds.lua")
    binds = []
    if not os.path.exists(path):
        return binds

    category = ""
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                raw = line.rstrip("\n")
                stripped = raw.strip()
                if stripped.startswith("--:"):
                    # Convention explicite : « --: Catégorie » est un en-tête de
                    # section, tout autre commentaire est de la prose et ne doit
                    # pas changer la catégorie du prochain bind.
                    category = stripped[3:].strip()
                    continue
                if stripped.startswith("--"):
                    continue
                if not stripped.startswith("hl.bind("):
                    continue
                key_m = re.search(r'"\s*\+\s*([^"]+)"', stripped)
                key = key_m.group(1).strip() if key_m else ""
                if not key:
                    continue
                dsp_m = re.search(r"hl\.dsp\.([a-zA-Z0-9_.]+)\(", stripped)
                desc_m = re.search(r'description\s*=\s*"([^"]*)"', stripped)
                arg_m = re.search(r"hl\.dsp\.[a-zA-Z0-9_.]+\((.*)\)", stripped)
                target = (arg_m.group(1).strip().strip('"').strip("'") if arg_m else "")
                target = re.split(r",\s*\{", target)[0].strip()
                binds.append({
                    "mod": "SUPER",
                    "key": key,
                    "dispatcher": dsp_m.group(1) if dsp_m else "",
                    "target": target or "",
                    "description": desc_m.group(1) if desc_m else "",
                    # Un commentaire `-- essentiel` en fin de ligne marque les
                    # raccourcis qui restent affichés quand la cheatsheet est en
                    # mode court. Commentaire Lua : Hyprland l'ignore, aucun
                    # risque qu'il refuse l'option.
                    "essentiel": bool(re.search(r"--\s*essentiel", stripped)),
                    "category": category,
                })
    except Exception:
        pass
    return binds


def set_keybind(key_combo, command_or_var):
    """Update or add a SUPER + <key_combo> shortcut in binds.lua."""
    path = os.path.join(HYPR_DIR, "binds.lua")
    key_clean = key_combo.strip()
    cmd_clean = command_or_var.strip()
    if not key_clean or not cmd_clean:
        return False
    if not KEY_COMBO_RE.match(key_clean):
        print(f"Invalid key combo: {key_clean!r}", file=sys.stderr)
        return False

    known_vars = {"terminal", "music_player", "browser1", "browser2", "file_explorer", "editor"}
    app_data = load_json(APP_VARS_FILE)
    for k in app_data:
        ident = lua_ident(k)
        if ident:
            known_vars.add(ident)

    if cmd_clean in known_vars:
        rhs = f"hl.dsp.exec_cmd({cmd_clean})"
    else:
        rhs = f"hl.dsp.exec_cmd({lua_str(cmd_clean)})"

    new_line = f'hl.bind(mainMod .. " + {key_clean}", {rhs})\n'
    lhs_prefix = f'hl.bind(mainMod .. " + {key_clean}"'

    try:
        lines = []
        if os.path.exists(path):
            with open(path, "r") as f:
                lines = f.readlines()
        updated = False
        for i, line in enumerate(lines):
            if lhs_prefix in line:
                lines[i] = new_line
                updated = True
                break
        if not updated:
            lines.append(new_line)
        with open(path, "w") as f:
            f.writelines(lines)
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return True
    except Exception as e:
        print(f"Error updating bind: {e}")
        return False


def remove_keybind(key_combo):
    """Remove a SUPER + <key_combo> shortcut from binds.lua."""
    if not KEY_COMBO_RE.match(key_combo.strip()):
        return False
    path = os.path.join(HYPR_DIR, "binds.lua")
    lhs_prefix = f'hl.bind(mainMod .. " + {key_combo.strip()}"'
    if not os.path.exists(path):
        return False
    try:
        with open(path, "r") as f:
            lines = f.readlines()
        new_lines = [l for l in lines if lhs_prefix not in l]
        with open(path, "w") as f:
            f.writelines(new_lines)
        subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return True
    except Exception:
        return False


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7: DYNAMIC VARIABLES & APPLICATIONS (app_vars.json <-> programs.lua)
# ─────────────────────────────────────────────────────────────────────────────

def set_app_var(alias, command):
    if not lua_ident(alias) or not command.strip():
        print(f"Invalid app alias or empty command: {alias!r}", file=sys.stderr)
        return False
    data = load_json(APP_VARS_FILE)
    data[alias.strip()] = command.strip()
    save_json(APP_VARS_FILE, data)
    sync_programs_lua(data)
    return True


SECRETS_FILE = os.path.join(BASE_DIR, "secrets.json")
HOMELAB_FILE = os.path.join(BASE_DIR, "homelab.json")
# Les fichiers de tâches suivis par l'applet : même fichier que celui que lit
# `todo_applet.py`, pour qu'il n'y en ait qu'un.
TODO_FILE = os.path.join(BASE_DIR, "todo.json")
TODO_FOCUS = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                          "quickshell", "todo-focus.json")


def lire_secrets():
    try:
        with open(SECRETS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def resume_secrets():
    """Ce que le panneau peut afficher : présence et derniers caractères, jamais la clé."""
    out = {}
    for section, valeur in lire_secrets().items():
        if not isinstance(valeur, dict):
            continue
        for nom, cle in valeur.items():
            if not isinstance(cle, str) or not cle.strip():
                continue
            out[f"{section}.{nom}"] = {"present": True, "tail": cle.strip()[-4:]}
    return out


def set_secret(section, nom, valeur):
    """Range une clé dans secrets.json (600), sans jamais l'écrire ailleurs."""
    section, nom = str(section).strip(), str(nom).strip()
    valeur = str(valeur or "").strip()
    if not section or not nom:
        return False
    if not valeur:
        return False
    data = lire_secrets()
    entree = data.get(section)
    if not isinstance(entree, dict):
        entree = {}
    entree[nom] = valeur
    data[section] = entree
    with open(SECRETS_FILE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=4, ensure_ascii=False)
        fh.write("\n")
    try:
        os.chmod(SECRETS_FILE, 0o600)
    except OSError:
        pass
    return True


def lire_homelab():
    """Ce que le panneau doit montrer du homelab : URL, jeton (sans le secret).

    Le secret du jeton n'est jamais rendu — seulement ses quatre derniers
    caractères, comme pour les clés d'API.
    """
    try:
        with open(HOMELAB_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    if not isinstance(d, dict):
        d = {}
    pve_brut = d.get("proxmox")
    pve = dict(pve_brut) if isinstance(pve_brut, dict) else {}
    sec = lire_secrets().get("proxmox") or {}
    secret = str(sec.get("token_secret") or "")
    return {
        "proxmox_url": str(pve.get("url") or ""),
        "proxmox_token_id": str(pve.get("token_id") or sec.get("token_id") or ""),
        "proxmox_verifier_tls": bool(pve.get("verifier_tls", False)),
        "jeton_present": bool(secret),
        "jeton_tail": secret[-4:] if secret else "",
        "hotes": d.get("hotes") or [],
    }


def lire_todo():
    """Les fichiers suivis, tels que l'applet les lit (`core/todo.json`)."""
    try:
        with open(TODO_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        liste = d.get("fichiers") if isinstance(d, dict) else d
    except (OSError, ValueError):
        liste = []
    sortie = []
    for entree in liste or []:
        if isinstance(entree, str):
            entree = {"chemin": entree}
        chemin = str((entree or {}).get("chemin") or "").strip()
        if not chemin:
            continue
        sortie.append({"chemin": chemin,
                       "nom": str(entree.get("nom") or os.path.basename(chemin))})
    return sortie


def ecrire_todo(liste):
    tmp = TODO_FILE + ".tmp"
    os.makedirs(os.path.dirname(TODO_FILE), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"fichiers": liste}, f, ensure_ascii=False, indent=4)
    os.replace(tmp, TODO_FILE)
    return True


def todo_add(nom, chemin):
    """Ajoute un fichier suivi. Le chemin est gardé tel qu'il est saisi (`~` reste
    `~`, c'est l'applet qui l'étend) ; l'existence est vérifiée tout de suite, pour
    qu'une faute de frappe se voie au moment où on la tape."""
    chemin = str(chemin or "").strip()
    if not chemin:
        return False
    reel = os.path.expanduser(os.path.expandvars(chemin))
    if not os.path.isfile(reel):
        return False
    libelle = str(nom or "").strip() or os.path.basename(reel)
    liste = lire_todo()
    for entree in liste:
        if entree["chemin"] == chemin or entree["nom"] == libelle:
            entree["chemin"] = chemin
            entree["nom"] = libelle
            return ecrire_todo(liste)
    liste.append({"chemin": chemin, "nom": libelle})
    return ecrire_todo(liste)


def todo_del(nom):
    liste = [e for e in lire_todo() if e["nom"] != str(nom)]
    return ecrire_todo(liste)


def todo_focus(nom):
    """Le fichier que l'applet montre. Il vit dans le cache : c'est une
    préférence de machine, pas une donnée du dépôt."""
    os.makedirs(os.path.dirname(TODO_FOCUS), exist_ok=True)
    tmp = TODO_FOCUS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"fichier": str(nom or "")}, f, ensure_ascii=False)
    os.replace(tmp, TODO_FOCUS)
    return True


def lire_todo_focus():
    try:
        with open(TODO_FOCUS, "r", encoding="utf-8") as f:
            memo = str(json.load(f).get("fichier") or "")
    except (OSError, ValueError):
        memo = ""
    noms = [e["nom"] for e in lire_todo()]
    if memo in noms:
        return memo
    return noms[0] if noms else ""


def homelab_set(cle, valeur):
    """Range une valeur non secrète dans homelab.json (écriture atomique)."""
    try:
        with open(HOMELAB_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    if not isinstance(d, dict):
        d = {}
    pve_brut = d.get("proxmox")
    pve = dict(pve_brut) if isinstance(pve_brut, dict) else {}
    pve.setdefault("verifier_tls", False)

    if cle == "proxmox_url":
        pve["url"] = str(valeur).strip()
    elif cle == "proxmox_token_id":
        pve["token_id"] = str(valeur).strip()
    elif cle == "proxmox_verifier_tls":
        pve["verifier_tls"] = str(valeur).strip().lower() in ("1", "true", "oui")
    else:
        return False

    d["proxmox"] = pve
    tmp = HOMELAB_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=4)
    os.replace(tmp, HOMELAB_FILE)
    return True


def set_secret_from_file(chemin):
    """La clé arrive par un fichier (pas par la ligne de commande).

    Un argument de commande est visible dans `/proc/<pid>/cmdline` le temps de
    l'exécution ; le fichier de passage, lui, vit sous $XDG_RUNTIME_DIR et
    disparaît dès lecture.
    """
    try:
        with open(chemin, encoding="utf-8") as fh:
            charge = json.load(fh)
    except Exception as exc:
        return {"ok": False, "erreur": f"fichier illisible : {exc}"}
    finally:
        try:
            os.unlink(chemin)
        except OSError:
            pass
    section = str(charge.get("section") or "").strip()
    nom = str(charge.get("nom") or "api_key").strip()
    valeur = str(charge.get("valeur") or "").strip()
    if not section or not valeur:
        return {"ok": False, "erreur": "section ou valeur vide"}
    ok = set_secret(section, nom, valeur)
    return {"ok": ok, "section": section, "nom": nom, "tail": valeur[-4:] if ok else ""}


def load_notif_targets():
    try:
        with open(NOTIF_TARGETS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError("racine non-objet")
    except Exception:
        data = {}
    data.setdefault("apps", {})
    data.setdefault("types", {"video": "Video", "image": "Images",
                              "folder": "Files", "text": "Editor"})
    data.setdefault("url", "Browser")
    data.setdefault("terminal_alias", "Terminal")
    return data


def save_notif_targets(data):
    with open(NOTIF_TARGETS_FILE, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=4, ensure_ascii=False)
        fh.write("\n")


def set_notif_app(key, command):
    """Règle par application. Le drapeau « terminal » de l'entrée existante est
    conservé : éditer la commande d'Arch-Update ne doit pas la sortir du terminal."""
    key, command = key.strip(), command.strip()
    if not key or not command:
        return False
    data = load_notif_targets()
    previous = data["apps"].get(key)
    entry = {"run": command}
    if isinstance(previous, dict) and previous.get("terminal"):
        entry["terminal"] = True
    data["apps"][key] = entry
    save_notif_targets(data)
    return True


def remove_notif_app(key):
    data = load_notif_targets()
    if key not in data["apps"]:
        return False
    del data["apps"][key]
    save_notif_targets(data)
    return True


def set_notif_type(nature, alias):
    nature, alias = nature.strip(), alias.strip()
    if not nature or not alias:
        return False
    data = load_notif_targets()
    data["types"][nature] = alias
    save_notif_targets(data)
    return True


def set_notif_url(alias):
    alias = alias.strip()
    if not alias:
        return False
    data = load_notif_targets()
    data["url"] = alias
    save_notif_targets(data)
    return True


def remove_app_var(alias):
    data = load_json(APP_VARS_FILE)
    if alias in data:
        del data[alias]
        save_json(APP_VARS_FILE, data)
        sync_programs_lua(data)
    return True


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8: AUTOSTART MANAGEMENT (autostart.json <-> autostart_cmds.txt)
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_AUTOSTART = [
    # `-n` (--no-duplicate) : une deuxième instance du même config sort
    # immédiatement au lieu d'empiler une barre et de reprendre le service de
    # notifications. Le pgrep couvre déjà le relogin ; -n couvre les lancements
    # manuels et les lancements concurrents.
    # Gardes en chemin absolu (/usr/bin/pgrep) : dans l'environnement d'autostart
    # un PATH minimal fait échouer la garde, qui échoue alors « ouverte » et
    # laisse démarrer une seconde instance. Un démon doit être lancé par une
    # unité systemd (hypridle) quand elle existe.
    {"name": "Quickshell (barre)", "cmd": "sh -c '/usr/bin/pgrep -x quickshell >/dev/null || exec quickshell -n' &", "enabled": True},
    {"name": "Hypridle (inactivité)", "cmd": "systemctl --user start hypridle", "enabled": True},
    {"name": "awww-daemon (wallpaper, si Noctalia absent)", "cmd": "sh -c '/usr/bin/pgrep -x awww-daemon >/dev/null || exec awww-daemon' &", "enabled": True},
    # Un seul superviseur pour les deux veilleurs cliphist : il se garde par un
    # pidfile, là où `pgrep -f "wl-paste --watch"` se trouvait lui-même dans son
    # propre `sh -c` et ne démarrait jamais rien.
    # La garde est dans le script (pidfile) : un `pgrep -f` sur le nom du script se
    # trouverait lui-même dans le `sh -c` qui le porte.
    {"name": "Presse-papiers (veilleurs cliphist)", "cmd": "sh -c '$HOME/.config/quickshell/core/cliphist_watch.sh' &", "enabled": True},
    {"name": "Agent Polkit", "cmd": "sh -c '/usr/bin/pgrep -x hyprpolkitagent >/dev/null && exit 0; for agent in /usr/lib/hyprpolkitagent/hyprpolkitagent /usr/libexec/hyprpolkitagent /usr/lib/lxqt-policykit-agent /usr/libexec/lxqt-policykit-agent /usr/lib/polkit-kde-authentication-agent-1; do if [ -x \"$agent\" ]; then exec \"$agent\"; fi; done' &", "enabled": True},
]


def get_autostart():
    if not os.path.exists(AUTOSTART_FILE):
        return DEFAULT_AUTOSTART
    data = load_json(AUTOSTART_FILE)
    return data if isinstance(data, list) else DEFAULT_AUTOSTART


def set_autostart(name, enabled=None, cmd=None):
    entries = get_autostart()
    changed = False
    for e in entries:
        if e.get("name") == name:
            if enabled is not None:
                e["enabled"] = bool(enabled)
                changed = True
            if cmd is not None and cmd.strip():
                e["cmd"] = cmd.strip()
                changed = True
    if not changed:
        return False
    save_json(AUTOSTART_FILE, entries)
    return sync_autostart_lua(entries)


def add_autostart(name, cmd):
    if not name.strip() or not cmd.strip():
        return False
    entries = get_autostart()
    for e in entries:
        if e.get("name") == name.strip():
            return False
    entries.append({"name": name.strip(), "cmd": cmd.strip(), "enabled": True})
    save_json(AUTOSTART_FILE, entries)
    return sync_autostart_lua(entries)


def remove_autostart(name):
    entries = get_autostart()
    kept = [e for e in entries if e.get("name") != name]
    if len(kept) == len(entries):
        return False
    save_json(AUTOSTART_FILE, kept)
    return sync_autostart_lua(kept)


def sync_autostart_lua(entries):
    """Régénère ~/.config/hypr/autostart_cmds.txt (une commande par ligne).
    Lu ligne à ligne par exec.lua dans hl.on("hyprland.start").
    Les programmes désactivés sont préfixés par '#' pour garder la trace."""
    out_path = os.path.join(HYPR_DIR, "autostart_cmds.txt")
    lines = ["# Généré par core/config_manager.py — ne pas éditer à la main.",
             "# Source de vérité : core/autostart.json (modifiable depuis le panneau)."]
    for e in entries:
        line = e["cmd"].strip()
        if line:
            lines.append(line if e.get("enabled", True) else "# " + line)
    try:
        os.makedirs(HYPR_DIR, exist_ok=True)
        with open(out_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        return True
    except Exception as ex:
        print(f"Error writing {out_path}: {ex}", file=sys.stderr)
        return False


def sync_programs_lua(app_data):
    """Synchronize core/app_vars.json with Hyprland's programs.lua."""
    programs_path = os.path.join(HYPR_DIR, "programs.lua")
    mapping = {
        "terminal": app_data.get("Terminal", "kitty"),
        "music_player": app_data.get("Music", "strawberry"),
        "browser1": app_data.get("Browser", "firefox"),
        "browser2": app_data.get("Browser2", "zen-browser"),
        "file_explorer": app_data.get("Files", "thunar"),
        "editor": app_data.get("Editor", "code"),
    }
    lines = ["-- ~/.config/hypr/programs.lua\n-- Generated from core/app_vars.json by config_manager.py\n"]
    for k, v in mapping.items():
        lines.append(f"{k} = {lua_str(v)}\n")
    for alias, cmd in app_data.items():
        safe_key = lua_ident(alias)
        if safe_key and safe_key not in mapping:
            lines.append(f"{safe_key} = {lua_str(cmd)}\n")
    try:
        with open(programs_path, "w") as f:
            f.writelines(lines)
    except Exception as e:
        print(f"Error syncing programs.lua: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9: FULL STATE AGGREGATION & CLI DISPATCHER
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8B: WIDGETS DE BUREAU (core/widgets.json)
# ─────────────────────────────────────────────────────────────────────────────
# Fichier d'état préservé au déploiement (PRESERVE_CORE). Chaque entrée devient
# une surface layer `shell-widget` en couche Bottom, une par widget.
# Un type par widget disponible dans widgets/ — le panneau coche, `widget_add`
# valide. Ajouter un fournisseur LLM passe par core/llm_providers.json.
WIDGET_TYPES = ("horloge", "date", "meteo", "combo", "musique", "systeme",
                "reseau", "disques", "homelab", "hermes", "usb", "todo",
                "presse_papiers",
                "deepseek", "ollama", "antigravity", "comptes")
WIDGET_DEFAULT_OPACITY = 0.35


def load_widgets():
    data = load_json(WIDGETS_FILE)
    items = data.get("widgets") if isinstance(data, dict) else None
    if not isinstance(items, list):
        return []
    return [w for w in items if isinstance(w, dict) and w.get("type")]


def save_widgets(items):
    save_json(WIDGETS_FILE, {"widgets": items})
    # Le flou d'un widget est une règle de couche (par namespace) : la réécrire et
    # recharger Hyprland à chaque changement, sinon le réglage ne prend pas avant
    # le prochain démarrage.
    try:
        apply_shell_blur()
    except Exception as e:
        print(f"widgets: application du flou impossible: {e}", file=sys.stderr)
    return items


def widget_add(wtype, workspace=1, x=120, y=160):
    wtype = str(wtype)
    if wtype not in WIDGET_TYPES:
        raise SystemExit(f"type de widget inconnu: {wtype} (attendu: {', '.join(WIDGET_TYPES)})")
    items = load_widgets()
    # Une seule instance par nature : le panneau coche, il ne compte pas. Un
    # double clic sur la case ne doit pas créer deux horloges.
    for w in items:
        if str(w.get("type")) == wtype:
            return str(w.get("id"))
    wid = f"{wtype}-{len(items) + 1}"
    while any(w.get("id") == wid for w in items):
        wid += "x"
    items.append({
        "id": wid, "type": wtype, "workspace": int(workspace),
        "x": int(x), "y": int(y), "enabled": True,
        "opacity": WIDGET_DEFAULT_OPACITY, "blur": True, "border": True,
        "options": {},
    })
    save_widgets(items)
    return wid


def _widget_update(wid, mutate):
    items = load_widgets()
    for w in items:
        if w.get("id") == wid:
            mutate(w)
            save_widgets(items)
            return w
    raise SystemExit(f"widget inconnu: {wid}")


def widget_set(wid, key, value):
    def mutate(w):
        if key in ("x", "y", "workspace"):
            w[key] = int(float(value))
            # Le panneau ne règle qu'un bureau à la fois : la liste repasse à un
            # seul élément, sinon une ancienne sélection multiple continuerait de
            # gagner sur le choix qui vient d'être fait.
            if key == "workspace":
                w["workspaces"] = [w[key]]
        elif key in ("enabled", "blur", "border"):
            w[key] = str(value).lower() in ("true", "1", "yes")
        elif key == "opacity":
            w[key] = round(max(0.0, min(1.0, float(value))), 2)
        elif key == "type":
            if str(value) not in WIDGET_TYPES:
                raise SystemExit(f"type de widget inconnu: {value}")
            w[key] = str(value)
        elif key == "id":
            w[key] = str(value)
        else:
            # Tout le reste va dans options (secondes, ville…).
            w.setdefault("options", {})[key] = value
    return _widget_update(wid, mutate)


def widget_workspaces(wid, spec):
    """Bureaux d'un widget : « 0 » ou vide = tous, sinon « 1,3 » = ces bureaux.

    Deux champs pour une idée : `workspaces` est la vérité, `workspace` reste
    écrit pour les lecteurs historiques (et pour le panneau, qui ne montre qu'un
    bureau). 0 dans la liste veut dire « tous les bureaux ».
    """
    def mutate(w):
        morceaux = str(spec or "").replace(";", ",").split(",")
        chiffres = [int(x) for x in morceaux if str(x).strip().isdigit()]
        if not chiffres or 0 in chiffres:
            w["workspaces"] = [0]
            w["workspace"] = 0
        else:
            vus = sorted(set(chiffres))
            w["workspaces"] = vus
            w["workspace"] = vus[0]
    return _widget_update(wid, mutate)


def widget_move(wid, x, y):
    def mutate(w):
        w["x"], w["y"] = int(float(x)), int(float(y))
    return _widget_update(wid, mutate)


def widget_remove(wid):
    items = [w for w in load_widgets() if w.get("id") != wid]
    save_widgets(items)
    return len(items)


def get_full_config_state():
    style_data = load_json(STYLE_FILE)
    kb = get_kb_layout()
    return {
        "hostname": get_hostname(),
        "is_laptop": is_laptop_system(),
        "kb_layout": kb,
        "workspace_keys": WORKSPACE_KEYS_BY_LAYOUT.get(kb, WORKSPACE_KEYS_BY_LAYOUT["us"]),
        "first_run_completed": bool(style_data.get("first_run_completed", False)),
        "show_config_button": bool(style_data.get("show_config_button", True)),
        "bar_height": int(style_data.get("bar_height", 40)),
        "launcher_position": style_data.get("launcher_position", "bas-centre"),
        "widgets": load_widgets(),
        "global_radius": int(style_data.get("global_radius", 2)),
        "global_opacity": float(style_data.get("global_opacity", 0.7)),
        "shell_opacity": float(style_data.get("shell_opacity", 0.7)),
        "cheatsheet_opacity": float(style_data.get("cheatsheet_opacity", 0.88)),
        "bar_border": bool(style_data.get("bar_border", True)),
        "bar_gaps_transparent": bool(style_data.get("bar_gaps_transparent", False)),
        "viz_fps": int(style_data.get("viz_fps", 30)),
        "viz_cols": int(style_data.get("viz_cols", 96)),
        "viz_sensibilite": float(style_data.get("viz_sensibilite", 1.0)),
        "viz_lissage": float(style_data.get("viz_lissage", 0.2)),
        "viz_epaisseur": float(style_data.get("viz_epaisseur", 1.4)),
        "viz_couleur": str(style_data.get("viz_couleur", "accent")),
        "hypr_rounding": get_hypr_rounding(),
        "hypr_rounding_power": get_hypr_rounding_power(),
        "api_keys": resume_secrets(),
        # Liste publique des fournisseurs LLM (sans secret) : le panneau dessine
        # une ligne par entrée, dans l'ordre du fichier.
        "llm_providers": list(llm_providers.charger().values()),
        "wallpaper_dir": get_wallpaper_dir(),
        "screenshots_dir": get_screenshots_dir(),
        "matugen_scheme": style_data.get("matugen_scheme", "scheme-tonal-spot"),
        "matugen_contrast": float(style_data.get("matugen_contrast", 0)),
        "blur_enabled": bool(style_data.get("blur_enabled", True)),
        "blur_size": int(style_data.get("blur_size", 3)),
        "blur_passes": int(style_data.get("blur_passes", 3)),
        "blur_vibrancy": float(style_data.get("blur_vibrancy", 0.1696)),
        "shell_blur_enabled": bool(style_data.get("shell_blur_enabled", True)),
        "shell_blur_alpha": float(style_data.get("shell_blur_alpha", 0.4)),
        "shell_blur_popups": bool(style_data.get("shell_blur_popups", True)),
        "launch_history": bool(style_data.get("launch_history", False)),
        "resize_step": int(style_data.get("resize_step", 15)),
        "panel_sections": style_data.get("panel_sections", {}),
        "gaps": get_hypr_gaps(),
        "display": get_monitors_info(),
        "binds": get_binds_list(),
        "apps": load_json(APP_VARS_FILE),
        "autostart": get_autostart(),
        "homelab": lire_homelab(),
        "todo": {"fichiers": lire_todo(), "focus": lire_todo_focus()},
        # Mode nuit : état et plage, pour l'onglet « Système & Écrans ».
        "night": {
            "mode": bool(style_data.get("night_mode", False)),
            "temperature": int(style_data.get("night_temp", 4000) or 4000),
            "from": str(style_data.get("night_from") or ""),
            "to": str(style_data.get("night_to") or ""),
        },
        "do_not_disturb": bool(style_data.get("do_not_disturb", False)),
    }


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "state"
    if action == "state":
        print(json.dumps(get_full_config_state()))
    elif action == "kb_layout" and len(sys.argv) > 2:
        set_kb_layout(sys.argv[2], mark_first_run_done=True)
        print(json.dumps(get_full_config_state()))
    elif action == "todo_add" and len(sys.argv) > 3:
        ok = todo_add(sys.argv[2], sys.argv[3])
        etat = get_full_config_state()
        etat["todo"]["erreur"] = "" if ok else f"Fichier introuvable : {sys.argv[3]}"
        print(json.dumps(etat))
    elif action == "todo_del" and len(sys.argv) > 2:
        todo_del(sys.argv[2])
        etat = get_full_config_state()
        etat["todo"]["erreur"] = ""
        print(json.dumps(etat))
    elif action == "todo_focus" and len(sys.argv) > 2:
        todo_focus(sys.argv[2])
        etat = get_full_config_state()
        etat["todo"]["erreur"] = ""
        print(json.dumps(etat))
    elif action == "todo_list":
        print(json.dumps({"fichiers": lire_todo(), "focus": lire_todo_focus()},
                         ensure_ascii=False))
    elif action == "homelab_set" and len(sys.argv) > 3:
        homelab_set(sys.argv[2], sys.argv[3])
        print(json.dumps(get_full_config_state()))
    elif action == "api_key_set_file" and len(sys.argv) > 2:
        print(json.dumps(set_secret_from_file(sys.argv[2]), ensure_ascii=False))
    elif action == "complete_first_run":
        complete_first_run()
        print(json.dumps(get_full_config_state()))
    elif action == "panel_section" and len(sys.argv) > 3:
        set_panel_section(sys.argv[2], sys.argv[3] == "true")
        print(json.dumps(get_full_config_state()))
    elif action == "widget_list":
        print(json.dumps(get_full_config_state()))
    elif action == "widget_add" and len(sys.argv) > 2:
        # Convention du panneau : chaque commande rend l'état complet, sinon
        # config_panel.qml doit relancer un `state` après chaque clic.
        ws = sys.argv[3] if len(sys.argv) > 3 else 1
        wx = sys.argv[4] if len(sys.argv) > 4 else 120
        wy = sys.argv[5] if len(sys.argv) > 5 else 160
        widget_add(sys.argv[2], ws, wx, wy)
        print(json.dumps(get_full_config_state()))
    elif action == "widget_set" and len(sys.argv) > 4:
        widget_set(sys.argv[2], sys.argv[3], sys.argv[4])
        print(json.dumps(get_full_config_state()))
    elif action == "widget_workspaces" and len(sys.argv) > 3:
        widget_workspaces(sys.argv[2], sys.argv[3])
        print(json.dumps(get_full_config_state()))
    elif action == "widget_move" and len(sys.argv) > 4:
        widget_move(sys.argv[2], sys.argv[3], sys.argv[4])
        print(json.dumps(get_full_config_state()))
    elif action == "widget_remove" and len(sys.argv) > 2:
        widget_remove(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "style" and len(sys.argv) > 3:
        update_style_var(sys.argv[2], sys.argv[3])
        print(json.dumps(get_full_config_state()))
    elif action == "notif_quiet" and len(sys.argv) > 3:
        new_list = set_quiet_notif_app(" ".join(sys.argv[3:]), sys.argv[2] == "true")
        print(json.dumps({"ok": True, "quiet_notif_apps": new_list}))
    elif action == "gaps" and len(sys.argv) > 3:
        update_hypr_gaps(sys.argv[2], sys.argv[3])
        print(json.dumps(get_full_config_state()))
    elif action == "monitor_primary" and len(sys.argv) > 2:
        set_primary_monitor(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "monitor_profile" and len(sys.argv) > 2:
        set_monitor_profile(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "monitor_mode" and len(sys.argv) > 3:
        scale = sys.argv[4] if len(sys.argv) > 4 else "1"
        set_monitor_mode(sys.argv[2], sys.argv[3], scale)
        print(json.dumps(get_full_config_state()))
    elif action == "rotate" and len(sys.argv) > 2:
        set_screen_rotation(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "bind_set" and len(sys.argv) > 3:
        set_keybind(sys.argv[2], " ".join(sys.argv[3:]))
        print(json.dumps(get_full_config_state()))
    elif action == "bind_del" and len(sys.argv) > 2:
        remove_keybind(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "sync_generated":
        # Régénère programs.lua et autostart_cmds.txt depuis les JSON préservés.
        sync_programs_lua(load_json(APP_VARS_FILE))
        sync_autostart_lua(get_autostart())
        print(json.dumps({"ok": True}))
    elif action == "app_set" and len(sys.argv) > 3:
        set_app_var(sys.argv[2], " ".join(sys.argv[3:]))
        print(json.dumps(get_full_config_state()))
    elif action == "app_del" and len(sys.argv) > 2:
        remove_app_var(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "notif_app_set" and len(sys.argv) > 3:
        print(json.dumps({"ok": set_notif_app(sys.argv[2], " ".join(sys.argv[3:]))}))
    elif action == "notif_app_del" and len(sys.argv) > 2:
        print(json.dumps({"ok": remove_notif_app(sys.argv[2])}))
    elif action == "notif_type_set" and len(sys.argv) > 3:
        print(json.dumps({"ok": set_notif_type(sys.argv[2], sys.argv[3])}))
    elif action == "notif_url_set" and len(sys.argv) > 2:
        print(json.dumps({"ok": set_notif_url(sys.argv[2])}))
    elif action == "autostart_set" and len(sys.argv) > 3:
        set_autostart(sys.argv[2], enabled=(sys.argv[3] == "true"))
        print(json.dumps(get_full_config_state()))
    elif action == "autostart_add" and len(sys.argv) > 3:
        add_autostart(sys.argv[2], " ".join(sys.argv[3:]))
        print(json.dumps(get_full_config_state()))
    elif action == "autostart_del" and len(sys.argv) > 2:
        remove_autostart(sys.argv[2])
        print(json.dumps(get_full_config_state()))
    elif action == "battery" and len(sys.argv) > 2:
        subprocess.run(["python3", SYSTEM_SERVICE, "limit", sys.argv[2]], check=False)
        print(json.dumps(get_full_config_state()))
    else:
        print(json.dumps(get_full_config_state()))
