#!/usr/bin/env python3
"""Applet « Comptes LLM » : la ligne de barre des comptes, et rien de plus.

La barre ne peut montrer qu'une valeur : ce service choisit laquelle. Le détail
(soldes, tableau des quotas, échéances) reste dans le popup, qui réutilise
`widgets/comptes.qml` — donc aucun rendu n'est dupliqué ici.

Ordre de priorité, décidé une fois :

  1. un quota tombé à 10 % ou moins : c'est ce qui bloque l'usage, il passe avant
     tout le reste (« 0 % », en couleur d'avertissement) ;
  2. à défaut, un solde que son service signale comme bas (il connaît son propre
     seuil : 5 $ pour DeepSeek, 1 $ pour Ollama) ;
  3. à défaut, le quota le plus bas, qui reste l'information la plus utile ;
  4. à défaut, le premier solde connu.

Les trois services sont interrogés en série : ce sont exactement ceux que le
popup utilisera, avec leurs caches respectifs, donc les deux vues ne peuvent pas
se contredire.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

from applet_contrat import compact, presenter, sortir

ICI = Path(__file__).resolve().parent
CACHE = ICI / "comptes_applet_cache.json"
CACHE_TTL = 60           # s : le popup et la barre demandent la même chose
SERVICES = ("deepseek", "ollama", "antigravity")
SEUIL_QUOTA = 10         # % : en dessous, l'applet passe en alerte
DELAI = 20               # s : un service bloqué ne doit pas figer la barre


def _lancer(nom):
    try:
        res = subprocess.run(
            [sys.executable, str(ICI / f"{nom}_service.py")],
            capture_output=True, text=True, timeout=DELAI,
        )
        if res.returncode != 0:
            return {"ok": False, "error": f"{nom} : code {res.returncode}"}
        return json.loads(res.stdout.strip() or "{}")
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"{nom} : délai dépassé"}
    except (OSError, ValueError) as e:
        return {"ok": False, "error": f"{nom} : {e}"}


def _pourcentage(texte):
    """«  0 % » → 0.0 ; illisible → 1000 (donc jamais choisi en priorité)."""
    try:
        return float(str(texte).replace("%", "").replace(",", ".").strip())
    except (TypeError, ValueError):
        return 1000.0


def _collecter():
    return {nom: _lancer(nom) for nom in SERVICES}


def _choisir(services):
    """Renvoie (valeur, libellé, alerte) selon l'ordre de priorité documenté."""
    quotas = []
    soldes = []
    for nom, s in services.items():
        if not s or not s.get("ok"):
            continue
        for ligne in (s.get("lignes") or []):
            quotas.append((_pourcentage(ligne.get("valeur")),
                           str(ligne.get("valeur") or "").strip(),
                           str(ligne.get("nom") or nom)))
        premieres = s.get("mesures") or []
        if premieres:
            m = premieres[0]
            soldes.append((str(m.get("valeur") or "").strip(),
                           str(s.get("fournisseur") or nom),
                           bool(s.get("alerte"))))

    bas = [q for q in quotas if q[0] <= SEUIL_QUOTA]
    if bas:
        q = min(bas, key=lambda x: x[0])
        return q[1], q[2], True
    for valeur, libelle, alerte in soldes:
        if alerte and valeur:
            return valeur, libelle, True
    if quotas:
        q = min(quotas, key=lambda x: x[0])
        return q[1], q[2], False
    for valeur, libelle, _alerte in soldes:
        if valeur:
            return valeur, libelle, False
    return "—", "", False


def analyser(force=False):
    if not force:
        try:
            lu = json.loads(CACHE.read_text(encoding="utf-8"))
            if 0 <= time.time() - float(lu.get("ts", 0)) < CACHE_TTL:
                return lu
        except (OSError, ValueError):
            pass
    services = _collecter()
    valeur, libelle, alerte = _choisir(services)
    manquants = [nom for nom, s in services.items() if not (s and s.get("ok"))]
    donnees = {
        "ok": True,
        "ts": time.time(),
        "alerte": alerte,
        "compact": compact(valeur, libelle, alerte),
        # Le popup n'utilise pas ce détail (il relance les services), mais il
        # permet de diagnostiquer depuis la ligne de commande sans deviner.
        "services": {nom: bool(s and s.get("ok")) for nom, s in services.items()},
    }
    if manquants:
        donnees["stale_reason"] = "sans réponse : " + ", ".join(manquants)
    try:
        CACHE.write_text(json.dumps(donnees, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    return donnees


def main(argv):
    force = "--force" in argv
    donnees = analyser(force=force)
    presenter(donnees, "comptes", "wallet", donnees["compact"],
              alerte=donnees["alerte"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
