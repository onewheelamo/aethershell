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
#
# L'enregistrement vidéo ne doit jamais échouer en silence : wf-recorder est
# lancé avec sa sortie dans un journal (~/.cache/quickshell/screenshot.log) et
# on vérifie qu'il est encore vivant un instant plus tard. S'il est mort
# (encodeur absent, géométrie refusée, capture déjà prise), le fichier vide est
# supprimé et la notification porte le message réel de wf-recorder.
# ══════════════════════════════════════════════════════════════════════════════

MODE="${1:-menu}"

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
LOG="${LOG_DIR}/screenshot.log"
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    printf '%s %-14s %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$MODE" "$*" >> "$LOG" 2>/dev/null
}

if [ "$MODE" = "menu" ]; then
    quickshell ipc -n call shell toggleScreenshotPicker 2>/dev/null || true
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

# Le pid et le chemin de la vidéo en cours vivent dans le dossier de session :
# c'est ce couple qui permet à `record-stop` d'arrêter le bon processus et
# d'annoncer le fichier produit.
RECORD_STATE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-recording-$(id -u)"

running_pid() {
    local pid
    pid="$(head -n 1 "$RECORD_STATE" 2>/dev/null)"
    case "$pid" in
        ''|*[!0-9]*) echo "" ;;
        *) if kill -0 "$pid" 2>/dev/null; then echo "$pid"; fi ;;
    esac
}

# pgrep couvre l'enregistrement lancé par une version précédente du script
# (état sans pid) et un wf-recorder démarré à la main.
any_recording_pid() {
    local pid
    pid="$(running_pid)"
    if [ -n "$pid" ]; then echo "$pid"; return; fi
    pgrep -x wf-recorder 2>/dev/null | head -n 1
}

notify_failure() {
    local detail="$1"
    # Pas d'apostrophe dans un ${var:-défaut} : bash y voit une citation ouverte.
    [ -n "$detail" ] || detail="wf-recorder s'est arrêté sans message"
    log "ÉCHEC : $detail"
    notify-send -a "Captures" -u critical -i "media-record" \
        "Enregistrement vidéo impossible" "${detail:0:180}"
}

# Notification d'une capture, avec la cible du clic déclarée dans un hint : le
# shell ouvre alors le fichier avec l'alias « Images » ou « Video » du tiroir
# « Programmes par défaut » (cascade de core/notif_target.py, règle 1). Le
# chemin est passé en `file://` pour que les espaces ne soient pas ambigus.
notify_capture() {
    local summary="$1" body="$2" path="${3:-}"
    local -a args=(-a "Captures")
    if [ -n "$path" ]; then
        args+=(-h "string:x-amo-open:file://${path}" -i "$path")
    else
        args+=(-i "camera-photo")
    fi
    notify-send "${args[@]}" "$summary" "$body"
    log "notification : $summary${path:+ → $path}"
}

start_recording() {
    local geometry="$1"
    local file="${SCREENSHOTS_DIR}/Video_${TIMESTAMP}.mp4"
    local wflog="${LOG_DIR}/wf-recorder.log"
    local pid i

    if [ -n "$(any_recording_pid)" ]; then
        notify-send -a "Captures" -i "media-record" "Enregistrement vidéo" \
            "Un enregistrement est déjà en cours."
        log "refus : enregistrement déjà en cours"
        exit 0
    fi
    if ! command -v wf-recorder >/dev/null 2>&1; then
        notify_failure "wf-recorder n'est pas installé."
        exit 1
    fi
    mkdir -p "$LOG_DIR" 2>/dev/null
    : > "$wflog" 2>/dev/null

    # Pas de setsid : le script sort aussitôt et wf-recorder est réadopté par
    # init, mais on garde `$!`, donc le pid exact — c'est lui que `record-stop`
    # signale. wf-recorder ne touche pas au terminal, il survit à la sortie.
    if [ -n "$geometry" ]; then
        wf-recorder -g "$geometry" -f "$file" >"$wflog" 2>&1 &
    else
        wf-recorder -f "$file" >"$wflog" 2>&1 &
    fi
    pid=$!
    disown "$pid" 2>/dev/null || true
    printf '%s\n%s\n' "$pid" "$file" > "$RECORD_STATE"

    # wf-recorder négocie la capture au démarrage : s'il tombe tout de suite,
    # aucune notification ne partait avant et le fichier restait vide.
    for i in 1 2 3 4 5 6 7 8; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if ! kill -0 "$pid" 2>/dev/null; then
        local err
        err="$(tail -n 3 "$wflog" 2>/dev/null | tr '\n' ' ')"
        rm -f "$file" "$RECORD_STATE"
        notify_failure "$err"
        exit 1
    fi

    log "démarré pid $pid ${geometry:+(région $geometry)} → $file"
    # Pas de hint ici : le mp4 est en cours d'écriture, il n'y a rien à ouvrir.
    notify-send -a "Captures" -i "media-record" "Enregistrement vidéo démarré" \
        "${geometry:+Région $geometry — }SUPER + SHIFT + S, puis le carré pour arrêter. Fichier : $(basename "$file")"
}

