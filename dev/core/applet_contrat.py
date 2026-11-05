#!/usr/bin/env python3
"""Contrat d'affichage commun aux applets de la barre.

Un applet est une chose que la barre montre en une ligne : une icône et **une**
valeur compacte. Le détail (tableau, liste, historique) va dans le popup, qui
reçoit le même JSON. Un applet n'est donc ni un widget flottant ni un bouton
écrit à la main : c'est un service qui rend ce contrat, et un composant qui le
dessine.

    {"ok": true,
     "applet": "comptes",
     "icone": "wallet",
     "compact": {"valeur": "0 %", "libelle": "Claude"},
     "alerte": true,
     "mesures": [...],      # détail, rendu par le popup (facultatif)
     "lignes": [...]}       # détail tabulaire (facultatif)

Règles, identiques à celles des widgets de compte (core/llm_contrat.py, dont ce
module reprend `montant` et `duree`) :

  - `compact.valeur` est la seule chose qui s'affiche dans la barre : elle doit
    tenir en quelques caractères. C'est au service de choisir ce qui compte
    (« pire quota », « prochain rendez-vous », « 42 % ») ;
  - `compact.libelle` est un repli pour l'infobulle, jamais dans la barre ;
  - `alerte` passe l'applet en couleur d'avertissement, dans la barre comme dans
    le popup ;
  - `icone` est un glyphe du singleton Icon du shell ;
  - en cas d'échec, `ok` est faux et `error` porte la formulation du service :
    l'applet affiche « — », jamais une valeur inventée.
"""
from __future__ import annotations

import json
import sys

# Les formats (« $12.30 », « 2h58 ») ne sont pas réinventés ici : les applets qui
# manipulent de l'argent ou des délais importent ceux des widgets de compte.
from llm_contrat import duree, montant  # noqa: F401  (réexportés pour les applets)


def compact(valeur="", libelle="", alerte=False, fin=0, barres=None):
    """La ligne de barre. `fin` (Unix) remplace la valeur par un décompte.

    `barres` est réservé aux applets qui mesurent plusieurs choses à la fois
    (l'applet système) : une liste de jauges, chacune avec sa icône, son
    remplissage 0-100, son texte et son niveau ("ok", "attention", "critique").
    Quand la liste n'est pas vide, le rendu dessine les jauges et ignore
    `valeur`.
    """
    donnees = {
        "valeur": "" if valeur is None else str(valeur),
        "libelle": "" if libelle is None else str(libelle),
        "alerte": bool(alerte),
        "fin": int(fin or 0),
    }
    if barres:
        donnees["barres"] = barres
    return donnees


def presenter(donnees, applet, icone, ligne, mesures=None, lignes=None, alerte=None,
              source=None):
    """Ajoute le bloc d'affichage à la réponse d'un service, sans la modifier.

    `alerte` explicite l'emporte sur celle du compact : un service peut signaler
    l'alerte sur le détail sans la vouloir dans la barre, et l'inverse.
    """
    if not donnees.get("ok"):
        return donnees
    donnees["applet"] = applet
    donnees["icone"] = icone
    donnees["compact"] = ligne if ligne is not None else compact()
    if mesures is not None:
        donnees["mesures"] = [m for m in mesures if m]
    if lignes is not None:
        donnees["lignes"] = [l for l in lignes if l]
    if alerte is not None:
        donnees["alerte"] = bool(alerte)
    elif "alerte" not in donnees:
        donnees["alerte"] = bool(donnees["compact"].get("alerte"))
    if source is not None:
        donnees["source"] = str(source)
    return donnees


def sortir(donnees):
    """Unique sortie d'un service d'applet : le JSON, une ligne."""
    print(json.dumps(donnees, ensure_ascii=False))
    sys.stdout.flush()
    return 0


# ── sortie compacte pour le mode « pas de données » ────────────────────────────
def indisponible(applet, message):
    """Réponse d'échec minimale : l'applet affiche « — » et garde son icône."""
    return sortir({"ok": False, "applet": applet, "error": str(message)})
