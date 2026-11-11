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
# unité systemd, et l'autostart Hyprland qui appelle ce même script). Sans
# garde-fou, le second en démarre une pendant que le premier attend encore le
# compositeur — `pgrep -x quickshell` ne voit pas un `sh` en attente. Mesuré :
# deux barres (l'une à y=40), deux jeux de veilleurs (notifications,
# presse-papiers, pactl) et deux instances à qui parlait l'IPC `shell`.
#
# Le garde-fou est double, et c'est le jeton qui tranche :
#   - un verrou `flock` sur $XDG_RUNTIME_DIR/aethershell.lancement.lock, tenu
#     seulement le temps de la décision (attente du compositeur comprise) et
#     refermé juste avant l'exec ;
#   - un jeton $XDG_RUNTIME_DIR/aethershell.shell.pid, qui nomme le shell et son
#     heure de démarrage, et ne vaut que si ce processus vit encore.
# Le verrou n'est PAS conservé à travers la vie du shell : ses enfants
# (`pactl subscribe`, `inotifywait`, veilleurs python…) héritaient du
# descripteur et le gardaient après sa mort. Un shell mort laissait donc des
# orphelins qui refusaient tout redémarrage — « un lancement est deja en cours,
# rien a faire » — alors que plus aucune barre n'était dessinée. Mesuré le
# 2026-11-11 : trois orphelins (pactl, inotifywait, tray_watchdog) tenaient le
# verrou d'un shell disparu, et la barre est restée absente jusqu'à leur mort.
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

# Heure de démarrage d'un processus — champ 22 de /proc/<pid>/stat, lu après le
# « ) » qui ferme son nom (celui-ci peut contenir espaces et parenthèses). Deux
# processus successifs peuvent porter le même pid : cette valeur, elle, ne se
# répète pas.
depart_de() {
    awk '{ sub(/.*\) /, ""); print $20 }' "/proc/$1/stat" 2>/dev/null
}

# Ce pid est-il le shell principal ? La ligne de commande doit le dire : un pid
# recyclé par un autre programme ne compte pas, et un lancement d'une AUTRE
# configuration (`-p` / `--path`, le sélecteur de fond d'écran) ne compte pas
# davantage — il porte le même nom de process sans dessiner la barre. Le lanceur
# lui-même compte : il porte le pid du futur shell avant son exec.
pid_est_shell() {
    _p=$1
    [ -n "$_p" ] && [ -r "/proc/$_p/cmdline" ] || return 1
    _c=$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null) || return 1
    case "$_c" in
        *lancer_quickshell.sh*) return 0 ;;
        quickshell|quickshell\ *)
            case "$_c" in
                *" -p "*|*" --path "*) return 1 ;;
            esac
            return 0 ;;
    esac
    return 1
}

# Un shell vit-il encore ? Le jeton fait foi : il nomme un pid, son heure de
# démarrage, et l'on vérifie sur /proc que ce pid désigne toujours le shell.
# Les enfants orphelins du shell ne portent pas ce jeton : eux seuls tenaient
# l'ancien verrou, et c'est de là que venait le blocage. Écrit le pid trouvé.
shell_vivant() {
    [ -s "$jeton" ] || return 1
    _pid=""
    _dep=""
    read -r _pid _dep < "$jeton" 2>/dev/null || true
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    if [ -n "$_dep" ]; then
        [ "$(depart_de "$_pid")" = "$_dep" ] || return 1
    fi
    pid_est_shell "$_pid" || return 1
    echo "$_pid"
}

# Une instance du shell principal tourne-t-elle déjà hors de ce lanceur (lancée
# à la main) ? Écrit son pid.
shell_deja_lance() {
    for _p in $(pgrep -x quickshell 2>/dev/null); do
        if pid_est_shell "$_p"; then
            echo "$_p"
            return 0
        fi
    done
    return 1
}

verrou="$r/aethershell.lancement.lock"
jeton="$r/aethershell.shell.pid"

# Premier test, sans verrou : le cas courant, un shell déjà vivant.
if _v=$(shell_vivant); then
    echo "quickshell : deja lance (pid $_v), rien a faire" >&2
    exit 0
fi

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

# Sous verrou : un second lanceur a pu écrire son jeton entre-temps.
if _v=$(shell_vivant); then
    echo "quickshell : deja lance (pid $_v), rien a faire" >&2
    exit 0
fi

# L'ancien verrou de vie (aethershell.shell.lock) ne sert plus à rien : il
# n'était tenu que par des descripteurs hérités. On retire le fichier du dossier
# de session — sans toucher aux orphelins qui le tiennent encore, un unlink ne
# les dérange pas.
rm -f "$r/aethershell.shell.lock" 2>/dev/null || true

# Le jeton porte le pid de ce lanceur : l'exec conserve le pid, donc il désigne
# le shell dès la première seconde et pendant toute sa vie. Tout lancement
# concurrent (l'autre chemin de démarrage) le lit et s'arrête là.
printf '%s %s\n' "$$" "$(depart_de $$)" > "$jeton" 2>/dev/null || true

while ! compositeur_vivant; do
    attente=$((attente + 1))
    if [ "$attente" -ge "$max" ]; then
        rm -f "$jeton" 2>/dev/null || true
        echo "quickshell : aucun compositeur ne repond dans $r apres ${max}s (session absente ou en cours de demarrage)" >&2
        exit 1
    fi
    sleep 1
done

export WAYLAND_DISPLAY="$socket"
# systemd --user n'exporte pas toujours XDG_SESSION_TYPE : certains wrappers
# Flatpak (ex. VSCodium) le testent explicitement et retombent sur X11 sinon.
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
if [ -n "$signature" ]; then
    export HYPRLAND_INSTANCE_SIGNATURE="$signature"
fi

# Sous verrou, dernière barrière : une instance a pu être lancée hors de ce
# script (à la main) pendant l'attente du compositeur. On note la sienne, pour
# que les lancements suivants la voient.
if _v=$(shell_deja_lance); then
    printf '%s %s\n' "$_v" "$(depart_de "$_v")" > "$jeton" 2>/dev/null || true
    echo "quickshell : une instance tourne deja (pid $_v), rien a faire" >&2
    exit 0
fi

# Le verrou est refermé ici, juste avant l'exec : rien de ce que le shell
# lancera ensuite (veilleurs, `pactl subscribe`, `inotifywait`) ne l'héritera,
# donc aucun orphelin ne pourra plus bloquer un redémarrage. La place est déjà
# tenue par le jeton, écrit plus haut, qui ne se transmet pas, lui.
exec 9>&-

exec quickshell -n "$@"
