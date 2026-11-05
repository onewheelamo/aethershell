#!/usr/bin/env python3
"""Fournisseurs LLM connus — une entrée par service, lue par le panneau et les services.

`core/llm_providers.json` (fichier préservé au déploiement) décrit chaque
fournisseur :

    id        identifiant, aussi celui du widget et du service
    label     ce que le panneau affiche
    kind      balance | usage | local — ce que le service sait montrer
    base_url  adresse de l'API, modifiable (proxy, auto-hébergement)
    key       référence de la clé dans secrets.json (« section.nom »)
    service   script qui interroge le fournisseur (pour le test de clé)
    widget    type de widget associé
    hint      exemple de forme de clé, affiché dans le champ vide
    summary   une ligne sur ce que le widget montre

Ajouter un fournisseur = ajouter une entrée ici, plus son adaptateur : ni le
panneau ni le widget ne sont à réécrire. Un fichier absent ou illisible retombe
sur `DEFAUT`, pour qu'un `git clean` malheureux ne vide pas la section « Accès API ».
"""
from __future__ import annotations

import json
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROVIDERS_FILE = BASE_DIR / "llm_providers.json"
SECRETS_FILE = BASE_DIR / "secrets.json"

DEFAUT = [
    {
        "id": "deepseek", "label": "DeepSeek", "kind": "balance",
        "base_url": "https://api.deepseek.com", "key": "deepseek.api_key",
        "service": "core/deepseek_service.py", "widget": "deepseek",
        "hint": "sk-…", "summary": "solde de l'API",
    },
    {
        "id": "ollama", "label": "Ollama Cloud", "kind": "balance",
        "base_url": "https://ollama.com", "key": "ollama.api_key",
        "service": "core/ollama_service.py", "widget": "ollama",
        "hint": "clé de ollama.com", "summary": "solde restant et coût des 7 derniers jours",
    },
    {
        "id": "antigravity", "label": "Antigravity (Google AI Pro)", "kind": "quota",
        "base_url": "", "key": "", "service": "core/antigravity_service.py",
        "widget": "antigravity", "hint": "",
        "summary": "quota de l'abonnement, lu dans les logs du CLI — Gemini, Claude et GPT sous le même plafond",
    },
]


def charger():
    """{id: entrée} — fichier d'abord, liste par défaut en secours."""
    entrees = DEFAUT
    try:
        data = json.loads(PROVIDERS_FILE.read_text(encoding="utf-8"))
        items = data.get("providers") if isinstance(data, dict) else data
        if isinstance(items, list) and items:
            entrees = items
    except (OSError, ValueError):
        pass

    sortie = {}
    for entree in entrees:
        if isinstance(entree, dict) and str(entree.get("id") or "").strip():
            sortie[str(entree["id"]).strip()] = entree

    # Le fichier est préservé au déploiement : un fournisseur livré plus tard
    # (nouvelle version du shell) n'y apparaîtrait jamais tout seul. Les entrées
    # du fichier gardent la priorité — c'est lui que l'utilisateur édite — et
    # celles qui manquent sont complétées par la liste par défaut.
    for entree in DEFAUT:
        sortie.setdefault(str(entree["id"]), entree)
    return sortie


def entree(provider_id):
    return charger().get(str(provider_id)) or {}


def base_url(provider_id, defaut=""):
    valeur = str(entree(provider_id).get("base_url") or defaut).strip()
    return valeur.rstrip("/")


def reference_cle(provider_id, defaut=""):
    return str(entree(provider_id).get("key") or defaut).strip()


def cle(provider_id, variable_env=""):
    """Clé du fournisseur : secrets.json (`section.nom`) puis environnement."""
    reference = reference_cle(provider_id)
    section, _, nom = reference.partition(".")
    if section and nom:
        try:
            data = json.loads(SECRETS_FILE.read_text(encoding="utf-8"))
            valeur = (data or {}).get(section)
            if isinstance(valeur, dict):
                valeur = valeur.get(nom)
            trouvee = str(valeur or "").strip()
            if trouvee:
                return trouvee
        except (OSError, ValueError):
            pass
    return str(os.environ.get(variable_env) or "").strip() if variable_env else ""
