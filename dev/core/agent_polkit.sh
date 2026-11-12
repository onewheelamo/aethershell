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
# Ordre : hyprpolkitagent, KDE, MATE, GNOME, LXQt — le premier installe gagne.
# Code de sortie 0 dans tous les cas : une session sans agent n'est pas une
# erreur d'autostart, et ne doit pas faire de bruit dans le journal.
set -u

deja_lance() {
    for motif in polkit-kde-authentication-agent-1 \
                 hyprpolkitagent \
                 polkit-mate-authentication-agent-1 \
                 polkit-gnome-authentication-agent-1 \
                 lxqt-policykit-agent; do
        pgrep -f "$motif" >/dev/null 2>&1 && return 0
    done
    return 1
}

# --force : l'unité systemd veut un agent dans *sa* session, même si un autre
# agent tourne ailleurs (le garde regarde tout le système, pas une session).
if [ "${1:-}" != "--force" ]; then
    deja_lance && exit 0
fi

for agent in \
    /usr/lib/hyprpolkitagent/hyprpolkitagent \
    /usr/libexec/hyprpolkitagent \
    /usr/libexec/kf6/polkit-kde-authentication-agent-1 \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-mate-authentication-agent-1 \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/lxqt-policykit-agent \
    /usr/lib/lxqt-policykit-agent
do
    if [ -x "$agent" ]; then
        exec "$agent"
    fi
done

exit 0
