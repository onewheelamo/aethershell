#!/usr/bin/env python3
"""Applet « Hermes » : l'état de l'agent, ce qu'il fait, et ce qui l'attend.

Le shell ne parle pas à Hermes : il lit un **fichier d'état** que Hermes écrit.
C'est la décision qui commande tout le reste — un fichier JSON rafraîchi suffit
pour l'état, la file, les tâches et les jetons ; les approbations demanderont en
plus un canal de réponse (socket ou fichier requête/réponse), et ce sera la
deuxième étape.

Emplacement, par défaut :
    ${XDG_RUNTIME_DIR:-/run/user/<uid>}/quickshell/hermes-etat.json
En RAM, propre à la session, comme le cache du launcher : un état d'agent n'a
aucune raison de survivre à la session ni d'être écrit sur le disque.

Forme attendue (tous les champs sont facultatifs sauf `etat`) :

    {
      "etat": "repos" | "en_cours" | "attente" | "erreur",
      "tache": "résumé court de la tâche en cours",
      "depuis": "2026-11-06T20:30:00Z",          # début de la tâche en cours
      "file": 2,                                  # tâches en attente
      "executions": [                             # les plus récentes d'abord
        {"nom": "veille prix", "debut": "2026-11-06T20:12:00Z",
         "duree_s": 42, "resultat": "ok", "modele": "deepseek"}
      ],
      "cron": [
        {"nom": "revue hebdo", "prochaine": "2026-11-08T09:00:00Z",
         "dernier": "ok", "quand": "2026-11-01T09:00:00Z"}
      ],
      "jetons": {"jour": 12345, "tache": 1234},
      "ecrit": "2026-11-06T20:45:00Z"
    }

Un fichier absent n'est pas une erreur : l'applet dit « hors ligne » et
n'invente rien. Un fichier plus vieux que DELAI_PERIME est traité comme périmé,
parce qu'un état figé est plus trompeur qu'une absence d'état.

    python3 hermes_applet.py             # contrat de l'applet
    python3 hermes_applet.py --exemple   # écrit un état de démonstration
"""
from __future__ import annotations

import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

DELAI_PERIME = 300          # secondes : au-delà, l'état n'est plus cru


def chemin_etat():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(base) / "quickshell" / "hermes-etat.json"


def maintenant():
    return datetime.datetime.now(datetime.timezone.utc)


def lire():
    """L'état, plus un drapeau `perime` — jamais d'exception."""
    fichier = chemin_etat()
    try:
        avec = json.loads(fichier.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"present": False}
    except (OSError, json.JSONDecodeError):
        return {"present": True, "illisible": True}
    if not isinstance(avec, dict):
        return {"present": True, "illisible": True}

    # L'âge sert à distinguer « l'agent se repose » de « l'agent ne répond plus ».
    ecrit = avec.get("ecrit")
    age = None
    try:
        moment = datetime.datetime.fromisoformat(str(ecrit).replace("Z", "+00:00"))
        age = (maintenant() - moment).total_seconds()
    except (ValueError, TypeError):
        pass
    avec["present"] = True
    avec["age_s"] = round(age) if age is not None else None
    avec["perime"] = age is None or age > DELAI_PERIME
    return avec


ETATS = {
    "repos":    ("repos", "au repos", "ok"),
    "en_cours": ("…", "en cours", "ok"),
    "attente":  ("!", "attend un accord", "attention"),
    "erreur":   ("!", "erreur", "critique"),
}


def analyser():
    # Source de vérité : la base de Hermes lue en lecture seule (hermes_lecteur.py).
    # Le fichier publié par d'anciens déploiements reste un repli, jamais la règle :
    # il n'était jamais écrit, et l'applet restait donc vide.
    d = {}
    try:
        from hermes_lecteur import etat as etat_hermes
        d = etat_hermes() or {}
    except Exception as erreur:              # import cassé, sqlite absent…
        print("hermes_applet : lecteur indisponible (%s)" % erreur, file=sys.stderr)
        d = {}
    if not d.get("present"):
        d = lire()
    if not d.get("present"):
        return {"etat": "hors_ligne", "raison": d.get("raison") or "état indisponible"}
    if d.get("illisible"):
        return {"etat": "hors_ligne", "raison": "état illisible"}

    brut = str(d.get("etat") or "repos").lower()
    symbole, libelle, niveau = ETATS.get(brut, ETATS["repos"])
    # Un état périmé n'est un problème que s'il prétend encore quelque chose :
    # une tâche « en cours » qui ne publie plus est morte, alors qu'un « repos »
    # d'il y a dix minutes est simplement la vie normale d'un agent qui dort.
    if d.get("perime") and brut == "en_cours":
        libelle = "état périmé"
        niveau = "attention"
    elif d.get("perime"):
        libelle, symbole, niveau = "repos", "", "ok"

    # Approbations en attente : publiées par le démon, lues comme le reste.
    try:
        attente = json.loads((chemin_etat().parent / "hermes-approbations.json")
                             .read_text(encoding="utf-8")).get("approbations") or []
    except (OSError, json.JSONDecodeError):
        attente = []
    if not isinstance(attente, list):
        attente = []

    if attente:
        symbole, libelle, niveau = "!", "accord à donner", "attention"

    executions = d.get("executions") or []
    if not isinstance(executions, list):
        executions = []
    cron = d.get("cron") or []
    if not isinstance(cron, list):
        cron = []
    jetons = d.get("jetons") or {}

    return {
        "etat": brut,
        "symbole": symbole,
        "libelle": libelle,
        "niveau": niveau,
        "alerte": niveau in ("attention", "critique"),
        "tache": str(d.get("tache") or ""),
        "depuis": d.get("depuis"),
        "file": int(d.get("file") or 0),
        "executions": executions[:5],
        "cron": cron[:6],
        "gateway": d.get("gateway") or {},
        "logs": d.get("logs") or [],
        "jetons": jetons,
        "approbations": attente[:3],
        "attention": int(d.get("attention") or len(attente)),
        "sessions": d.get("sessions") or [],
        "profils": d.get("profils") or [],
        "source": d.get("source") or "",
        "age_s": d.get("age_s"),
        "perime": bool(d.get("perime")),
        "present": True,
    }


