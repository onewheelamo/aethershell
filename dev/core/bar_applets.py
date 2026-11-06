#!/usr/bin/env python3
"""Registre des applets de la barre : catalogue (code) + état (utilisateur).

Deux fichiers, deux rôles :

  - `applets_catalogue.json` décrit les applets qui existent : nom, icône,
    service Python, popup QML, îlot et ordre par défaut. Il fait partie du code ;
  - `bar_applets.json` ne retient que ce que l'utilisateur a choisi : quels
    applets sont allumés, sur quel îlot, dans quel ordre, à quelle échelle de
    texte. Il est préservé au déploiement.

Un applet absent de `bar_applets.json` est **éteint** : les applets sont opt-in.
Et comme l'état est un dictionnaire `id → placement`, un applet ne peut pas
exister deux fois — le doublon entre deux îlots est impossible par construction,
pas par validation.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
CATALOGUE = ICI / "applets_catalogue.json"
ETAT = ICI / "bar_applets.json"

# Emplacements. Les trois premiers sont les sections de la barre du haut ; les
# suivants appartiennent aux barres optionnelles (bas, côtés).
ILES = ("haut-gauche", "haut-centre", "haut-droite", "bas", "cote-gauche", "cote-droite")
# Les anciens noms désignaient les sections de la barre du haut : on les traduit
# à la lecture, sinon un registre existant perdrait ses applets au premier
# démarrage (et l'utilisateur croirait les avoir éteints).
ANCIENS = {"gauche": "haut-gauche", "centre": "haut-centre", "droite": "haut-droite"}
ECHELLE_MIN, ECHELLE_MAX = 60, 160


def _lire(chemin, defaut):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return defaut


def _ecrire(chemin, donnees):
    """Écriture atomique : un shell qui relit pendant l'écriture ne voit jamais
    un fichier tronqué (le fichier de widgets a déjà souffert de ça)."""
    tmp = chemin.with_suffix(chemin.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(donnees, f, ensure_ascii=False, indent=4)
        f.write("\n")
    os.replace(tmp, chemin)


def catalogue():
    data = _lire(CATALOGUE, {})
    applets = data.get("applets") if isinstance(data, dict) else None
    return [a for a in (applets or []) if isinstance(a, dict) and a.get("id")]


def etat_utilisateur():
    data = _lire(ETAT, {})
    actifs = data.get("actifs") if isinstance(data, dict) else None
    if not isinstance(actifs, dict):
        return {}
    for placement in actifs.values():
        if isinstance(placement, dict) and placement.get("ile") in ANCIENS:
            placement["ile"] = ANCIENS[placement["ile"]]
    return actifs


def _entree(applet, choix=None):
    """Catalogue + choix de l'utilisateur, avec les valeurs par défaut."""
    choix = choix or {}
    entree = dict(applet)
    entree["actif"] = bool(choix)
    ile = str(choix.get("ile") or applet.get("ile") or "haut-droite")
    ile = ANCIENS.get(ile, ile)
    entree["ile"] = ile if ile in ILES else "haut-droite"
    try:
        entree["ordre"] = int(choix.get("ordre", applet.get("ordre", 100)))
    except (TypeError, ValueError):
        entree["ordre"] = 100
    try:
        echelle = int(choix.get("text_scale", applet.get("text_scale", 100)))
    except (TypeError, ValueError):
        echelle = 100
    entree["text_scale"] = max(ECHELLE_MIN, min(ECHELLE_MAX, echelle))
    entree["options"] = choix.get("options") or {}
    return entree


def resoudre(ile=None):
    """Les applets allumés, pour un îlot ou pour la barre entière."""
    choix = etat_utilisateur()
    actifs = [_entree(a, choix.get(a["id"])) for a in catalogue() if choix.get(a["id"])]
    if ile:
        actifs = [a for a in actifs if a["ile"] == ile]
    return sorted(actifs, key=lambda a: (ILES.index(a["ile"]), a["ordre"], a["id"]))


def etat_complet():
    """Ce que le panneau affiche : tout le catalogue, allumé ou non."""
    choix = etat_utilisateur()
    return [_entree(a, choix.get(a["id"])) for a in catalogue()]


def _exiger(applet_id):
    for a in catalogue():
        if a["id"] == applet_id:
            return a
    raise SystemExit(f"applet inconnu : {applet_id} (connus : "
                     + ", ".join(a["id"] for a in catalogue()) + ")")


def activer(applet_id, ile=None):
    """Allume un applet, sur son îlot par défaut s'il n'est pas précisé.

    S'il était déjà allumé ailleurs, c'est un **déplacement** : l'état est un
    dictionnaire, donc l'ancien emplacement est remplacé, jamais dupliqué.
    """
    applet = _exiger(applet_id)
    etat = etat_utilisateur()
    courant = etat.get(applet_id) or {}
    ile = ile or courant.get("ile") or applet.get("ile") or "droite"
    if ile not in ILES:
        raise SystemExit(f"îlot inconnu : {ile} (attendu : {', '.join(ILES)})")
    etat[applet_id] = {
        "ile": ile,
        "ordre": courant.get("ordre", applet.get("ordre", 100)),
        "text_scale": courant.get("text_scale", applet.get("text_scale", 100)),
        "options": courant.get("options") or {},
    }
    _ecrire(ETAT, {"version": 1, "actifs": etat})


