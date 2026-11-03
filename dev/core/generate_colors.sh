#!/usr/bin/env bash
# Matugen Color Generator for Quickshell + Rofi + Hyprland

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STYLE_VARS="$SCRIPT_DIR/style_vars.json"

if ! command -v matugen &> /dev/null; then
    echo "Matugen not installed. Skipping color generation."
    exit 1
fi

WALLPAPER_DIR="$(python3 - "$STYLE_VARS" << 'EOF' 2>/dev/null
import json, os, sys
p = sys.argv[1] if len(sys.argv) > 1 else ""
val = "$HOME/Images/wallpapers/"
if p and os.path.exists(p):
    try:
        with open(p, "r") as f:
            val = json.load(f).get("wallpaper_dir") or val
    except Exception:
        pass
print(os.path.expandvars(os.path.expanduser(val)))
EOF
)"
[ -z "$WALLPAPER_DIR" ] && WALLPAPER_DIR="$HOME/Images/wallpapers/"

WALLPAPER="${1:-}"
if [ -z "$WALLPAPER" ] && [ -f "$HOME/.cache/quickshell/hyprquickpaper/.current" ]; then
    WALLPAPER="$(cat "$HOME/.cache/quickshell/hyprquickpaper/.current")"
fi
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER="$(find "$WALLPAPER_DIR" "$HOME/Images/wallpapers" "$HOME/Pictures/wallpapers" "$HOME/Pictures" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | head -n 1)"
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo "No valid wallpaper found to generate palette."
    exit 1
fi

# Matugen scheme type + contrast level (set from the config panel, stored in style_vars.json)
MATUGEN_SCHEME="$(python3 - "$STYLE_VARS" << 'EOF' 2>/dev/null
import json, os, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("matugen_scheme") or "scheme-tonal-spot")
except Exception:
    print("scheme-tonal-spot")
EOF
)"
MATUGEN_CONTRAST="$(python3 - "$STYLE_VARS" << 'EOF' 2>/dev/null
import json, os, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("matugen_contrast", 0))
except Exception:
    print("0")
EOF
)"

MATUGEN_JSON="$(matugen image "$WALLPAPER" -t "$MATUGEN_SCHEME" --contrast "$MATUGEN_CONTRAST" --prefer saturation --dry-run --json hex -q 2>/dev/null)"
if [ -z "$MATUGEN_JSON" ]; then
    MATUGEN_JSON="$(matugen image "$WALLPAPER" -t "$MATUGEN_SCHEME" --contrast "$MATUGEN_CONTRAST" --source-color-index 0 --dry-run --json hex -q 2>/dev/null)"
fi
if [ -z "$MATUGEN_JSON" ]; then
    echo "Matugen failed to extract palette from $WALLPAPER"
    exit 1
fi

python3 - "$STYLE_VARS" "$MATUGEN_JSON" << 'EOF'
import json
import sys

style_path = sys.argv[1]
raw_json = sys.argv[2]

try:
    with open(style_path, "r") as f:
        style_data = json.load(f)
except Exception:
    style_data = {
        "active_theme": "dynamic",
        "global_radius": 2,
        "hypr_rounding": 2,
        "global_opacity": 0.85,
        "kb_layout": "fr",
        "first_run_completed": False,
        "palette": {"dynamic": {}}
    }

m_data = json.loads(raw_json)
colors = m_data.get("colors", {})

def get_hex(token, fallback):
    val = colors.get(token, {})
    if isinstance(val, dict):
        dark = val.get("dark", val.get("default", fallback))
        if isinstance(dark, dict):
            return dark.get("color", dark.get("hex", fallback))
        if isinstance(dark, str):
            return dark if dark.startswith("#") else f"#{dark}"
    elif isinstance(val, str):
        return val if val.startswith("#") else f"#{val}"
    return fallback

style_data.setdefault("palette", {})["dynamic"] = {
    "bg": get_hex("surface_container_lowest", "#1e1e2e"),
    "fg": get_hex("on_surface", "#cdd6f4"),
    "accent": get_hex("primary", "#b4befe"),
    "accent_muted": get_hex("secondary", "#89b4fa"),
    "surface": get_hex("surface", "#313244"),
    "surface_variant": get_hex("surface_container", "#45475a"),
    "error": get_hex("error", "#f38ba8"),
    "warn": get_hex("tertiary", "#fab387"),
    "info": get_hex("secondary", "#89b4fa"),
    "success": get_hex("tertiary_fixed_dim", "#a6e3a1")
}
style_data["active_theme"] = "dynamic"

with open(style_path, "w") as f:
    json.dump(style_data, f, indent=4)

print(f"Dynamic palette updated in {style_path}")
EOF

"$SCRIPT_DIR/generate_rofi_theme.sh"
