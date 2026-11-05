#!/usr/bin/env python3
"""Solde et consommation de l'API Ollama Cloud.

    ollama_service.py [--force]

Une ligne JSON sur stdout, rien d'autre :

    {"ok": true, "currency": "USD", "total": 0.26, "included": 0.0,
     "allowance": 2.5, "purchased": 0.26, "reset_at": "2026-11-26T11:37:08Z",
     "usage_7d": 21.03, "requests_7d": 7931, "ts": 1699..., "cached": false}

Deux points d'entrée, tous deux sur `ollama.com` — le démon local
(`localhost:11434`) ne connaît que les modèles installés, il n'a rien à dire sur
un compte cloud :

    GET /api/balance          enveloppe incluse (`balance_usd` restant sur
                             `allowance_usd`, avec la date de remise à zéro) et
                             crédits achetés ;
    GET /api/usage?range=7d   coût réel des sept derniers jours.

Le solde affiché est la somme des deux postes (inclus restant + achetés) : c'est
ce qu'il reste à dépenser. « 0.00 sur 2.50 » veut dire que l'enveloppe du mois
est consommée et qu'on puise dans les crédits achetés — ce que le widget doit
montrer avant qu'il ne reste plus rien.

La clé est lue dans `core/secrets.json` (`ollama.api_key`, fichier préservé au
déploiement) ou, à défaut, dans l'environnement (`OLLAMA_API_KEY`). Rien n'est
journalisé : la clé ne sort pas de ce script.

Cache de 5 minutes dans `core/ollama_cache.json` : le widget interroge le
service à son rythme et le cache sert la dernière valeur connue (`cached: true`)
quand le réseau tombe. L'API limite à 10 requêtes par minute et par compte, tous
postes confondus — deux appels par rafraîchissement, la marge est large.

L'usage est *non bloquant* : si `/api/usage` échoue alors que le solde répond, la
ligne de consommation disparaît (`usage_7d: null`) et le widget affiche le solde
seul, plutôt que de tout perdre pour une statistique.

Sortie en cas d'échec du solde : {"ok": false, "error": "..."} avec un code de
retour 0 — le widget affiche alors la raison plutôt que de disparaître.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
CACHE_FILE = BASE_DIR / "ollama_cache.json"

sys.path.insert(0, str(BASE_DIR))
import llm_contrat  # noqa: E402
import llm_providers  # noqa: E402

SEUIL_BAS = 1.0        # sous 1 $, il reste moins d'une heure de consommation

API_BASE = llm_providers.base_url("ollama", "https://ollama.com") + "/api"
PLAGE = "7d"
TTL = 300
TIMEOUT = 8


def cle_api():
    """Clé de l'API : secrets.json d'abord, environnement ensuite."""
    return llm_providers.cle("ollama", "OLLAMA_API_KEY")


def lire_cache():
    try:
        return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def ecrire_cache(donnees):
    try:
        CACHE_FILE.write_text(json.dumps(donnees, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError:
        pass


def interroger(chemin, cle, parametres=None):
    url = API_BASE + chemin
    if parametres:
        url += "?" + urllib.parse.urlencode(parametres)
    requete = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {cle}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(requete, timeout=TIMEOUT) as reponse:
        return json.loads(reponse.read().decode("utf-8", errors="replace"))


def message_erreur(erreur):
    if isinstance(erreur, urllib.error.HTTPError):
        if erreur.code == 401:
            return "clé refusée"
        if erreur.code == 429:
            return "limite d'appels (429)"
        if erreur.code == 403:
            return "accès refusé"
        return f"HTTP {erreur.code}"
    if isinstance(erreur, urllib.error.URLError):
        return f"réseau : {erreur.reason}"
    return str(erreur)[:120]


def nombre(valeur):
    """Convertit un champ monétaire de l'API ; `None` si absent ou illisible."""
    try:
        return float(valeur)          # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def solde(cle):
    charge = interroger("/balance", cle)
    inclus_bloc = charge.get("included") or {}
    achat_bloc = charge.get("purchased") or {}

    inclus = nombre(inclus_bloc.get("balance_usd")) or 0.0
    achat = nombre(achat_bloc.get("balance_usd")) or 0.0
    enveloppe = nombre(inclus_bloc.get("allowance_usd"))
    periode = inclus_bloc.get("period") or {}

    # Certains plans n'ont pas d'enveloppe mensuelle mais des fenêtres en
    # pourcentage (session / semaine) : on les remonte telles quelles plutôt que
    # d'inventer un montant.
    fenetres = {}
    for nom in ("session", "weekly"):
        bloc = inclus_bloc.get(nom)
        if isinstance(bloc, dict) and bloc.get("remaining_percent") is not None:
            try:
                fenetres[nom] = {
                    "percent": int(round(float(bloc.get("remaining_percent")))),
                    "resets_at": bloc.get("resets_at"),
                }
            except (TypeError, ValueError):
                pass

    return {
        "ok": True,
        "provider": "ollama",
        "currency": "USD",
        "total": round(inclus + achat, 2),
        "included": round(inclus, 2),
        "allowance": None if enveloppe is None else round(float(enveloppe), 2),
        "purchased": round(achat, 2),
        "reset_at": periode.get("until"),
        "windows": fenetres or None,
    }


