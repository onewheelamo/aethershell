#!/usr/bin/env bash
# Rofi, Hyprland (colors.lua) & Hyprquickpaper Theme Generator synchronized with style_vars.json

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_ROOT="$(dirname "$SCRIPT_DIR")"
STYLE_VARS="$SCRIPT_DIR/style_vars.json"
ROFI_DIR="$HOME/.config/rofi"
ROFI_CONFIG="$ROFI_DIR/config.rasi"
FUZZEL_DIR="$HOME/.config/fuzzel"
FUZZEL_CONFIG="$FUZZEL_DIR/fuzzel.ini"

if [ ! -f "$STYLE_VARS" ]; then
    echo "style_vars.json not found at $STYLE_VARS"
    exit 1
fi

COLORS=$(python3 - "$STYLE_VARS" << 'EOF'
import json
import sys

with open(sys.argv[1], "r") as f:
    d = json.load(f)

active = d.get("active_theme", "dynamic")
palettes = d.get("palette", {})
p = palettes.get(active) or palettes.get("dynamic", {})
radius = d.get("global_radius", 2)
opacity = d.get("global_opacity", 0.85)

def norm(c, default):
    val = str(p.get(c, default)).strip()
    return val if val.startswith("#") else f"#{val}"

print(",".join([
    norm("bg", "#1e1e2e"),
    norm("fg", "#cdd6f4"),
    norm("accent", "#b4befe"),
    norm("surface", "#313244"),
    norm("surface_variant", "#45475a"),
    norm("error", "#f38ba8"),
    str(radius),
    str(opacity)
]))
EOF
)

IFS=',' read -r BG FG ACCENT SURFACE SURFACE_VAR ERROR RADIUS OPACITY <<< "$COLORS"
ACCENT_NOHASH="${ACCENT#\#}"
SURFACE_VAR_NOHASH="${SURFACE_VAR#\#}"

# 1. Generate Rofi theme directly into ~/.config/rofi/config.rasi
mkdir -p "$ROFI_DIR" 2>/dev/null || true
if [ -d "$ROFI_DIR" ]; then
cat <<EOF > "$ROFI_CONFIG"
configuration {
    modi: "drun,run,window";
    show-icons: true;
    terminal: "kitty";
    drun-display-format: "{name}";
    location: 0;
    disable-history: false;
    sidebar-mode: true;
    hover-select: true;
    me-select-entry: "";
    me-accept-entry: "!MousePrimary";
    kb-cancel: "Escape,Control+g,MousePrimary";
}

* {
    bg: ${BG};
    fg: ${FG};
    accent: ${ACCENT};
    surface: ${SURFACE};
    surface-var: ${SURFACE_VAR};
    urgent: ${ERROR};
    background-color: transparent;
    text-color: @fg;
}

window {
    fullscreen: true;
    transparency: "real";
    background-color: #00000044;
    cursor: "default";
    padding: 0px;
    border: 0px;
    children: [ dummy-top, center-row, dummy-bottom ];
}

dummy-top {
    expand: true;
    background-color: transparent;
}

dummy-bottom {
    expand: true;
    background-color: transparent;
}

center-row {
    orientation: horizontal;
    expand: false;
    children: [ dummy-left, mainbox, dummy-right ];
    background-color: transparent;
}

dummy-left {
    expand: true;
    background-color: transparent;
}

dummy-right {
    expand: true;
    background-color: transparent;
}

mainbox {
    width: 600px;
    expand: false;
    background-color: @bg;
    border: 2px;
    border-color: @accent;
    border-radius: ${RADIUS}px;
    padding: 20px;
    spacing: 12px;
    children: [ inputbar, message, listview, mode-switcher ];
}

inputbar {
    background-color: @surface;
    text-color: @fg;
    border-radius: ${RADIUS}px;
    padding: 8px 12px;
    children: [ prompt, entry ];
}

prompt {
    background-color: transparent;
    text-color: @accent;
    margin: 0px 8px 0px 0px;
}

entry {
    background-color: transparent;
    text-color: @fg;
    placeholder: "Rechercher...";
    placeholder-color: @surface-var;
}

