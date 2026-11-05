#!/usr/bin/env python3
"""Applet « Musique » : le morceau en cours dans la barre.

La barre montre le titre ; le popup de contrôle reste celui de l'îlot central
(`popup_cle: "media"`), qui pilote le joueur par MPRIS côté QML. Ce service ne
fait donc qu'une chose : dire quel morceau joue, et par qui.

Sans lecteur actif, la valeur est vide et l'applet disparaît — plutôt qu'un
tiret permanent dans la barre.
"""
from __future__ import annotations

import subprocess
import sys

from applet_contrat import compact, presenter, sortir

LONGUEUR_TITRE = 30
DELAI = 4


def _lire():
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
        lignes.append((statut, titre, artiste, lecteur))
    return lignes


def _court(texte, limite=LONGUEUR_TITRE):
    if len(texte) <= limite:
        return texte
    return texte[: limite - 1].rstrip() + "…"


def analyser():
    lignes = _lire()
    if not lignes:
        return {"ok": True, "compact": compact(""), "lecteur": ""}
    # Un lecteur qui joue l'emporte sur un lecteur en pause : c'est ce qu'on
    # cherche à voir dans la barre.
    jouant = [l for l in lignes if l[0].lower() == "playing"]
    statut, titre, artiste, lecteur = (jouant or lignes)[0]
    en_pause = statut.lower() != "playing"
    return {
        "ok": True,
        "compact": compact(_court(titre), artiste, alerte=False),
        "en_pause": en_pause,
        "lecteur": lecteur,
        "statut": statut,
    }


def main(argv):
    donnees = analyser()
    presenter(donnees, "musique", "music", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
