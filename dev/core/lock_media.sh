#!/usr/bin/env sh
# Ligne média de l'écran de verrouillage : « artiste — titre », jamais les paroles.
#
# Pourquoi un script : hyprlock passe le texte des labels par hyprlang, qui
# interprète `{{…}}` comme une expression arithmétique et rejette la ligne
# (« Invalid expression type »). Le format Go de playerctl ne peut donc pas être
# écrit dans hyprlock.conf ; il vit ici.
#
# Sortie vide quand aucun lecteur ne joue : le label reste alors vide au lieu
# d'afficher « Sample Text ».

a="$(playerctl metadata artist 2>/dev/null)"
t="$(playerctl metadata title 2>/dev/null)"

if [ -n "$a" ] && [ -n "$t" ]; then
    printf '%s — %s' "$a" "$t"
elif [ -n "$t" ]; then
    printf '%s' "$t"
elif [ -n "$a" ]; then
    printf '%s' "$a"
fi