message {
    background-color: transparent;
    padding: 0px;
}

textbox {
    text-color: @fg;
    background-color: @surface;
    padding: 8px 12px;
    border-radius: ${RADIUS}px;
}

listview {
    background-color: transparent;
    spacing: 6px;
    lines: 8;
    columns: 1;
}

element {
    background-color: transparent;
    padding: 8px 12px;
    spacing: 10px;
    border-radius: ${RADIUS}px;
    cursor: pointer;
}

element selected {
    background-color: @accent;
    text-color: @bg;
}

element-text {
    background-color: inherit;
    text-color: inherit;
    vertical-align: 0.5;
    cursor: pointer;
}

element-icon {
    size: 24px;
    background-color: transparent;
    cursor: pointer;
}

mode-switcher {
    spacing: 8px;
    background-color: transparent;
}

button {
    padding: 6px 12px;
    background-color: @surface;
    text-color: @fg;
    border-radius: ${RADIUS}px;
    cursor: pointer;
}

button selected {
    background-color: @accent;
    text-color: @bg;
}
EOF
fi

# 2. Generate Fuzzel configuration directly into ~/.config/fuzzel/fuzzel.ini
mkdir -p "$FUZZEL_DIR" 2>/dev/null || true
BG_NOHASH="${BG#\#}"
FG_NOHASH="${FG#\#}"
SURFACE_NOHASH="${SURFACE#\#}"
OPACITY_HEX=$(python3 -c "import sys; op = float(sys.argv[1]); print(f'{int(round(op * 255)):02x}')" "$OPACITY" 2>/dev/null || echo "e6")

if [ -d "$FUZZEL_DIR" ]; then
cat <<EOF > "$FUZZEL_CONFIG"
[main]
font=Noto Sans:size=12
prompt="  "
placeholder=Rechercher une application...
terminal=kitty
lines=10
width=38
horizontal-pad=20
vertical-pad=12
inner-pad=8
image-size-ratio=0.5
layer=overlay
exit-on-keyboard-focus-loss=yes

[border]
width=2
radius=${RADIUS}
selection-radius=${RADIUS}

[colors]
background=${BG_NOHASH}${OPACITY_HEX}
text=${FG_NOHASH}ff
prompt=${ACCENT_NOHASH}ff
placeholder=${SURFACE_VAR_NOHASH}cc
input=${FG_NOHASH}ff
match=${ACCENT_NOHASH}ff
selection=${SURFACE_NOHASH}${OPACITY_HEX}
selection-text=${ACCENT_NOHASH}ff
selection-match=${ACCENT_NOHASH}ff
border=${ACCENT_NOHASH}ff
EOF
fi

# 3. Generate Hyprland Lua colors file (colors.lua)
HYPR_COLORS_TARGET="$DEV_ROOT/hypr_modular/colors.lua"
if [[ "$SCRIPT_DIR" == "$HOME/.config/quickshell"* ]]; then
    HYPR_COLORS_TARGET="$HOME/.config/hypr/colors.lua"
fi

if [ -d "$(dirname "$HYPR_COLORS_TARGET")" ]; then
    cat <<EOF > "$HYPR_COLORS_TARGET"
-- ~/.config/hypr/colors.lua
-- Généré automatiquement via Matugen / style_vars.json
-- Applique la palette active aux bordures, arrondis et à l'opacité de Hyprland

hl.config({
    general = {
        col = {
            active_border   = "rgba(${ACCENT_NOHASH}ee)",
            inactive_border = "rgba(${SURFACE_VAR_NOHASH}aa)",
        },
    },
    decoration = {
        rounding         = ${RADIUS},
        active_opacity   = ${OPACITY},
        inactive_opacity = ${OPACITY},
    },
})
EOF
fi

# 4. Sync live configs if target directories exist or running from deployed location
if [ -d "$HOME/.config/quickshell/hyprquickpaper" ]; then
    (printf '{\n    "border_color": "%s"\n}\n' "$ACCENT" > "$HOME/.config/quickshell/hyprquickpaper/colors.json") 2>/dev/null || true
fi
