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
# Le nœud de socket, lui, survit aussi à la session : il passe donc le test
# d'existence alors que plus personne n'écoute, et Qt avorte encore. D'où le
# second test — sur Hyprland, une signature doit **répondre** (`hyprctl
# version`). Un compositeur mort laisse son dossier mais ne répond pas.
#
# Ici on attend le compositeur quelques secondes (démarrage à froid), et on sort
# en 1 sans rien lancer s'il ne vient pas : un échec se lit dans le journal, il
# ne produit pas de coredump.
#
# Variables : QS_ATTENTE_S (défaut 45) = durée d'attente maximale.

r="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
max="${QS_ATTENTE_S:-45}"
attente=0
socket=""
signature=""

# Le compositeur est-il joignable ? Pose `socket` et `signature`.
compositeur_vivant() {
    socket="${WAYLAND_DISPLAY:-}"
    # Une valeur héritée n'est retenue que si elle désigne un socket existant.
    if [ -z "$socket" ] || [ ! -S "$r/$socket" ]; then
        socket=$(ls "$r" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
    fi
    [ -n "$socket" ] && [ -S "$r/$socket" ] || return 1

    # Hyprland : il faut une réponse, pas seulement un nœud présent. La plus
    # récente d'abord, au cas où une session précédente aurait laissé le sien.
    if [ -d "$r/hypr" ] && [ -n "$(ls -A "$r/hypr" 2>/dev/null)" ]; then
        for sig in $(ls -t "$r/hypr" 2>/dev/null); do
            if hyprctl -i "$sig" version >/dev/null 2>&1; then
                signature="$sig"
                return 0
            fi
        done
        return 1
    fi
    # Autre compositeur : le socket qui existe suffit.
    return 0
}

while ! compositeur_vivant; do
    attente=$((attente + 1))
    if [ "$attente" -ge "$max" ]; then
        echo "quickshell : aucun compositeur ne repond dans $r apres ${max}s (session absente ou en cours de demarrage)" >&2
        exit 1
    fi
    sleep 1
done

export WAYLAND_DISPLAY="$socket"
if [ -n "$signature" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$signature"
fi

exec quickshell -n "$@"
