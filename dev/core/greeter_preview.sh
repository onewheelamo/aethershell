#!/bin/sh
# Aperçu plein écran du greeter, avec une porte de sortie.
#
#   greeter_preview.sh start <dossier-thème> [secondes]
#   greeter_preview.sh stop
#
# Le mode test de sddm-greeter-qt6 n'a aucun socket d'authentification : la
# fenêtre est plein écran, identique au vrai écran de connexion, et un mot de
# passe tapé dedans se perd sans message. Elle n'est pas refermable depuis son
# propre QML — mesuré : `Qt.quit()` s'exécute sans arrêter le processus — donc
# la sortie est côté compositeur : binds.lua lie Échap à `stop`, qui tue le PID
# enregistré. Le délai reste le filet de sécurité si personne n'appuie.
set -u

RUNDIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/quickshell-session"
PIDFILE="$RUNDIR/greeter-preview.pid"
WSFILE="$RUNDIR/greeter-preview.ws"
PREV_WORKSPACE=99
mkdir -p "$RUNDIR" 2>/dev/null || true

changer_workspace() {
    target="${1:-99}"
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl repl "hl.dispatch(hl.dsp.focus({ workspace = $target }))" >/dev/null 2>&1 || \
            hyprctl dispatch workspace "$target" >/dev/null 2>&1 || true
    fi
}

restaurer_workspace() {
    if [ -f "$WSFILE" ]; then
        orig=$(cat "$WSFILE" 2>/dev/null || true)
        rm -f "$WSFILE"
        if [ -n "$orig" ]; then
            changer_workspace "$orig"
        fi
    fi
}

is_greeter() {
    # comm est tronqué à 15 caractères par le noyau : « sddm-greeter-qt ».
    [ -n "${1:-}" ] && [ -r "/proc/$1/comm" ] &&
        [ "$(cat "/proc/$1/comm" 2>/dev/null)" = "sddm-greeter-qt" ]
}

stop() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null || true)
        rm -f "$PIDFILE"
        # Un PID recyclé ne doit pas emporter autre chose que le greeter.
        if is_greeter "$pid"; then
            kill "$pid" 2>/dev/null || true
        fi
    fi
    restaurer_workspace
}

start() {
    theme="${1:-}"
    secs="${2:-45}"
    if [ ! -d "$theme" ]; then
        echo "greeter_preview: thème absent : $theme" >&2
        exit 1
    fi

    # Mémoriser le workspace actif et basculer sur le bureau dédié
    if command -v hyprctl >/dev/null 2>&1; then
        current_ws=$(hyprctl activeworkspace -j 2>/dev/null | grep -o '"id": *[0-9]*' | head -1 | awk '{print $2}')
        [ -n "$current_ws" ] || current_ws="1"
        echo "$current_ws" > "$WSFILE"
        changer_workspace "$PREV_WORKSPACE"
    fi

    QT_QPA_PLATFORM=wayland sddm-greeter-qt6 --test-mode --theme "$theme" &
    pid=$!
    echo "$pid" > "$PIDFILE"

    # Filet de sécurité : referme au bout du délai même sans appui sur Échap.
    (
        i=0
        while [ "$i" -lt "$((secs * 5))" ]; do
            kill -0 "$pid" 2>/dev/null || break
            i=$((i + 1))
            sleep 0.2
        done
        kill "$pid" 2>/dev/null || true
    ) &

    wait "$pid" 2>/dev/null
    rm -f "$PIDFILE"
    restaurer_workspace

    # La copie jetable du thème ne survit pas à l'aperçu.
    case "$theme" in
        /var/tmp/greeter-preview-*) rm -rf "$theme" ;;
    esac
}

case "${1:-}" in
    start) shift; start "$@" ;;
    stop)  stop ;;
    *)     echo "usage: greeter_preview.sh {start <thème> [s]|stop}" >&2; exit 2 ;;
esac
