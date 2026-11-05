#!/bin/sh
# Lance la cible d'une notification et signale l'échec.
#
# Usage : notif_open.sh <libellé> -- <commande> [args...]
#
# Un clic sur le titre d'une notification ne doit pas rester sans effet : si la
# commande n'existe plus (binaire désinstallé, alias renommé dans le tiroir
# « Programmes par défaut »), la sortie d'erreur est remontée en notification
# critique au lieu d'être perdue — le même piège que « la capture vidéo ne
# marche pas », où rien ne disait pourquoi.
label="$1"
[ $# -gt 0 ] && shift
[ "$1" = "--" ] && shift
[ $# -eq 0 ] && exit 2

err=$("$@" 2>&1 >/dev/null)
status=$?
if [ "$status" -ne 0 ]; then
    detail=$(printf '%s' "$err" | head -n 3 | tr '\n' ' ')
    [ -n "$detail" ] || detail="code $status"
    notify-send -a "quickshell" -u critical "Impossible d'ouvrir : $label" "$detail"
fi
exit "$status"
