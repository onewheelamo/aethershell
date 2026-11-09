#!/usr/bin/env python3
"""Worker d'exécution des tâches Todo confiées à Hermes (Étape 1).

Ce script fait le pont entre les demandes déposées par l'applet Todo
(`todo-demandes.json`) et l'agent Hermes :

  1. Vérifie si la surveillance est active (`todo_applet.est_surveillance_active()`).
     Si désactivée, ne fait rien et quitte.
  2. Parcourt les demandes à l'état `attente`.
  3. Pour chaque demande :
     - La prend en charge (`todo_applet.prendre(id)`).
     - Notifie l'utilisateur via `notify-send` que Hermes prend la tâche.
     - Exécute la tâche via `hermes -z "<prompt>"` ou via `hermes_session.sh`.
     - Si succès (exit 0) : marque la ligne Markdown comme `✓ fait le <date>` via `todo_applet.fait(id)`.
     - Si échec : remet la case à `[ ]` avec la mention `⚠ <erreur>` via `todo_applet.bloquer(id, ...)`.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, BASE)
import todo_applet  # noqa: E402


def notifier(titre, corps, urgence="normal"):
    """Envoie une notification bureau avec notify-send si disponible."""
    if shutil.which("notify-send"):
        try:
            cmd = ["notify-send", "-a", "Hermes", "-u", urgence, str(titre), str(corps)]
            subprocess.run(cmd, capture_output=True, timeout=5)
        except Exception:
            pass


def executer_demande(demande):
    """Prend en charge une demande et lance Hermes pour l'exécuter."""
    item_id = demande.get("id")
    if not item_id:
        return False, "identifiant manquant"

    titre = demande.get("titre") or "Tâche sans titre"
    section = demande.get("section") or ""
    fichier = demande.get("fichier") or ""

    # 1. Prise en charge du bail
    ok, msg = todo_applet.prendre(item_id)
    if not ok:
        return False, f"impossible de prendre la demande ({msg})"

    notifier("Tâche prise en charge", f"{titre}\n({section or 'Todo'})")

    # 2. Construction du prompt d'instruction pour Hermes
    contexte = f"Section : {section}" if section else ""
    if fichier:
        contexte += f" (Fichier : {fichier})"
    prompt = f"Tâche issue du gestionnaire Todo : {titre}.\n{contexte}\nRéalise cette action ou effectue les commandes demandées."

    # 3. Exécution avec Hermes
    hermes_bin = shutil.which("hermes") or os.path.expanduser("~/.local/bin/hermes")
    if not os.path.exists(hermes_bin):
        todo_applet.bloquer(item_id, "binaire hermes introuvable")
        notifier("Échec de la tâche", f"Hermes introuvable pour {titre}", urgence="critical")
        return False, "hermes introuvable"

    cmd = [hermes_bin, "-z", prompt]
    wrapper = os.path.join(BASE, "hermes_session.sh")
    if os.path.isfile(wrapper) and os.access(wrapper, os.X_OK):
        cmd = [wrapper, f"Todo: {titre[:40]}", "--", hermes_bin, "-z", prompt]

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        code = res.returncode
        stdout = res.stdout
        stderr = res.stderr
    except subprocess.TimeoutExpired:
        code = 124
        stderr = "Délai d'exécution dépassé (timeout 10 min)"
    except Exception as e:
        code = 1
        stderr = str(e)

    # 4. Traitement du résultat
    if code == 0:
        todo_applet.fait(item_id)
        notifier("✓ Tâche terminée", titre)
        return True, "succès"
    else:
        erreur = (stderr or stdout or f"Code sortie {code}").strip().splitlines()
        motif = erreur[-1] if erreur else f"Code sortie {code}"
        motif_court = motif[:60]
        todo_applet.bloquer(item_id, f"Hermes : {motif_court}")
        notifier("⚠ Tâche bloquée", f"{titre}\n{motif_court}", urgence="critical")
        return False, motif_court


def traiter_file():
    """Traite toutes les demandes en attente."""
    if not todo_applet.est_surveillance_active():
        return {"ok": False, "motif": "surveillance désactivée"}

    demandes = todo_applet._lire_file()
    en_attente = [d for d in demandes if d.get("etat") == "attente"]
    if not en_attente:
        return {"ok": True, "traitees": 0, "motif": "aucune demande en attente"}

    traitees = 0
    for d in en_attente:
        ok, _ = executer_demande(d)
        if ok:
            traitees += 1

    return {"ok": True, "traitees": traitees}


def main(argv):
    action = argv[1] if len(argv) > 1 else "run"
    if action == "statut":
        active = todo_applet.est_surveillance_active()
        demandes = todo_applet._lire_file()
        en_attente = [d for d in demandes if d.get("etat") == "attente"]
        en_cours = [d for d in demandes if d.get("etat") == "en_cours"]
        print(json.dumps({
            "surveillance": active,
            "en_attente": len(en_attente),
            "en_cours": len(en_cours),
            "total_demandes": len(demandes)
        }, ensure_ascii=False))
        return 0

    if action in ("declencher", "run"):
        cible_id = argv[2] if len(argv) > 2 and action == "declencher" else None
        if not todo_applet.est_surveillance_active():
            print(json.dumps({"ok": False, "motif": "surveillance désactivée"}))
            return 0
        if cible_id:
            demande = todo_applet._demande(cible_id)
            if demande and demande.get("etat") == "attente":
                ok, msg = executer_demande(demande)
                print(json.dumps({"ok": ok, "message": msg}))
                return 0 if ok else 1
            print(json.dumps({"ok": False, "motif": "demande introuvable ou déjà prise"}))
            return 0
        res = traiter_file()
        print(json.dumps(res, ensure_ascii=False))
        return 0

    print("Usage: todo_worker.py [run|declencher <id>|statut]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
