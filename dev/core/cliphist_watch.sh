#!/bin/sh
# Deux veilleurs cliphist — texte et images — qui se relancent tout seuls.
#
# Pourquoi un superviseur plutôt qu'une ligne par veilleur dans l'autostart :
# les anciennes entrées se gardaient avec `pgrep -f "wl-paste --watch"`. Or le
# `sh -c '…'` qui porte la garde contient lui-même cette chaîne, donc pgrep se
# trouvait lui-même, concluait « déjà lancé » et ne démarrait **rien**. Résultat :
# aucune entrée n'était enregistrée, et rien ne le disait.
#
# Ici la garde est un pidfile dans $XDG_RUNTIME_DIR : pas de motif à confondre
# avec soi-même, et le fichier disparaît à la fin de la session avec le reste du
# répertoire d'exécution.
set -u

STORE_MAX=300
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNTIME/quickshell-cliphist.pid"

# Déjà en place et vivant : une deuxième instance ne servirait à rien.
if [ -f "$PIDFILE" ]; then
    ancien=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "${ancien:-}" ] && kill -0 "$ancien" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT INT TERM

# Un veilleur qui meurt (perte du data-control, redémarrage du compositeur) est
# relancé après deux secondes ; la boucle est volontairement muette, elle ne doit
# rien écrire dans les journaux à chaque tour.
boucle() {
    while :; do
        "$@" || true
        sleep 2
    done
}

boucle wl-paste --watch cliphist -max-items "$STORE_MAX" store &
boucle wl-paste --type image --watch cliphist -max-items "$STORE_MAX" store &

wait