def desactiver(applet_id):
    etat = etat_utilisateur()
    etat.pop(applet_id, None)
    _ecrire(ETAT, {"version": 1, "actifs": etat})


# Une barre éteinte rendrait l'applet invisible : placer dans « bas » ou sur un
# côté allume la barre correspondante. Le faire ici couvre tous les chemins
# (panneau, ligne de commande, réparation), pas seulement les clics du panneau.
BARRE_STYLE = {"bas": "bar_bottom", "cote-gauche": "bar_left", "cote-droite": "bar_right"}


def _allumer_barre(ile):
    cle = BARRE_STYLE.get(ile)
    if not cle:
        return
    chemin = ICI / "style_vars.json"
    etat = _lire(chemin, {})
    if not isinstance(etat, dict) or etat.get(cle) is True:
        return
    etat[cle] = True
    _ecrire(chemin, etat)


def placer(applet_id, ile):
    _exiger(applet_id)
    if ile not in ILES:
        raise SystemExit(f"îlot inconnu : {ile} (attendu : {', '.join(ILES)})")
    _allumer_barre(ile)
    etat = etat_utilisateur()
    if applet_id not in etat:
        activer(applet_id, ile)
        return
    etat[applet_id]["ile"] = ile
    _ecrire(ETAT, {"version": 1, "actifs": etat})


def ordonner(applet_id, ordre):
    etat = etat_utilisateur()
    if applet_id not in etat:
        raise SystemExit(f"applet éteint : {applet_id}")
    try:
        etat[applet_id]["ordre"] = int(ordre)
    except (TypeError, ValueError):
        raise SystemExit("ordre attendu : un entier")
    _ecrire(ETAT, {"version": 1, "actifs": etat})


def echelle(applet_id, pourcentage):
    etat = etat_utilisateur()
    if applet_id not in etat:
        raise SystemExit(f"applet éteint : {applet_id}")
    try:
        valeur = int(pourcentage)
    except (TypeError, ValueError):
        raise SystemExit("échelle attendue : un entier (60 à 160)")
    etat[applet_id]["text_scale"] = max(ECHELLE_MIN, min(ECHELLE_MAX, valeur))
    _ecrire(ETAT, {"version": 1, "actifs": etat})


def deplacer(applet_id, sens):
    """Échange la place avec l'applet voisin du même îlot.

    L'ordre affiché est celui des `ordre` croissants. Deux applets peuvent porter
    le même ordre (catalogue recopié à la main) : on renumérote donc l'îlot en
    10, 20, 30… avant d'échanger, sinon l'échange ne changerait rien à l'écran.
    """
    etat = etat_utilisateur()
    if applet_id not in etat:
        raise SystemExit(f"applet éteint : {applet_id}")
    ile = (etat[applet_id] or {}).get("ile")
    voisins = sorted(
        ((int((a or {}).get("ordre", 100)), k) for k, a in etat.items()
         if (a or {}).get("ile") == ile),
        key=lambda t: (t[0], t[1]),
    )
    ids = [k for _, k in voisins]
    i = ids.index(applet_id)
    j = i + int(sens)
    if j < 0 or j >= len(ids):
        return etat  # déjà au bout de l'îlot
    ordres = {k: (n + 1) * 10 for n, k in enumerate(ids)}
    ordres[ids[i]], ordres[ids[j]] = ordres[ids[j]], ordres[ids[i]]
    for k, o in ordres.items():
        etat[k]["ordre"] = o
    _ecrire(ETAT, {"version": 1, "actifs": etat})
    return etat


def option(applet_id, cle, valeur):
    """Change une option d'applet (ex. quelles mesures montrer).

    La valeur est lue comme du JSON quand elle en est (« ["cpu","ram"] »), sinon
    gardée en chaîne : le panneau et le popup peuvent ainsi écrire une liste
    sans avoir à connaître le format.
    """
    etat = etat_utilisateur()
    if applet_id not in etat:
        raise SystemExit(f"applet éteint : {applet_id}")
    try:
        valeur = json.loads(valeur)
    except ValueError:
        pass
    options = etat[applet_id].get("options") or {}
    options[str(cle)] = valeur
    etat[applet_id]["options"] = options
    _ecrire(ETAT, {"version": 1, "actifs": etat})


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    action = argv[1]
    if action == "state":
        print(json.dumps(etat_complet(), ensure_ascii=False))
        return 0
    if action == "resoudre":
        print(json.dumps(resoudre(argv[2] if len(argv) > 2 else None),
                         ensure_ascii=False))
        return 0
    if action == "activer" and len(argv) > 2:
        activer(argv[2], argv[3] if len(argv) > 3 else None)
    elif action == "desactiver" and len(argv) > 2:
        desactiver(argv[2])
    elif action == "placer" and len(argv) > 3:
        placer(argv[2], argv[3])
    elif action == "ordre" and len(argv) > 3:
        ordonner(argv[2], argv[3])
    elif action == "echelle" and len(argv) > 3:
        echelle(argv[2], argv[3])
    elif action in ("monter", "descendre") and len(argv) > 2:
        deplacer(argv[2], -1 if action == "monter" else 1)
    elif action == "option" and len(argv) > 4:
        option(argv[2], argv[3], " ".join(argv[4:]))
    else:
        print(__doc__)
        return 2
    print(json.dumps(etat_complet(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
