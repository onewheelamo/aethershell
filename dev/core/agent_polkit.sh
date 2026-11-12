#!/bin/sh
# Lance l'agent polkit de la session, s'il n'y en a pas deja un.
#
# Pourquoi un fichier et non une ligne `sh -c` : le garde `pgrep -f "(polkit-...)"`
# ecrit dans la ligne se reconnaissait lui-meme — le motif figurait dans sa propre
# ligne de commande — donc le garde repondait « deja lance », sortait en 0, et
# l'agent n'etait jamais demarre. Sans agent, `pkexec` ne peut pas demander
# l'autorisation : les actions du shell qui ecrivent dans /sys (limite de charge
# a 80 %) echouaient sans un mot. Ici le motif vit dans un fichier, plus dans la
# ligne de commande : le garde ne peut plus se confondre avec l'agent.
#
# Le garde compare les **sessions**, pas le systeme entier : polkit ne presente un
# agent qu'aux appelants de sa session, et deux agents dans la meme session se
# disputeraient l'invite. Sur une machine ou Hyprland demarre depuis un TTY, le
# compositeur et quickshell (systemd --user) vivent dans deux sessions : un agent
# lance par l'autostart n'y sert a rien pour les applets, et le garde ne doit pas
# le prendre pour « deja lance ».
#
# Ordre : KDE d'abord (c'est celui qui fonctionne sur les deux machines),
# hyprpolkitagent en dernier — il part en SIGSEGV sous systemd --user quand il ne
# trouve pas de compositeur dans son environnement.
# Code de sortie 0 dans tous les cas : une session sans agent n'est pas une
# erreur d'autostart, et ne doit pas faire de bruit dans le journal.
set -u

SESSION_MOI=$(cat "/proc/$$/sessionid" 2>/dev/null || echo "")

deja_lance() {
    p=""
    for motif in polkit-kde-authentication-agent-1 \
                 polkit-mate-authentication-agent-1 \
                 polkit-gnome-authentication-agent-1 \
                 lxqt-policykit-agent \
                 hyprpolkitagent; do
        for p in $(pgrep -f "$motif" 2>/dev/null); do
            [ "$p" = "$$" ] && continue
            if [ -n "$SESSION_MOI" ] && [ -r "/proc/$p/sessionid" ] \
               && [ "$(cat "/proc/$p/sessionid" 2>/dev/null)" = "$SESSION_MOI" ]; then
                return 0
            fi
        done
    done
    return 1
}

deja_lance && exit 0

for agent in \
    /usr/libexec/kf6/polkit-kde-authentication-agent-1 \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-mate-authentication-agent-1 \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/lxqt-policykit-agent \
    /usr/lib/lxqt-policykit-agent \
    /usr/lib/hyprpolkitagent/hyprpolkitagent \
    /usr/libexec/hyprpolkitagent
do
    if [ -x "$agent" ]; then
        exec "$agent"
    fi
done

exit 0