def presenter(a):
    """Le contrat commun : compact pour la barre, detail pour le popup/widget."""
    if a.get("etat") == "hors_ligne":
        return {
            "ok": True,
            "compact": {"valeur": "", "libelle": "", "alerte": False},
            "detail": {"hermes": a},
            "applet": "hermes",
            "icone": "rocket",
            "alerte": False,
        }

    if a.get("approbations"):
        valeur, libelle = "!", "accord à donner"
        a["alerte"] = True
    elif a["etat"] == "attente":
        valeur, libelle = "!", "accord"
    elif a["etat"] == "erreur":
        valeur, libelle = "!", "erreur"
    elif a["etat"] == "en_cours":
        profils = a.get("profils") or []
        if len(profils) > 1:
            valeur, libelle = str(len(profils)), "%d sessions" % len(profils)
        else:
            valeur, libelle = "…", a.get("tache", "")[:24] or "en cours"
    elif a["file"]:
        valeur, libelle = str(a["file"]), "en file"
    else:
        valeur, libelle = "", a["libelle"]

    return {
        "ok": True,
        "compact": {"valeur": valeur, "libelle": libelle, "alerte": a["alerte"]},
        "detail": {"hermes": a},
        "applet": "hermes",
        "icone": "rocket",
        "alerte": a["alerte"],
    }


EXEMPLE = {
    "etat": "en_cours",
    "tache": "veille des prix — 4 boutiques",
    "depuis": "2026-11-06T20:42:00Z",
    "file": 2,
    "executions": [
        {"nom": "revue des commits", "debut": "2026-11-06T20:12:00Z", "duree_s": 42,
         "resultat": "ok", "modele": "deepseek"},
        {"nom": "sauvegarde du portable", "debut": "2026-11-06T19:40:00Z", "duree_s": 130,
         "resultat": "echec", "modele": "—"},
    ],
    "cron": [
        {"nom": "revue hebdo", "prochaine": "2026-11-08T09:00:00Z",
         "dernier": "ok", "quand": "2026-11-01T09:00:00Z"},
        {"nom": "veille prix", "prochaine": "2026-11-06T21:00:00Z",
         "dernier": "ok", "quand": "2026-11-06T20:00:00Z"},
    ],
    "jetons": {"jour": 12345, "tache": 1234},
    "ecrit": maintenant().strftime("%Y-%m-%dT%H:%M:%SZ"),
}


def main(argv):
    if len(argv) > 1:
        cmd = argv[1]
        if cmd == "--exemple":
            fichier = chemin_etat()
            fichier.parent.mkdir(parents=True, exist_ok=True)
            fichier.write_text(json.dumps(EXEMPLE, ensure_ascii=False, indent=2),
                               encoding="utf-8")
            print(str(fichier))
            return 0
        elif cmd in ("gateway-restart", "gateway-start", "gateway-stop"):
            action = cmd.split("-")[1]
            res = subprocess.run(["systemctl", "--user", action, "hermes-gateway.service"],
                                 capture_output=True, text=True)
            print(json.dumps({"ok": res.returncode == 0, "action": action, "output": (res.stdout + res.stderr).strip()}))
            return res.returncode
        elif cmd == "cron-tick":
            res = subprocess.run(["hermes", "cron", "tick"], capture_output=True, text=True)
            print(json.dumps({"ok": res.returncode == 0, "action": "cron-tick", "output": (res.stdout + res.stderr).strip()}))
            return res.returncode
        elif cmd == "doctor":
            res = subprocess.run(["hermes", "cron", "doctor"], capture_output=True, text=True)
            print(json.dumps({"ok": res.returncode == 0, "action": "doctor", "output": (res.stdout + res.stderr).strip()}))
            return res.returncode
        elif cmd == "quick-prompt" and len(argv) > 2:
            prompt = argv[2]
            # Lancement détaché en arrière-plan
            subprocess.Popen(["hermes", "-z", prompt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print(json.dumps({"ok": True, "action": "quick-prompt", "prompt": prompt}))
            return 0

    a = analyser()
    print(json.dumps(presenter(a), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
