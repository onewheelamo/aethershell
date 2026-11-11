#!/bin/sh
# Veille des dossiers de schémas de couleurs, pour le shell.
#
# Le catalogue est lu une fois au démarrage du shell ; il doit être relu quand un
# `.colors` apparaît ou disparaît dans l'un des deux dossiers. `inotifywait` fait
# cette veille en un seul processus, sans sondage : une ligne par événement, et
# `main.qml` relance `themes_scan.py --sync` quand la ligne nomme un `.colors`.
#
# Sans `inotifywait` (paquet inotify-tools), le script sort en 0 sans rien faire :
# la lecture du démarrage et celle de l'ouverture du panneau restent, la veille
# continue seulement à manquer.

command -v inotifywait >/dev/null 2>&1 || exit 0

set --
for d in /usr/share/color-schemes "$HOME/.local/share/color-schemes"; do
    [ -d "$d" ] || continue
    set -- "$@" "$d"
done
[ $# -gt 0 ] || exit 0

exec inotifywait -m -q --format '%e %w%f' \
    -e create -e delete -e moved_to -e moved_from -e close_write \
    "$@"
