#!/bin/bash
# Script de bascule manuelle pour l'écran eDP-1 (portable convertible)

STATE=$(hyprctl monitors | grep -i "eDP-1")

if [ -z "$STATE" ]; then
    hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = false, mode = "preferred", position = "auto", scale = 1, transform = 0 })'
else
    hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'
fi
