#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# SCREENSHOT UTILITY (screenshot.sh)
# ══════════════════════════════════════════════════════════════════════════════
# Triggered via SUPER + SHIFT + S:
#   • Allows region / window interactive selection with mouse
#   • Copies captured image to clipboard (wl-copy)
#   • Saves image file into ~/Images/Screenshots or ~/Pictures/Screenshots
#   • Triggers notification preview
# ══════════════════════════════════════════════════════════════════════════════

# Determine screenshot destination directory
if [ -d "$HOME/Images" ]; then
    SCREENSHOTS_DIR="$HOME/Images/Screenshots"
elif [ -d "$HOME/Pictures" ]; then
    SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
else
    SCREENSHOTS_DIR="${XDG_PICTURES_DIR:-$HOME/Images}/Screenshots"
fi
mkdir -p "$SCREENSHOTS_DIR"

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
FILENAME="Capture_${TIMESTAMP}.png"
FILEPATH="${SCREENSHOTS_DIR}/${FILENAME}"

# 1. Prefer hyprshot (native Hyprland area & window capture + clipboard + notification)
if command -v hyprshot &>/dev/null; then
    hyprshot -m region --output-folder "$SCREENSHOTS_DIR" --filename "$FILENAME"
    exit 0
fi

# 2. Fallback to grimblast
if command -v grimblast &>/dev/null; then
    grimblast --notify copysave area "$FILEPATH"
    exit 0
fi

# 3. Fallback to grim + slurp + wl-copy
if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
    GEOM="$(slurp 2>/dev/null)"
    if [ -n "$GEOM" ]; then
        grim -g "$GEOM" "$FILEPATH"
        if command -v wl-copy &>/dev/null; then
            wl-copy < "$FILEPATH"
        fi
        if command -v notify-send &>/dev/null; then
            notify-send -i "$FILEPATH" "Capture d'écran" "Enregistrée dans $FILENAME et copiée dans le presse-papier"
        fi
    fi
    exit 0
fi

if command -v notify-send &>/dev/null; then
    notify-send -u critical "Capture d'écran" "Aucun outil de capture trouvé (installez hyprshot ou grimblast)."
fi
exit 1

