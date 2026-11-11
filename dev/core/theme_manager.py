#!/usr/bin/env python3
"""Bascule de palette demandée par le panneau (et par l'IPC).

Une seule implémentation, dans `themes_scan.activer` : c'est lui qui sait si la
palette demandée est écrite à la main dans `style_vars.json` ou si elle vient du
catalogue lu sur le disque, et qui recopie les couleurs de l'active dans la
configuration (rofi, terminal et SDDM lisent tous `palette[active_theme]`).

Ce script ne faisait que vérifier `theme_name in palette` : depuis que les
schémas importés vivent dans le cache et non plus dans la configuration, il
aurait refusé tous les thèmes du disque.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import themes_scan  # noqa: E402


def set_theme(theme_name):
    try:
        themes_scan.activer(theme_name)
        return True
    except SystemExit as e:
        print(e)
        return False


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(0 if set_theme(sys.argv[1]) else 1)
