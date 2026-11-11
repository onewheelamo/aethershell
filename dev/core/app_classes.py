#!/usr/bin/env python3
"""Icône et nom lisible d'une fenêtre, à partir de sa classe Hyprland.

Une classe de fenêtre (`org.kde.kate`, `com.mitchellh.ghostty`) n'est pas un nom
d'icône : elle ne coïncide avec une entrée .desktop que par hasard. Ce module
porte la **seule** règle de rapprochement classe ↔ .desktop, partagée par le
double clic du systray (`tray_apps.py`) et par l'applet des fenêtres minimisées.
Une seconde copie de cette règle divergerait au premier correctif.

    python3 app_classes.py --classes=org.kde.kate,firefox
    → {"org.kde.kate": {"icone": "kate", "nom": "Kate", "desktop": "org.kde.kate.desktop"},
       "firefox": {"icone": "firefox", "nom": "Firefox", "desktop": "firefox.desktop"}}

Une classe inconnue rend une entrée vide (`icone: ""`) : c'est au QML de
retomber sur `Quickshell.hasThemeIcon(classe)`, puis sur une icône générique.
Ce module nomme, il ne résout pas les thèmes.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

INDEX = Path(__file__).resolve().parent / "app_index.json"

# Mots qui ne distinguent rien : ils figurent dans presque tous les identifiants
# d'items SNI et dans presque tous les noms de .desktop.
BRUIT = {
    "status", "icon", "indicator", "item", "app", "gtk", "qt", "desktop",
    "tray", "menu", "main", "the", "and",
}


def jetons(texte):
    """Ensemble de mots signifiants d'un identifiant, d'un titre ou d'une classe."""
    if not texte:
        return set()
    nu = re.sub(r"[^a-z0-9]+", " ", str(texte).lower())
    return {j for j in nu.split() if len(j) > 1 and j not in BRUIT}


def couvre(recherche, candidat):
    """Tous les jetons cherchés se retrouvent-ils dans le candidat ?

    Égalité de jeton, ou l'un contenu dans l'autre : `vpn` doit reconnaître la
    classe `protonvpn` (pas de séparateur), et `kate` la classe `org.kde.kate`.
    Le test est « tous les jetons », pas un score : `Proton Pass` ne doit pas
    tomber sur la fenêtre de Proton VPN sous prétexte qu'ils partagent
    `proton`.
    """
    if not recherche or not candidat:
        return False
    for j in recherche:
        if not any(j == c or (min(len(j), len(c)) >= 3 and (j in c or c in j))
                   for c in candidat):
            return False
    return True


def entrees():
    """Index des applications (écrit par `app_index.py`)."""
    try:
        donnees = json.loads(INDEX.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    return donnees if isinstance(donnees, list) else []


def _compresse(texte):
    """Forme collée d'un nom : minuscules alphanumériques, sans séparateur.

    `com.mitchellh.ghostty` → `commitchellighostty`, `ghostty` → `ghostty`. C'est
    ce qui reconnaît une classe préfixée par son éditeur sans rapprocher deux
    applications qui partagent seulement `com` ou `org`.
    """
    return re.sub(r"[^a-z0-9]+", "", str(texte or "").lower())


def _appariement(recherche, candidat):
    """Qualité du rapprochement entre les jetons cherchés et ceux d'un nom.

    Rend 0 (même ensemble), 1 (tous les jetons cherchés, mot pour mot), 2
    (seulement par contenance, avec au moins quatre caractères communs) ou None.
    La contenance courte est refusée : `kdenlive` contient `kde` et tombait donc
    sur `org.kde.ark.desktop`.
    """
    if not recherche or not couvre(recherche, candidat):
        return None
    if recherche == candidat:
        return 0
    verbatim = True
    contenu = False
    for j in recherche:
        if j not in candidat:
            verbatim = False
            if not any(min(len(j), len(c)) >= 4 and (j in c or c in j) for c in candidat):
                return None
            contenu = True
    return 1 if verbatim else (2 if contenu else None)


def entree_pour_classe(classe, index=None):
    """Entrée .desktop qui décrit cette classe de fenêtre, ou None.

    Deux passes : la règle par jetons (celle du systray, `couvre`), puis le nom
    collé, qui rattrape les classes préfixées par l'éditeur — `org.kde.kate`
    contre `kate.desktop`, `com.mitchellh.ghostty` contre `ghostty.desktop`.
    Le repli exige un recouvrement d'au moins quatre caractères : sans cette
    borne, `com.spotify.Client` tombait sur `com.opera.Opera` par le seul mot
    `com`.
    """
    liste = index if index is not None else entrees()
    distinctifs = {j for j in jetons(classe) if len(j) >= 3}
    if distinctifs:
        # Le nom exact d'abord, puis celui qui ajoute le moins de mots :
        # `thunar` doit tomber sur `thunar.desktop`, pas sur
        # `thunar-volman-settings.desktop`, qui le contient aussi.
        candidats = []
        for e in liste:
            stem = jetons(str(e.get("desktop", "")).removesuffix(".desktop"))
            niveau = _appariement(distinctifs, stem)
            if niveau is not None:
                candidats.append((niveau, len(stem - distinctifs), len(stem), e))
        if candidats:
            candidats.sort(key=lambda t: (t[0], t[1], t[2]))
            return candidats[0][3]

    colle = _compresse(classe)
    if len(colle) < 4:
        return None
    meilleur, longueur = None, 0
    for e in liste:
        stem = _compresse(e.get("desktop", ""))
        court, long = (stem, colle) if len(stem) <= len(colle) else (colle, stem)
        if len(court) >= 4 and court in long and len(court) > longueur:
            meilleur, longueur = e, len(court)
    return meilleur


def decrire(classe, index=None):
    """{icone, nom, desktop} pour une classe de fenêtre (champs vides si inconnue)."""
    entree = entree_pour_classe(classe, index)
    if not entree:
        return {"icone": "", "nom": "", "desktop": ""}
    return {
        "icone": str(entree.get("icon", "") or ""),
        "nom": str(entree.get("name", "") or ""),
        "desktop": str(entree.get("desktop", "") or ""),
    }


def main(argv):
    classes = []
    for a in argv:
        if a.startswith("--classes="):
            classes = [c.strip() for c in a.split("=", 1)[1].split(",") if c.strip()]
    if not classes:
        print(__doc__.strip().splitlines()[-4], file=sys.stderr)
        return 2
    index = entrees()
    print(json.dumps({c: decrire(c, index) for c in classes}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
