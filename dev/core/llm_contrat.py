#!/usr/bin/env python3
"""Contrat d'affichage commun aux widgets de compte (« famille LLM »).

Un seul composant, `widgets/llm.qml`, rend DeepSeek, Ollama Cloud et Antigravity ;
il ne connaît aucun d'eux. Chaque service garde ses champs propres (`total`,
`windows`, `usage_7d`…) et y ajoute ce bloc, calculé ici :

    {"ok": true, "fournisseur": "Ollama Cloud", "icone": "cloud",
     "alerte": false,
     "mesures": [{"valeur": "$0.26",  "libelle": "Ollama Cloud", "fin": 0},
                 {"valeur": "$21.03", "libelle": "sur 7 j",      "fin": 0}]}

Règles que le widget applique, et qui suffisent aux trois cas :

  - `mesures[0]` est la grande ligne, `mesures[1:]` forment la petite ligne,
    séparées par « · » ;
  - `fin` (horodatage Unix) remplace la valeur par un décompte qui avance seul :
    c'est ce qu'on affiche quand on ne connaît qu'une échéance ;
  - `releve` (horodatage Unix) ne s'affiche pas : il dit quand relancer le
    service, parce que la valeur va changer à cet instant ;
  - `depuis` (horodatage passé) ajoute « il y a 1 h 12 » à la mesure — c'est ce
    qui donne un sens à « libre », qui sans ça n'informe de rien ;
  - `alerte` passe le texte en couleur d'avertissement ;
  - `icone` est un glyphe du singleton Icon du shell.

Sur échec, le bloc n'est pas ajouté : le widget affiche `error`, dont la
formulation reste celle du service (une clé absente et un réseau coupé ne se
réparent pas de la même façon).
"""
from __future__ import annotations

# Devise → symbole. Une devise inconnue s'affiche en clair plutôt que masquée.
SYMBOLES = {"USD": "$", "CNY": "¥", "EUR": "€", "GBP": "£"}


def montant(valeur, devise="USD"):
    """12.3 → « $12.30 » ; None → « — » (jamais « $None »)."""
    if valeur is None:
        return "—"
    try:
        nombre = float(valeur)
    except (TypeError, ValueError):
        return "—"
    return SYMBOLES.get(str(devise or "USD").upper(), "") + f"{nombre:.2f}"


def duree(secondes):
    """« 26 min », « 2h58 », « 2 j 02 » — le format suit la grandeur du délai."""
    s = int(max(0, secondes))
    jours, heures, minutes = s // 86400, (s % 86400) // 3600, (s % 3600) // 60
    if jours > 0:
        return f"{jours} j {heures:02d}"
    if heures > 0:
        return f"{heures}h{minutes:02d}"
    return f"{minutes} min"


def mesure(valeur="", libelle="", fin=0, depuis=0, texte="", releve=0):
    """Une ligne du widget : `valeur` en grand (si première), `libelle` en petit.

    `texte` est une phrase toute faite, prioritaire sur valeur/libelle : certaines
    mesures ne s'écrivent pas « valeur libelle » (Antigravity affiche
    « 5 h · Gemini 96 % », où le séparateur appartient à la donnée).
    """
    return {
        "valeur": "" if valeur is None else str(valeur),
        "libelle": "" if libelle is None else str(libelle),
        "texte": "" if texte is None else str(texte),
        "fin": int(fin or 0),
        "depuis": int(depuis or 0),
        # `releve` : instant où la valeur va changer. Le widget relance le service
        # à ce moment sans rien afficher ; `fin`, lui, remplace la valeur par un
        # décompte. Les deux existent parce qu'un « 0 % » et un « 2 j 01 » ne
        # disent pas la même chose du même instant.
        "releve": int(releve or 0),
    }


def presenter(donnees, fournisseur, icone, mesures, alerte=False):
    """Ajoute le bloc d'affichage à la réponse d'un service, sans la modifier."""
    if not donnees.get("ok"):
        return donnees
    donnees["fournisseur"] = fournisseur
    donnees["icone"] = icone
    donnees["mesures"] = [m for m in mesures if m]
    donnees["alerte"] = bool(alerte)
    return donnees


def sortir(donnees):
    """Unique sortie d'un service : le JSON, une ligne, avec le bloc d'affichage.

    Les services l'appellent à la place de `print(json.dumps(...))` pour que le
    contrat soit ajouté partout — y compris sur le cache et sur la valeur périmée,
    qui sont deux chemins de sortie faciles à oublier.
    """
    import json
    import sys
    print(json.dumps(donnees, ensure_ascii=False))
    sys.stdout.flush()
    return 0