stop_recording() {
    local pid file i
    pid="$(any_recording_pid)"
    file="$(sed -n '2p' "$RECORD_STATE" 2>/dev/null)"
    if [ -z "$pid" ]; then
        rm -f "$RECORD_STATE"
        notify-send -a "Captures" "Enregistrement vidéo" "Aucun enregistrement en cours."
        log "arrêt demandé, rien ne tournait"
        exit 0
    fi

    # SIGINT : wf-recorder finalise le mp4 (l'index est écrit à ce moment-là).
    kill -INT "$pid" 2>/dev/null || pkill -INT -x wf-recorder 2>/dev/null
    for i in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    rm -f "$RECORD_STATE"

    if [ -n "$file" ] && [ -s "$file" ]; then
        log "arrêté pid $pid → $file ($(du -h "$file" | cut -f1))"
        notify_capture "Enregistrement vidéo arrêté" \
            "Fichier : $(basename "$file")" "$file"
    else
        log "arrêté pid $pid, fichier absent ou vide${file:+ ($file)}"
        notify-send -u critical -i "media-record" "Enregistrement vidéo" \
            "Le fichier est vide — l'enregistrement n'a rien capturé."
    fi
}

pick_geometry() {
    if ! command -v slurp >/dev/null 2>&1; then
        notify_failure "slurp n'est pas installé (sélection de région)."
        exit 1
    fi
    # -d : affiche les dimensions pendant le glissé, comme hyprshot.
    # stdin reste /dev/null (hérité de Quickshell) : slurp ne bascule pas en
    # mode « rectangles prédéfinis » pour autant (il ne le fait que sur un pipe).
    local geom
    geom="$(slurp -d 2>>"$LOG")"
    local rc=$?
    if [ -z "$geom" ]; then
        # Échap / clic : annulation, silence. Un échec, lui, se dit.
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
            notify_failure "slurp a échoué (code $rc)."
            exit 1
        fi
        log "sélection annulée"
        exit 0
    fi
    printf '%s' "$geom"
}

case "$MODE" in
    region)
        # 1. hyprshot (sélection native Hyprland + presse-papier). `-s` coupe SA
        # notification : c'est la nôtre qui part, avec la cible du clic (hint).
        if command -v hyprshot &>/dev/null; then
            hyprshot -s -m region --output-folder "$SCREENSHOTS_DIR" --filename "$FILENAME"
            if [ -s "$FILEPATH" ]; then
                notify_capture "Capture d'écran" \
                    "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
                log "hyprshot region → $FILEPATH"
            else
                log "hyprshot region : rien produit (sélection annulée ?)"
            fi
            exit 0
        fi
        # 2. grimblast (sans --notify : la notification est la nôtre)
        if command -v grimblast &>/dev/null; then
            grimblast copysave area "$FILEPATH"
            [ -s "$FILEPATH" ] && notify_capture "Capture d'écran" \
                "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
            log "grimblast area → $FILEPATH"
            exit 0
        fi
        # 3. grim + slurp + wl-copy
        if command -v grim &>/dev/null && command -v slurp &>/dev/null; then
            GEOM="$(slurp 2>/dev/null)"
            if [ -n "$GEOM" ]; then
                grim -g "$GEOM" "$FILEPATH"
                command -v wl-copy &>/dev/null && wl-copy < "$FILEPATH"
                notify_capture "Capture d'écran" \
                    "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
                log "grim+slurp région → $FILEPATH"
            fi
            exit 0
        fi
        ;;
    full)
        # 1. hyprshot — la sortie qui a le focus, sans sa notification
        if command -v hyprshot &>/dev/null; then
            hyprshot -s -m output --output-folder "$SCREENSHOTS_DIR" --filename "$FILENAME"
            if [ -s "$FILEPATH" ]; then
                notify_capture "Capture d'écran" \
                    "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
                log "hyprshot output → $FILEPATH"
            else
                log "hyprshot output : rien produit"
            fi
            exit 0
        fi
        # 2. grimblast
        if command -v grimblast &>/dev/null; then
            grimblast copysave screen "$FILEPATH"
            [ -s "$FILEPATH" ] && notify_capture "Capture d'écran" \
                "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
            log "grimblast screen → $FILEPATH"
            exit 0
        fi
        # 3. grim sur la sortie courante
        if command -v grim &>/dev/null; then
            grim "$FILEPATH"
            command -v wl-copy &>/dev/null && wl-copy < "$FILEPATH"
            notify_capture "Capture d'écran" \
                "Enregistrée dans $FILENAME et copiée dans le presse-papier" "$FILEPATH"
            log "grim écran → $FILEPATH"
            exit 0
        fi
        ;;
    record-region)
        GEOM="$(pick_geometry)" || exit 1
        start_recording "$GEOM"
        exit 0
        ;;
    record|record-full)
        start_recording ""
        exit 0
        ;;
    record-stop)
        stop_recording
        exit 0
        ;;
    *)
        exit 0
        ;;
esac

notify_failure "Aucun outil de capture trouvé (installez hyprshot ou grimblast)."
exit 1
