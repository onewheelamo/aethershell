#!/usr/bin/env python3
"""Solde de l'API DeepSeek — pour savoir quand remettre des fonds.

    deepseek_service.py [--force]

Une ligne JSON sur stdout, rien d'autre :

    {"ok": true, "currency": "CNY", "total": 42.1, "granted": 0.0,
     "topped_up": 42.1, "available": true, "ts": 1699..., "cached": false}

L'API publique n'expose que le solde (`GET /user/balance`) : DeepSeek ne publie
ni pourcentage de quota ni historique de consommation par clé. Le solde est donc
la seule donnée qui réponde à la question « faut-il remettre des fonds ? » — et
`is_available` dit si l'API répond encore.

La clé est lue dans `core/secrets.json` (`deepseek.api_key`, fichier préservé au
déploiement) ou, à défaut, dans l'environnement (`DEEPSEEK_API_KEY`). Rien n'est
journalisé : la clé ne sort pas de ce script.

Cache de 5 minutes dans `core/deepseek_cache.json` : le widget interroge le
service à son rythme, le cache évite une requête par cycle et sert la dernière
valeur connue (`cached: true`) quand le réseau tombe.

Sortie en cas d'échec : {"ok": false, "error": "..."} avec un code de retour 0 —
le widget affiche alors la raison plutôt que de disparaître.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
SECRETS_FILE = BASE_DIR / "secrets.json"
CACHE_FILE = BASE_DIR / "deepseek_cache.json"

API_URL = "https://api.deepseek.com/user/balance"
TTL = 300
TIMEOUT = 8


def cle_api():
    """Clé de l'API : secrets.json d'abord, environnement ensuite."""
    try:
        data = json.loads(SECRETS_FILE.read_text(encoding="utf-8"))
        valeur = (data or {}).get("deepseek", {})
        if isinstance(valeur, dict):
            cle = str(valeur.get("api_key") or "").strip()
        else:
            cle = str(valeur or "").strip()
        if cle:
            return cle
    except (OSError, ValueError):
        pass
    return str(os.environ.get("DEEPSEEK_API_KEY") or "").strip()


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


def interroger(cle):
    requete = urllib.request.Request(
        API_URL,
        headers={"Authorization": f"Bearer {cle}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(requete, timeout=TIMEOUT) as reponse:
        charge = json.loads(reponse.read().decode("utf-8", errors="replace"))

    soldes = charge.get("balance_infos") or []
    # Une seule devise en pratique ; si plusieurs, celle qui porte un solde.
    retenu = None
    for info in soldes:
        if retenu is None or float(info.get("total_balance") or 0) > float(retenu.get("total_balance") or 0):
            retenu = info
    if retenu is None:
        raise ValueError("réponse sans balance_infos")

    return {
        "ok": True,
        "currency": str(retenu.get("currency") or ""),
        "total": round(float(retenu.get("total_balance") or 0), 2),
        "granted": round(float(retenu.get("granted_balance") or 0), 2),
        "topped_up": round(float(retenu.get("topped_up_balance") or 0), 2),
        "available": bool(charge.get("is_available")),
        "ts": int(time.time()),
        "cached": False,
    }


def main(argv):
    force = "--force" in argv

    cache = lire_cache()
    if cache and not force and (time.time() - int(cache.get("ts") or 0)) < TTL:
        cache["cached"] = True
        print(json.dumps(cache, ensure_ascii=False))
        return 0

    cle = cle_api()
    if not cle:
        # Pas de clé : on le dit, et on sert la dernière valeur connue si elle existe.
        if cache:
            cache["cached"] = True
            print(json.dumps(cache, ensure_ascii=False))
            return 0
        print(json.dumps({
            "ok": False,
            "error": "clé absente (core/secrets.json → deepseek.api_key)",
        }, ensure_ascii=False))
        return 0

    try:
        donnees = interroger(cle)
    except urllib.error.HTTPError as erreur:
        message = {401: "clé refusée", 402: "solde épuisé", 403: "accès refusé"}.get(
            erreur.code, f"HTTP {erreur.code}")
        donnees = {"ok": False, "error": message}
    except urllib.error.URLError as erreur:
        donnees = {"ok": False, "error": f"réseau : {erreur.reason}"}
    except Exception as erreur:                      # noqa: BLE001
        donnees = {"ok": False, "error": str(erreur)[:120]}

    if donnees.get("ok"):
        ecrire_cache(donnees)
        print(json.dumps(donnees, ensure_ascii=False))
        return 0

    # Échec : la dernière valeur connue vaut mieux qu'un tiret, à condition de
    # dire qu'elle est périmée.
    if cache and cache.get("ok"):
        cache["cached"] = True
        cache["stale_reason"] = donnees.get("error")
        print(json.dumps(cache, ensure_ascii=False))
        return 0
    print(json.dumps(donnees, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
