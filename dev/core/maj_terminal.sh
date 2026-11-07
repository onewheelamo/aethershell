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

case "$TERMINAL_CHOISI" in
    ghostty|kitty|foot|alacritty) exec "$TERMINAL_CHOISI" -e bash -lc "$CORPS" ;;
    konsole)                      exec konsole -e bash -lc "$CORPS" ;;
    xterm)                        exec xterm -e bash -lc "$CORPS" ;;
    *)                            exec "$TERMINAL_CHOISI" -e bash -lc "$CORPS" ;;
esac
