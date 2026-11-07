#!/usr/bin/env python3
"""Applet « flotte » : l'état des autres machines du parc, dans la barre.

Chaque machine a son shell ; aucune ne sait rien des autres. Cet applet comble
ça en lecture seule : il interroge les autres machines en SSH, met le résultat en
cache en RAM, et rend le contrat habituel (compact pour la barre, detail pour le
popup).

Aucune adresse n'est écrite dans le dépôt : la liste des machines vit dans
`core/flotte.json`, fichier local préservé par le déploiement.

    {"machines": [{"nom": "portable", "cible": "utilisateur@portable.local"}], "delai_s": 3}

Trois règles de conception :

  * une machine injoignable n'est pas une erreur de l'applet : elle s'affiche
    « injoignable », avec l'heure de la dernière réponse connue. Une barre qui
    disparaît parce que le portable est éteint serait pire que la panne ;
  * la mesure distante tient en **un seul** aller-retour SSH (un python3 -c qui
    rend du JSON), parce que quatre commandes séparées multiplient les délais par
    quatre quand la machine répond mal ;
  * le cache est en RAM et horodaté : au-delà de trois cycles sans réponse, on
    cesse de présenter l'ancienne mesure comme actuelle.

    python3 flotte_applet.py            # contrat de l'applet
    python3 flotte_applet.py --brut     # état détaillé, sans mise en forme
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

DELAI_DEFAUT = 3
CACHE = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "quickshell" / "flotte-etat.json"
CONFIG = Path(__file__).resolve().parent / "flotte.json"

MESURE = r"""
import json, os, subprocess
def lire(p):
    try:
        return open(p).read()
    except OSError:
        return ""
charge = lire("/proc/loadavg").split()[:1]
memo = {}
for l in lire("/proc/meminfo").splitlines():
    c = l.split()
    if len(c) >= 2 and c[0] in ("MemTotal:", "MemAvailable:"):
        memo[c[0]] = int(c[1])
tot = memo.get("MemTotal:", 0); dispo = memo.get("MemAvailable:", 0)
shell = subprocess.run(["pgrep", "-x", "quickshell"], capture_output=True).returncode == 0
barre = shell
up = float(lire("/proc/uptime").split()[0] or 0)
print(json.dumps({
    "charge": charge[0] if charge else "",
    "ram_pct": round(100 * (tot - dispo) / tot) if tot else None,
    "shell": shell,
    "barre": barre,
    "uptime_j": round(up / 86400, 1),
}))
"""


def config():
    try:
        d = json.loads(CONFIG.read_text(encoding="utf-8"))
        if isinstance(d, dict):
            return d
    except (OSError, json.JSONDecodeError):
        pass
    return {"machines": [], "delai_s": DELAI_DEFAUT}


def local():
    return json.loads(subprocess.run([sys.executable, "-c", MESURE],
                                     capture_output=True, text=True, timeout=10).stdout or "{}")


def distant(cible, delai):
    """Un aller-retour : la mesure entière part et revient en une fois."""
    try:
        # Le script part sur l'entrée standard (`python3 -`) : passer le code en
        # argument obligeait à le ré-échapper dans la ligne de commande distante,
        # et ssh le cassait en silence — l'applet annonçait « injoignable » alors
        # que `ssh cible echo ok` répondait.
        p = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=3",
                            "-o", "StrictHostKeyChecking=accept-new", cible,
                            "python3", "-"],
                           input=MESURE, capture_output=True, text=True, timeout=delai + 4)
        if p.returncode != 0 or not p.stdout.strip():
            return None
        return json.loads(p.stdout.strip().splitlines()[-1])
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return None


def mesurer():
    c = config()
    delai = int(c.get("delai_s") or DELAI_DEFAUT)
    machines = c.get("machines") or []

    precedent = {}
    try:
        precedent = json.loads(CACHE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        pass

    etats = []
    for m in machines:
        nom = str(m.get("nom") or m.get("cible") or "?")
        cible = str(m.get("cible") or "")
        mesure = distant(cible, delai) if cible else None
        if mesure:
            etats.append({"nom": nom, "joignable": True, **mesure, "quand": time.time()})
        else:
            vieux = (precedent.get("machines") or {}).get(nom) or {}
            etats.append({"nom": nom, "joignable": False,
                          "derniere_vue": vieux.get("quand"), **{k: vieux.get(k) for k in
                                                                 ("charge", "ram_pct", "barre", "uptime_j")}})

    resultat = {"quand": time.time(), "machines": {e["nom"]: e for e in etats},
                "local": {"nom": os.uname().nodename, **local()}}
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        provisoire = CACHE.with_suffix(".tmp")
        provisoire.write_text(json.dumps(resultat), encoding="utf-8")
        os.replace(provisoire, CACHE)
    except OSError:
        pass
    return resultat


def contrat(etat):
    distantes = [e for e in etat["machines"].values()]
    muettes = [e for e in distantes if not e.get("joignable")]
    barres_off = [e for e in distantes if e.get("joignable") and not e.get("barre")]

    if not distantes:
        return {"ok": True, "compact": {"valeur": "", "libelle": "flotte non configurée", "alerte": False},
                "detail": {"flotte": etat}, "applet": "flotte", "icone": "cloud", "alerte": False}

    if muettes or barres_off:
        alerte = True
        valeur = str(len(muettes) + len(barres_off))
        libelle = "injoignable" if muettes else "barre arrêtée"
    else:
        alerte = False
        valeur = ""
        libelle = f"{len(distantes)} machine(s) en ligne"

    return {"ok": True, "compact": {"valeur": valeur, "libelle": libelle, "alerte": alerte},
            "detail": {"flotte": etat}, "applet": "flotte", "icone": "cloud", "alerte": alerte}


def main(argv):
    etat = mesurer()
    if "--brut" in argv:
        print(json.dumps(etat, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(contrat(etat), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
