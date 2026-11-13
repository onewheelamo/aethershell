#!/usr/bin/env bash
# Ouvre une commande (mise à jour, par exemple) dans le premier terminal disponible.
#
# Pourquoi ce script existe : l'applet de mises à jour lançait `ghostty -e …` en
# dur. Sur une machine où ghostty n'est pas installé, `execDetached` échoue et
# **personne ne le voit** : le clic ne fait rien, sans message ni journal. Un
# terminal par défaut doit être une préférence, pas une hypothèse.
#
# Usage :
#   maj_terminal.sh "<commande à exécuter>"
#   maj_terminal.sh --resoudre        # affiche le terminal retenu, ne lance rien
#
# Ordre : $AETHER_TERMINAL, puis app_vars.json (clé Terminal) si présent, puis
# ghostty, kitty, foot, alacritty, konsole, xterm.
set -uo pipefail

CORPS="${1:-}"

resoudre() {
    local candidats=() t fichier
    [ -n "${AETHER_TERMINAL:-}" ] && candidats+=("$AETHER_TERMINAL")
    fichier="$(dirname "$(readlink -f "$0")")/app_vars.json"
    if [ -f "$fichier" ]; then
        t=$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("Terminal","") or "")
except Exception:
    print("")' "$fichier" 2>/dev/null)
        [ -n "$t" ] && candidats+=("$t")
    fi
    candidats+=(ghostty kitty foot alacritty konsole xterm)
    for t in "${candidats[@]}"; do
        [ -n "$t" ] || continue
        if command -v "$t" >/dev/null 2>&1; then
            printf '%s\n' "$t"
            return 0
        fi
    done
    return 1
}

if [ "$CORPS" = "--resoudre" ]; then
    t=$(resoudre) || { echo "aucun terminal"; exit 1; }
    echo "$t"
    exit 0
fi

[ -n "$CORPS" ] || { echo "usage : maj_terminal.sh \"<commande>\"" >&2; exit 2; }

TERMINAL_CHOISI=$(resoudre) || {
    # Dernier recours visible : au moins l'utilisateur saura pourquoi rien ne s'ouvre.
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a AetherShell "Aucun terminal trouvé" \
            "Installe ghostty, kitty ou foot : la commande ne peut pas s'ouvrir."
    fi
    echo "aucun terminal disponible" >&2
    exit 1
}

# 3. Préparation de l'enveloppe d'exécution :
# - Journalise dans ~/.cache/quickshell/maj.log via tee
# - Maintient le terminal ouvert si la commande échoue (code != 0)
LOG_DIR="$HOME/.cache/quickshell"
mkdir -p "$LOG_DIR"
WRAPPER="$LOG_DIR/maj_exec.sh"
cat << 'EOF' > "$WRAPPER"
#!/usr/bin/env bash
LOG="$HOME/.cache/quickshell/maj.log"
CMD="$*"
echo "=== Début de la mise à jour : $(date) ===" | tee -a "$LOG"
echo "Commande : $CMD" | tee -a "$LOG"
eval "$CMD" 2>&1 | tee -a "$LOG"
CODE=${PIPESTATUS[0]}
echo "=== Fin de la mise à jour (code $CODE) : $(date) ===" | tee -a "$LOG"
if [ $CODE -ne 0 ]; then
    echo ""
    echo "❌ La commande a échoué (code $CODE). Journal complet : $LOG"
    echo ""
    read -r -p "Appuyez sur Entrée pour fermer cette fenêtre..." _
fi
exit $CODE
EOF
chmod +x "$WRAPPER"

COMMANDE_FINALE="$(printf '%q %q' "$WRAPPER" "$CORPS")"

lancer_hors_cgroup() {
    if command -v systemd-run >/dev/null 2>&1 && systemctl --user is-system-running >/dev/null 2>&1; then
        exec systemd-run --user --scope --quiet -- "$@"
    else
        exec "$@"
    fi
}

case "$TERMINAL_CHOISI" in
    ghostty|kitty|foot|alacritty) lancer_hors_cgroup "$TERMINAL_CHOISI" -e bash -lc "$COMMANDE_FINALE" ;;
    konsole)                      lancer_hors_cgroup konsole -e bash -lc "$COMMANDE_FINALE" ;;
    xterm)                        lancer_hors_cgroup xterm -e bash -lc "$COMMANDE_FINALE" ;;
    *)                            lancer_hors_cgroup "$TERMINAL_CHOISI" -e bash -lc "$COMMANDE_FINALE" ;;
esac
