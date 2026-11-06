#!/usr/bin/env python3
"""Applet « Calendrier » : la date dans la barre.

Le panneau (mois, agenda du jour, ajout d'événement, Nextcloud) reste celui de
l'îlot central (`popup_cle: "calendar"`) : le migrer aurait voulu dire déplacer
six cents lignes de QML pour un résultat identique.

La barre n'affiche **que la date** (« ven. 6 nov. »). Auparavant l'applet y
mettait le prochain rendez-vous du jour, tronqué à 24 caractères : un intitulé
coupé prenait la place de l'heure sans dire de quel jour il parlait, et le
panneau — qui lit Nextcloud directement — le redit mieux au clic. L'applet
n'interroge donc plus Nextcloud du tout, et ne coûte plus qu'un calcul de date.
"""
from __future__ import annotations

import datetime
import sys

from applet_contrat import compact, presenter, sortir

JOURS = ("lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim.")
MOIS = ("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août",
        "sept.", "oct.", "nov.", "déc.")


def date_courte(moment=None):
    m = moment or datetime.datetime.now()
    return f"{JOURS[m.weekday()]} {m.day} {MOIS[m.month - 1]}"


def analyser(force=False):
    """`force` reste accepté : le shell l'ajoute (`--force`) à l'ouverture d'un
    popup et à chaque cadence. Il ne change plus rien, le calcul étant immédiat.
    """
    maintenant = datetime.datetime.now()
    valeur = date_courte(maintenant)
    return {
        "ok": True,
        "ts": maintenant.timestamp(),
        "compact": compact(valeur, ""),
        "date": valeur,
        "genre": "",
        "source": "date",
    }


def main(argv):
    force = "--force" in argv
    donnees = analyser(force=force)
    presenter(donnees, "calendrier", "calendar", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
