#!/usr/bin/env bash
# Hyprquickpaper selection hook for the session:
# 1. Resolves WALLPAPER_DIR from core/style_vars.json (configured in the Config Panel)
# 2. Applies the chosen wallpaper (or picks one from $WALLPAPER_DIR if a relative name or none was passed)
# 3. Triggers Matugen dynamic palette generation (Quickshell + Hyprland + Rofi)

STYLE_VARS="$HOME/.config/quickshell/core/style_vars.json"
if [ ! -f "$STYLE_VARS" ]; then
    STYLE_VARS="$HOME/dev/quickshell_todo/dev/core/style_vars.json"
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
export WALLPAPER_DIR

WALLPAPER="${1:-}"
if [ -n "$WALLPAPER" ] && [ ! -f "$WALLPAPER" ] && [ -f "${WALLPAPER_DIR%/}/$WALLPAPER" ]; then
    WALLPAPER="${WALLPAPER_DIR%/}/$WALLPAPER"
fi
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER="$(find "$WALLPAPER_DIR" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | head -n 1)"
fi
[ -z "$WALLPAPER" ] && exit 1

mkdir -p "$HOME/.cache/quickshell/hyprquickpaper"
echo "$WALLPAPER" > "$HOME/.cache/quickshell/hyprquickpaper/.current"

# Noctalia wins when it is running: it owns the wallpaper on its outputs
# (it would otherwise re-apply its persisted wallpaper over ours).
if pgrep -x noctalia > /dev/null 2>&1 && command -v noctalia &> /dev/null; then
    noctalia msg wallpaper-set "$WALLPAPER" 2>/dev/null || true
elif command -v awww &> /dev/null; then
    awww img "$WALLPAPER" -t grow --transition-duration 1
elif command -v swww &> /dev/null; then
    swww img "$WALLPAPER" -t grow --transition-duration 1
elif command -v hyprpaper &> /dev/null; then
    hyprpaper set "$WALLPAPER" 2>/dev/null || true
elif command -v swaybg &> /dev/null; then
    pkill -x swaybg 2>/dev/null
    setsid -f swaybg -i "$WALLPAPER" -m fill >/dev/null 2>&1
fi

if [ -x "$HOME/.config/quickshell/core/generate_colors.sh" ]; then
    "$HOME/.config/quickshell/core/generate_colors.sh" "$WALLPAPER"
elif [ -x "$HOME/dev/quickshell_todo/dev/core/generate_colors.sh" ]; then
    "$HOME/dev/quickshell_todo/dev/core/generate_colors.sh" "$WALLPAPER"
fi
