#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# SCREENSHOT UTILITY (screenshot.sh)
# ══════════════════════════════════════════════════════════════════════════════
# Triggered via SUPER + SHIFT + S. Without argument the script does not capture
# anything: it opens the capture bar (barre posée à gauche de l'écran), whose
# entries call it back with a mode.
#
#   screenshot.sh                → ouvre/ferme la barre de capture (IPC Quickshell)
#   screenshot.sh region         → sélection à la souris, copie + notification
#   screenshot.sh full           → écran entier (sortie courante)
#   screenshot.sh record-region  → vidéo d'une région (wf-recorder + slurp)
#   screenshot.sh record-full    → vidéo de l'écran entier
#   screenshot.sh record-stop    → arrête l'enregistrement en cours (SIGINT)
#
# Le dossier de destination vient de core/style_vars.json (réglable depuis le
# panneau, « Dossier des captures ») ; à défaut, ~/Images/Screenshots.
# ══════════════════════════════════════════════════════════════════════════════

MODE="${1:-menu}"

if [ "$MODE" = "menu" ]; then
    quickshell ipc call shell toggleScreenshotPicker 2>/dev/null || true
    exit 0
fi

# Dossier configuré (la valeur est stockée avec un $HOME littéral).
CONFIGURED="$(python3 - "$HOME/.config/quickshell/core/style_vars.json" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("screenshots_dir", ""))
except Exception:
    print("")
PY
)"
CONFIGURED="${CONFIGURED//\$HOME/$HOME}"
if [ -n "$CONFIGURED" ]; then
    SCREENSHOTS_DIR="${CONFIGURED%/}"
else
    SCREENSHOTS_DIR="$HOME/Images/Screenshots"
fi
mkdir -p "$SCREENSHOTS_DIR"

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
FILENAME="Capture_${TIMESTAMP}.png"
FILEPATH="${SCREENSHOTS_DIR}/${FILENAME}"

# Le chemin de la vidéo en cours vit dans le dossier de session : c'est lui qui
# permet à `record-stop` d'annoncer le fichier produit.
RECORD_STATE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-recording-$(id -u)"

start_recording() {
    local geometry="$1"
    local file="${SCREENSHOTS_DIR}/Video_${TIMESTAMP}.mp4"

    if pgrep -x wf-recorder >/dev/null 2>&1; then
        notify-send -i "media-record" "Enregistrement vidéo" \
            "Un enregistrement est déjà en cours."
        exit 0
    fi
    if ! command -v wf-recorder >/dev/null 2>&1; then
        notify-send -u critical "Enregistrement vidéo" "wf-recorder n'est pas installé."
        exit 1
    fi

    # setsid : l'enregistrement doit survivre à la sortie du script (lancé par
    # execDetached depuis le shell) et à la fermeture de la barre.
    if [ -n "$geometry" ]; then
        setsid wf-recorder -g "$geometry" -f "$file" >/dev/null 2>&1 &
    else
        setsid wf-recorder -f "$file" >/dev/null 2>&1 &
    fi
    echo "$file" > "$RECORD_STATE"
    notify-send -i "media-record" "Enregistrement vidéo démarré" \
        "Relance SUPER + SHIFT + S pour arrêter. Fichier : $(basename "$file")"
}

case "$MODE" in
    region)
        # 1. hyprshot (sélection native Hyprland + presse-papier + notification)
        if command -v hyprshot &>/dev/null; then
            hyprshot -m region --output-folder "$SCREENSHOTS_DIR" --filename "$FILENAME"
            exit 0
        fi
        # 2. grimblast
        if command -v grimblast &>/dev/null; then
            grimblast --notify copysave area "$FILEPATH"
            exit 0
        fi
        # 3. grim + slurp + wl-copy
        if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
            GEOM="$(slurp 2>/dev/null)"
            if [ -n "$GEOM" ]; then
                grim -g "$GEOM" "$FILEPATH"
                command -v wl-copy &>/dev/null && wl-copy < "$FILEPATH"
                command -v notify-send &>/dev/null && \
                    notify-send -i "$FILEPATH" "Capture d'écran" \
                    "Enregistrée dans $FILENAME et copiée dans le presse-papier"
            fi
            exit 0
        fi
        ;;
    full)
        # 1. hyprshot — la sortie qui a le focus
        if command -v hyprshot &>/dev/null; then
            hyprshot -m output --output-folder "$SCREENSHOTS_DIR" --filename "$FILENAME"
            exit 0
        fi
        # 2. grimblast
        if command -v grimblast &>/dev/null; then
            grimblast --notify copysave screen "$FILEPATH"
            exit 0
        fi
        # 3. grim sur la sortie courante
        if command -v grim &>/dev/null; then
            grim "$FILEPATH"
            command -v wl-copy &>/dev/null && wl-copy < "$FILEPATH"
            command -v notify-send &>/dev/null && \
                notify-send -i "$FILEPATH" "Capture d'écran" \
                "Enregistrée dans $FILENAME et copiée dans le presse-papier"
            exit 0
        fi
        ;;
    record-region)
        if ! command -v slurp &>/dev/null; then
            notify-send -u critical "Enregistrement vidéo" "slurp n'est pas installé."
            exit 1
        fi
        GEOM="$(slurp 2>/dev/null)"
        [ -z "$GEOM" ] && exit 0        # sélection annulée
        start_recording "$GEOM"
        exit 0
        ;;
    record|record-full)
        start_recording ""
        exit 0
        ;;
    record-stop)
        if pgrep -x wf-recorder >/dev/null 2>&1; then
            pkill -INT -x wf-recorder
            FILE="$(cat "$RECORD_STATE" 2>/dev/null || true)"
            rm -f "$RECORD_STATE"
            notify-send -i "media-record" "Enregistrement vidéo arrêté" \
                "${FILE:+Fichier : $(basename "$FILE")}"
            exit 0
        fi
        rm -f "$RECORD_STATE"
        notify-send "Enregistrement vidéo" "Aucun enregistrement en cours."
        exit 0
        ;;
    *)
        exit 0
        ;;
esac

if command -v notify-send &>/dev/null; then
    notify-send -u critical "Capture d'écran" "Aucun outil de capture trouvé (installez hyprshot ou grimblast)."
fi
exit 1
