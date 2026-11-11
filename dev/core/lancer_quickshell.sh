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
# Une seule instance par session : deux chemins de lancement coexistent (cette
# unité systemd, et l'autostart Hyprland qui appelle ce même script). Sans le
# verrou ci-dessous, le second en démarre une pendant que le premier attend
# encore le compositeur — `pgrep -x quickshell` ne voit pas un `sh` en attente.
# Mesuré : deux barres (l'une à y=40), deux jeux de veilleurs (notifications,
# presse-papiers, pactl) et deux instances à qui parlait l'IPC `shell`.
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

# Une instance du shell principal tourne-t-elle déjà ? Un lancement d'une AUTRE
# configuration (`-p` / `--path`, le sélecteur de fond d'écran) porte le même nom
# de process sans dessiner la barre : il ne compte pas.
shell_deja_lance() {
    for p in $(pgrep -x quickshell 2>/dev/null); do
        cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) || continue
        case "$cmd" in
            *" -p "*|*" --path "*) continue ;;
        esac
        return 0
    done
    return 1
}

# Verrou détenu pendant toute la vie du shell : le descripteur 9 est conservé par
# l'exec qui suit, donc il se libère exactement quand quickshell meurt (et
# `systemctl restart` tue l'ancien avant de relancer). Deux appels simultanés ne
# peuvent pas empiler deux instances : le second sort en 0 sans rien démarrer.
verrou="$r/aethershell.shell.lock"
if ! : 2>/dev/null > "$verrou"; then
    echo "quickshell : verrou impossible dans $r (session absente ?)" >&2
    exit 1
fi
exec 9> "$verrou"
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
        echo "quickshell : un lancement est deja en cours, rien a faire" >&2
        exit 0
    fi
fi

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

# Sous verrou, dernière barrière : une instance peut avoir été lancée hors de ce
# script (à la main) pendant l'attente du compositeur.
if shell_deja_lance; then
    echo "quickshell : une instance tourne deja, rien a faire" >&2
    exit 0
fi

exec quickshell -n "$@"
