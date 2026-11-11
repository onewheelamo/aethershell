#!/bin/sh
# Lance quickshell dans la bonne session Wayland, en attendant qu'elle existe.
#
# Pourquoi ce script existe : Hyprland ne transmet ni sa signature ni
# WAYLAND_DISPLAY au gestionnaire systemd. L'unité reprenait donc ces valeurs de
# son environnement — et `$WAYLAND_DISPLAY` y survit à la session qui l'a créé.
# `${WAYLAND_DISPLAY:-wayland-1}` ne protège que du cas « non défini » : une
# valeur périmée passait telle quelle, Qt ne trouvait aucun platform plugin et
# abandonnait (SIGABRT). Mesuré : 194 coredumps en sept jours, dont 142 en sept
# minutes, relancés toutes les 3 s par systemd.
#
# Ici on vérifie que le socket existe vraiment, on attend quelques secondes s'il
# n'est pas encore là (démarrage à froid), et on sort en 1 sans rien lancer si la
# session ne vient pas : un échec se lit dans le journal, il ne produit pas de
# coredump.
#
# Variables : QS_ATTENTE_S (défaut 20) = durée d'attente maximale du socket.

r="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
max="${QS_ATTENTE_S:-20}"
attente=0

while :; do
    socket="${WAYLAND_DISPLAY:-}"
    # Une valeur héritée n'est retenue que si elle désigne un socket existant.
    if [ -z "$socket" ] || [ ! -S "$r/$socket" ]; then
        socket=$(ls "$r" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
    fi
    if [ -n "$socket" ] && [ -S "$r/$socket" ]; then
        break
    fi
    attente=$((attente + 1))
    if [ "$attente" -ge "$max" ]; then
        echo "quickshell : aucun socket Wayland dans $r après ${max}s (session absente ou en cours de démarrage trop long)" >&2
        exit 1
    fi
    sleep 1
done

export WAYLAND_DISPLAY="$socket"

# Signature Hyprland : le dossier de sockets porte son nom. La plus récente
# d'abord, au cas où une session précédente aurait laissé le sien.
signature=$(ls -t "$r/hypr" 2>/dev/null | head -1)
if [ -n "$signature" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$signature"
fi

exec quickshell -n "$@"
