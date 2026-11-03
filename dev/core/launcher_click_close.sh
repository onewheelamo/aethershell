#!/bin/sh
# Ferme le launcher (fuzzel) quand le clic a eu lieu hors de sa fenêtre.
#
# Hyprland 0.57 ne retire pas le focus clavier d'une surface layer quand on
# clique sur le bureau ou sur la fenêtre déjà active : fuzzel, qui quitte
# pourtant sur perte de focus clavier, reste donc affiché.
#
# Appelée par un bind souris non-consommant (hypr_modular/binds.lua), cette
# commande ne fait rien tant qu'aucun launcher n'est ouvert — d'où le `pgrep`
# en premier, avant tout appel à hyprctl.

pgrep -x fuzzel >/dev/null 2>&1 || exit 0

# Géométrie de la couche du launcher :
#   Layer 0x...: xywh: X Y W H, a: 1, namespace: launcher, pid: ...
geom=$(hyprctl layers 2>/dev/null | awk '/namespace: launcher/ {
    for (i = 1; i <= NF; i++)
        if ($i == "xywh:") { gsub(",", "", $7); print $4, $5, $6, $7; exit }
}')
[ -n "$geom" ] || exit 0
set -- $geom
lx=$1
ly=$2
lw=$3
lh=$4

pos=$(hyprctl cursorpos 2>/dev/null) || exit 0
cx=${pos%,*}
cy=${pos#*,}
cx=${cx# }
cy=${cy# }

if [ "$cx" -lt "$lx" ] || [ "$cx" -ge $((lx + lw)) ] ||
   [ "$cy" -lt "$ly" ] || [ "$cy" -ge $((ly + lh)) ]; then
    pkill -x fuzzel
fi