def consommation(cle):
    """Coût des sept derniers jours. Non bloquant : lève, l'appelant décide."""
    charge = interroger("/usage", cle, {"range": PLAGE})
    totaux = charge.get("totals") or {}
    return {
        "usage_7d": round(float(totaux.get("usage_usd") or 0), 2),
        "requests_7d": int(totaux.get("request_count") or 0),
    }


def presenter(donnees):
    """Bloc d'affichage : le solde en grand, le rythme des 7 jours en petit.

    Les deux chiffres répondent à deux questions différentes — « combien puis-je
    encore dépenser » et « à quel rythme », un solde seul ne dit pas s'il tiendra
    la semaine. Le rythme manque quand `/api/usage` a échoué : on l'omet plutôt
    que d'afficher un zéro qui ferait croire à une consommation nulle.
    """
    if not donnees.get("ok"):
        return donnees
    total = float(donnees.get("total") or 0)
    if total <= 0:
        libelle, alerte = "crédit épuisé · Ollama Cloud", True
    elif total < SEUIL_BAS:
        libelle, alerte = "à recharger · Ollama Cloud", True
    else:
        libelle, alerte = "Ollama Cloud", False

    mesures = [llm_contrat.mesure(llm_contrat.montant(total), libelle)]
    conso = donnees.get("usage_7d")
    if conso is not None:
        mesures.append(llm_contrat.mesure(llm_contrat.montant(conso), "sur 7 j"))
    return llm_contrat.presenter(donnees, "Ollama Cloud", "cloud", mesures, alerte)


def main(argv):
    force = "--force" in argv

    cache = lire_cache()
    if cache and not force and (time.time() - int(cache.get("ts") or 0)) < TTL:
        # Simple lecture du cache : la valeur est fraîche, elle n'a rien de périmé.
        cache["cached"] = True
        cache.pop("stale_reason", None)
        return llm_contrat.sortir(presenter(cache))

    cle = cle_api()
    if not cle:
        if cache:
            cache["cached"] = True
            return llm_contrat.sortir(presenter(cache))
        return llm_contrat.sortir({
            "ok": False,
            "provider": "ollama",
            "error": "clé absente (core/secrets.json → " + llm_providers.reference_cle("ollama") + ")",
        })

    try:
        donnees = solde(cle)
    except Exception as erreur:                       # noqa: BLE001
        donnees = {"ok": False, "provider": "ollama", "error": message_erreur(erreur)}

    if donnees.get("ok"):
        try:
            donnees.update(consommation(cle))
            donnees["usage_error"] = None
        except Exception as erreur:                   # noqa: BLE001
            # Le solde est la donnée qui compte ; l'usage est un confort.
            donnees["usage_7d"] = None
            donnees["requests_7d"] = None
            donnees["usage_error"] = message_erreur(erreur)
        donnees["ts"] = int(time.time())
        donnees["cached"] = False
        ecrire_cache(donnees)
        return llm_contrat.sortir(presenter(donnees))

    # Échec : la dernière valeur connue vaut mieux qu'un tiret, à condition de
    # dire qu'elle est périmée.
    if cache and cache.get("ok"):
        cache["cached"] = True
        cache["stale_reason"] = donnees.get("error")
        return llm_contrat.sortir(presenter(cache))
    return llm_contrat.sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
