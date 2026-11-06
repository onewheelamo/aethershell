#!/usr/bin/env python3
"""Publie l'état de Hermes pour le shell (applet, popup, widget).

Le shell ne parle pas à l'agent : il lit un fichier d'état. Ce script est
l'autre moitié — il écrit ce fichier, de façon atomique et sous verrou, pour
qu'un lecteur ne tombe jamais sur un JSON tronqué.

Emplacement : ${XDG_RUNTIME_DIR}/quickshell/hermes-etat.json (RAM, par session).

    # une tâche commence
    hermes_publier.py debut "veille des prix — 4 boutiques"

    # elle se termine
    hermes_publier.py fin ok --duree 42 --modele deepseek

    # elle échoue, avec le motif dans le journal d'exécutions
    hermes_publier.py fin echec --duree 12 --motif "timeout boutique 3"

    # une tâche de fond se planifie
    hermes_publier.py cron "revue hebdo" --prochain 2026-11-08T09:00Z --dernier ok

    # consommation de la journée
    hermes_publier.py jetons --jour 12345 --tache 1234

    # une tâche longue : rafraîchir l'horodatage sans rien changer
    hermes_publier.py battement

    # ce que le shell verra
    hermes_publier.py lire

Chaque écriture rafraîchit `ecrit` : au-delà de cinq minutes sans écriture, le
shell considère l'état comme périmé, ce qui est le comportement voulu — un état
figé est plus trompeur qu'une absence d'état.
"""
from __future__ import annotations

import fcntl
import json
import os
import sys
from pathlib import Path

MAX_EXECUTIONS = 5
MAX_CRON = 4
ETATS = ("repos", "en_cours", "attente", "erreur")


def racine():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(base) / "quickshell"


def chemin_etat():
    return racine() / "hermes-etat.json"


def maintenant():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc)


def horodatage(moment=None):
    return (moment or maintenant()).strftime("%Y-%m-%dT%H:%M:%SZ")


class Verrou:
    """Un seul écrivain à la fois : deux hooks peuvent se croiser."""

    def __init__(self):
        self.fichier = racine() / "hermes.lock"

    def __enter__(self):
        racine().mkdir(parents=True, exist_ok=True)
        self.fd = open(self.fichier, "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()
        return False


def lire_brut():
    try:
        d = json.loads(chemin_etat().read_text(encoding="utf-8"))
        if isinstance(d, dict):
            return d
    except (OSError, json.JSONDecodeError):
        pass
    return {"etat": "repos", "executions": [], "cron": [], "jetons": {}}


def ecrire(d):
    """Écriture atomique : un lecteur voit l'ancien état ou le nouveau, jamais
    un fichier à moitié écrit."""
    d["ecrit"] = horodatage()
    dossier = chemin_etat().parent
    dossier.mkdir(parents=True, exist_ok=True)
    provisoire = dossier / ".hermes-etat.json.tmp"
    provisoire.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(provisoire, chemin_etat())
    return d


def argument(argv, nom, defaut=None):
    if nom in argv:
        i = argv.index(nom)
        if i + 1 < len(argv):
            return argv[i + 1]
    return defaut


def nombre(valeur, defaut=0):
    try:
        return int(float(valeur))
    except (TypeError, ValueError):
        return defaut


def cmd_debut(argv):
    if not argv:
        return "debut : il manque le libellé de la tâche", 2
    with Verrou():
        d = lire_brut()
        d["etat"] = "en_cours"
        d["tache"] = " ".join(argv)
        d["depuis"] = horodatage()
        ecrire(d)
    return f"tâche publiée : {' '.join(argv)}", 0


def cmd_fin(argv):
    if not argv or argv[0] not in ("ok", "echec"):
        return "fin : attendu « ok » ou « echec »", 2
    resultat = argv[0]
    duree = nombre(argument(argv, "--duree", "0"))
    with Verrou():
        d = lire_brut()
        executions = d.get("executions") or []
        executions.insert(0, {
            "nom": d.get("tache") or "tâche",
            "debut": d.get("depuis") or horodatage(),
            "duree_s": duree,
            "resultat": resultat,
            "modele": argument(argv, "--modele", "—"),
            "motif": argument(argv, "--motif", ""),
        })
        d["executions"] = executions[:MAX_EXECUTIONS]
        d["etat"] = "erreur" if resultat == "echec" else "repos"
        d["tache"] = argument(argv, "--tache", "") or ""
        d.pop("depuis", None)
        ecrire(d)
    return f"tâche terminée : {resultat}", 0


def cmd_etat(argv):
    if not argv or argv[0] not in ETATS:
        return f"etat : attendu parmi {', '.join(ETATS)}", 2
    with Verrou():
        d = lire_brut()
        if d.get("etat") != argv[0]:
            d["depuis"] = horodatage()
        d["etat"] = argv[0]
        if argument(argv, "--tache"):
            d["tache"] = argument(argv, "--tache")
        if argument(argv, "--file") is not None:
            d["file"] = nombre(argument(argv, "--file"))
        ecrire(d)
    return f"état publié : {argv[0]}", 0


def cmd_cron(argv):
    if not argv:
        return "cron : il manque le nom de la tâche", 2
    nom = argv[0]
    with Verrou():
        d = lire_brut()
        entrees = [c for c in (d.get("cron") or []) if c.get("nom") != nom]
        entrees.insert(0, {
            "nom": nom,
            "prochaine": argument(argv, "--prochain", ""),
            "dernier": argument(argv, "--dernier", "ok"),
            "quand": argument(argv, "--quand", horodatage()),
        })
        d["cron"] = entrees[:MAX_CRON]
        ecrire(d)
    return f"planification publiée : {nom}", 0


def cmd_jetons(argv):
    with Verrou():
        d = lire_brut()
        jetons = d.get("jetons") or {}
        if argument(argv, "--jour") is not None:
            jetons["jour"] = nombre(argument(argv, "--jour"))
        if argument(argv, "--tache") is not None:
            jetons["tache"] = nombre(argument(argv, "--tache"))
        d["jetons"] = jetons
        ecrire(d)
    return f"jetons : {jetons}", 0


def cmd_battement(argv):
    with Verrou():
        ecrire(lire_brut())
    return "horodatage rafraîchi", 0


def cmd_lire(argv):
    print(json.dumps(lire_brut(), ensure_ascii=False, indent=2))
    return "", 0


COMMANDES = {
    "debut": cmd_debut, "fin": cmd_fin, "etat": cmd_etat, "cron": cmd_cron,
    "jetons": cmd_jetons, "battement": cmd_battement, "lire": cmd_lire,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDES:
        print(__doc__)
        return 0 if len(argv) < 2 else 2
    message, code = COMMANDES[argv[1]](argv[2:])
    if message:
        print(message, file=sys.stdout if code == 0 else sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
