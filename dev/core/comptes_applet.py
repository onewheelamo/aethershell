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


def _valeur_service(nom, s):
    """La valeur qui représente un service : son quota le plus bas, sinon son solde.

    Un service à quotas (Antigravity) est résumé par le quota qui contraint le
    plus ; un service à solde (DeepSeek, Ollama) par ce solde. Le libellé nomme
    la ligne choisie, sinon on ne saurait pas de quoi parle le chiffre.
    """
    if not s or not s.get("ok"):
        return None
    lignes = s.get("lignes") or []
    if lignes:
        pire = min(lignes, key=lambda l: _pourcentage(l.get("valeur")))
        texte = str(pire.get("valeur") or "").strip()
        if texte:
            return texte, str(pire.get("nom") or nom), bool(pire.get("alerte"))
    mesures = s.get("mesures") or []
    if mesures:
        texte = str(mesures[0].get("valeur") or "").strip()
        if texte:
            return texte, str(s.get("fournisseur") or nom), bool(s.get("alerte"))
    return None


def _survol(services, prefere, affiche=None):
    """Les autres services, pour la carte de survol : nom et valeur, rien de plus.

    On écarte aussi celui que la barre montre déjà : sans préférence choisie, la
    règle d'alerte peut désigner n'importe quel service, et la carte le répétait.
    """
    lignes = []
    for nom in SERVICES:
        if nom == prefere:
            continue
        trouve = _valeur_service(nom, services.get(nom))
        if not trouve:
            continue
        if affiche and trouve[1] == affiche[1] and trouve[0] == affiche[0]:
            continue
        lignes.append({"nom": trouve[1], "valeur": trouve[0], "alerte": trouve[2]})
    return lignes


def analyser(options=None, force=False):
    prefere = str((options or {}).get("prefere") or "").strip()
    if not force:
        try:
            lu = json.loads(CACHE.read_text(encoding="utf-8"))
            # Le cache porte le choix qui l'a produit : changer de service
            # prioritaire doit se voir tout de suite, pas au bout d'une minute.
            if (0 <= time.time() - float(lu.get("ts", 0)) < CACHE_TTL
                    and str(lu.get("prefere") or "") == prefere):
                return lu
        except (OSError, ValueError):
            pass
    services = _collecter()
    choisi = _valeur_service(prefere, services.get(prefere)) if prefere in SERVICES else None
    if choisi:
        # Service préféré choisi par l'utilisateur : la barre l'affiche, même si
        # un autre service est plus bas. La carte de survol montre les autres, et
        # le popup garde le détail complet — l'alerte reste visible via la couleur.
        valeur, libelle, alerte = choisi
    else:
        valeur, libelle, alerte = _choisir(services)
    survol = _survol(services, prefere if choisi else "", (valeur, libelle))
    manquants = [nom for nom, s in services.items() if not (s and s.get("ok"))]
    donnees = {
        "ok": True,
        "ts": time.time(),
        "alerte": alerte,
        "compact": compact(valeur, libelle, alerte),
        # Carte de survol : les services que la barre ne montre pas.
        "survol": survol,
        "prefere": prefere if choisi else "",
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
    options = {}
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                options = json.loads(arg.split("=", 1)[1])
            except ValueError:
                options = {}
    donnees = analyser(options=options, force=force)
    presenter(donnees, "comptes", "wallet", donnees["compact"],
              alerte=donnees["alerte"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
