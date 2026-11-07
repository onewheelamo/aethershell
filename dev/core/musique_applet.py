#!/usr/bin/env python3
"""Applet « Musique » : le morceau en cours dans la barre.

La barre montre le titre ; le popup de contrôle reste celui de l'îlot central
(`popup_cle: "media"`), qui pilote le joueur par MPRIS côté QML. Ce service ne
fait donc qu'une chose : dire quel morceau joue, et par qui.

Sans lecteur actif, la valeur est vide et l'applet disparaît — plutôt qu'un
tiret permanent dans la barre.
"""
from __future__ import annotations

import json
import subprocess
import sys

from applet_contrat import compact, presenter, sortir

DELAI = 4

# Lecteurs qui ne sont pas des lecteurs de musique : un onglet Firefox qui joue
# une vidéo n'est pas « le morceau en cours ». L'option permet de les suivre
# quand même (radio dans le navigateur, par exemple).
#
# `plasma-browser-integration` est le pont KDE : il publie le même média que
# l'onglet, sous un nom qui ne contient aucun nom de navigateur — c'est lui qui
# laissait passer une vidéo YouTube dans la barre, Firefox étant pourtant filtré.
# Le motif `browser` couvre les ponts du même genre ; un futur pont se reconnaît
# à son nom, et c'est cette liste qu'il faudra compléter.
NAVIGATEURS = ("firefox", "zen", "chromium", "chrome", "brave", "vivaldi",
               "opera", "edge", "librewolf", "waterfox",
               "plasma-browser-integration", "browser")


def _vrai(valeur, defaut=True):
    if isinstance(valeur, bool):
        return valeur
    if valeur is None:
        return defaut
    return str(valeur).strip().lower() not in ("false", "0", "non", "")


def _est_navigateur(lecteur):
    bas = str(lecteur or "").lower()
    return any(n in bas for n in NAVIGATEURS)


def _lire(ignorer_navigateurs=True):
    """[(statut, titre, artiste, lecteur)] — une ligne par lecteur MPRIS."""
    try:
        res = subprocess.run(
            ["playerctl", "-a", "metadata", "--format",
             "{{status}}\t{{title}}\t{{artist}}\t{{playerName}}"],
            capture_output=True, text=True, timeout=DELAI,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    lignes = []
    for brute in res.stdout.splitlines():
        morceaux = brute.split("\t")
        if len(morceaux) < 3:
            continue
        statut = morceaux[0].strip()
        titre = morceaux[1].strip()
        artiste = morceaux[2].strip()
        lecteur = morceaux[3].strip() if len(morceaux) > 3 else ""
        if titre == "":
            continue
        if ignorer_navigateurs and _est_navigateur(lecteur):
            continue
        lignes.append((statut, titre, artiste, lecteur))
    return lignes


def analyser(options=None):
    lignes = _lire(_vrai((options or {}).get("ignorer_navigateurs"), True))
    if not lignes:
        return {"ok": True, "compact": compact(""), "lecteur": ""}
    # Un lecteur qui joue l'emporte sur un lecteur en pause : c'est ce qu'on
    # cherche à voir dans la barre.
    jouant = [l for l in lignes if l[0].lower() == "playing"]
    statut, titre, artiste, lecteur = (jouant or lignes)[0]
    en_pause = statut.lower() != "playing"
    return {
        "ok": True,
        # Le titre part entier : c'est le texte de barre (`Defilement.qml`) qui
        # borne la largeur et le fait défiler. Tronquer ici coupait l'information
        # avant même que l'affichage puisse la donner.
        "compact": compact(titre, artiste, alerte=False),
        "en_pause": en_pause,
        "lecteur": lecteur,
        "statut": statut,
    }


def main(argv):
    options = {}
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                options = json.loads(arg.split("=", 1)[1])
            except ValueError:
                options = {}
    donnees = analyser(options=options)
    presenter(donnees, "musique", "music", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
