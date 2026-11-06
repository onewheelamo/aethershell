#!/usr/bin/env python3
"""Canal d'approbation entre Hermes et le shell, sur une socket Unix.

Hermes demande, le shell répond. Le transport est une socket Unix locale, parce
qu'une approbation est une question qui attend une réponse : deux fichiers
suffiraient mal, mais il faudrait alors inventer un horodatage, un verrou et un
nettoyage pour dire « la réponse concerne bien cette demande ».

    ${XDG_RUNTIME_DIR}/quickshell/hermes-approbations.sock

Trois rôles, un seul protocole : des lignes JSON terminées par un saut de ligne.

    hermes_approbations.py serveur              # le démon
    hermes_approbations.py demander "titre" --detail "..."  # Hermes, bloque
    hermes_approbations.py repondre <id> oui    # le shell
    hermes_approbations.py liste                # ce qui attend un verdict

Le démon tient la liste des demandes en attente et la recopie dans
`hermes-approbations.json` : l'applet et le widget la lisent comme le reste de
l'état, sans avoir à parler socket. C'est le démon qui décide, pas le fichier —
si le démon meurt, les demandes en attente tombent, ce qui est le bon défaut :
une approbation qu'on ne peut plus accorder ne doit pas rester à l'écran.

Réponse par défaut : refus. Une demande sans shell connecté, ou sans verdict
dans le délai, est refusée avec son motif — jamais accordée par omission.
"""
from __future__ import annotations

import json
import os
import socket
import sys
import threading
import time
import uuid
from pathlib import Path

DELAI_DEFAUT = 300.0        # secondes d'attente d'un verdict


def racine():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return Path(base) / "quickshell"


def chemin_socket():
    return racine() / "hermes-approbations.sock"


def chemin_liste():
    return racine() / "hermes-approbations.json"


def horodatage():
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Serveur:
    def __init__(self):
        self.attente = {}                 # id -> dict de la demande
        self.verdicts = {}                # id -> dict du verdict
        self.verrou = threading.Lock()

    # ── état publié pour le shell ────────────────────────────────────────────
    def publier(self):
        with self.verrou:
            liste = [dict(d) for d in self.attente.values()]
        provisoire = chemin_liste().with_suffix(".tmp")
        provisoire.write_text(json.dumps({"approbations": liste, "ecrit": horodatage()},
                                         ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(provisoire, chemin_liste())

    # ── une connexion entrante ───────────────────────────────────────────────
    def traiter(self, conn):
        fichier = conn.makefile("rw", encoding="utf-8", newline="\n")
        try:
            ligne = fichier.readline()
            if not ligne:
                return
            message = json.loads(ligne)
            role = message.get("role")

            if role == "demande":
                self.demande(fichier, message)
            elif role == "verdict":
                self.verdict(message)
            elif role == "liste":
                fichier.write(json.dumps({"approbations": list(self.attente.values())},
                                         ensure_ascii=False) + "\n")
                fichier.flush()
        except (json.JSONDecodeError, OSError):
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def demande(self, fichier, message):
        identifiant = uuid.uuid4().hex[:8]
        delai = float(message.get("delai") or DELAI_DEFAUT)
        entree = {
            "id": identifiant,
            "titre": str(message.get("titre") or "approbation")[:120],
            "detail": str(message.get("detail") or "")[:400],
            "depuis": horodatage(),
            "expire_s": int(delai),
        }
        with self.verrou:
            self.attente[identifiant] = entree
        self.publier()

        limite = time.monotonic() + delai
        while time.monotonic() < limite:
            with self.verrou:
                verdict = self.verdicts.pop(identifiant, None)
            if verdict:
                break
            time.sleep(0.2)
        else:
            verdict = {"id": identifiant, "accord": False, "motif": "délai dépassé"}

        with self.verrou:
            self.attente.pop(identifiant, None)
            self.verdicts.pop(identifiant, None)
        self.publier()

        fichier.write(json.dumps(verdict, ensure_ascii=False) + "\n")
        fichier.flush()

    def verdict(self, message):
        identifiant = str(message.get("id") or "")
        if not identifiant:
            return
        with self.verrou:
            if identifiant in self.attente:
                self.verdicts[identifiant] = {
                    "id": identifiant,
                    "accord": bool(message.get("accord")),
                    "motif": str(message.get("motif") or ""),
                    "par": "shell",
                }

    # ── boucle ───────────────────────────────────────────────────────────────
    def servir(self):
        racine().mkdir(parents=True, exist_ok=True)
        chemin = chemin_socket()
        if chemin.exists():
            chemin.unlink()               # socket périmée d'une session précédente
        self.publier()

        avec = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        avec.bind(str(chemin))
        os.chmod(chemin, 0o600)           # seul l'utilisateur : une approbation
        avec.listen(16)                   # ne se prend pas depuis un autre compte
        try:
            while True:
                conn, _ = avec.accept()
                threading.Thread(target=self.traiter, args=(conn,), daemon=True).start()
        finally:
            avec.close()
            for f in (chemin, chemin_liste()):
                try:
                    f.unlink()
                except OSError:
                    pass


# ── clients ──────────────────────────────────────────────────────────────────
def envoyer(message, attendre_reponse=True):
    chemin = chemin_socket()
    if not chemin.exists():
        return None
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(600)
        s.connect(str(chemin))
        fichier = s.makefile("rw", encoding="utf-8", newline="\n")
        fichier.write(json.dumps(message, ensure_ascii=False) + "\n")
        fichier.flush()
        if not attendre_reponse:
            return {"envoye": True}
        ligne = fichier.readline()
        return json.loads(ligne) if ligne else None


def cmd_serveur(argv):
    import signal

    serveur = Serveur()

    def arreter(*_):
        for f in (chemin_socket(), chemin_liste()):
            try:
                f.unlink()
            except OSError:
                pass
        raise SystemExit(0)

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, arreter)
    serveur.servir()
    return "", 0


def cmd_demander(argv):
    if not argv:
        return "demander : il manque le titre", 2
    def detail(nom, defaut=""):
        if nom in argv and argv.index(nom) + 1 < len(argv):
            return argv[argv.index(nom) + 1]
        return defaut
    titre = argv[0]
    reponse = envoyer({"role": "demande", "titre": titre,
                       "detail": detail("--detail"),
                       "delai": float(detail("--delai", str(int(DELAI_DEFAUT))))})
    if reponse is None:
        return "aucun démon d'approbation : refus par défaut", 1
    print(json.dumps(reponse, ensure_ascii=False))
    return "", (0 if reponse.get("accord") else 1)


def cmd_repondre(argv):
    if len(argv) < 2 or argv[1] not in ("oui", "non"):
        return "repondre : attendu <id> oui|non", 2
    accord = argv[1] == "oui"
    reponse = envoyer({"role": "verdict", "id": argv[0], "accord": accord}, attendre_reponse=False)
    if reponse is None:
        return "aucun démon d'approbation", 1
    return f"verdict envoyé : {'accordé' if accord else 'refusé'}", 0


def cmd_liste(argv):
    reponse = envoyer({"role": "liste"})
    if reponse is None:
        print(json.dumps({"approbations": [], "hors_ligne": True}, ensure_ascii=False))
        return "", 0
    print(json.dumps(reponse, ensure_ascii=False))
    return "", 0


COMMANDES = {"serveur": cmd_serveur, "demander": cmd_demander,
             "repondre": cmd_repondre, "liste": cmd_liste}


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
