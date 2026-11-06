"""Identifiants Nextcloud du calendrier — lecture d'état et écriture ciblée.

Le panneau de configuration ne connaît jamais le mot de passe : il demande son
état (présent ou non, quatre derniers caractères) et en écrit un nouveau. Tout
passe par ce script, qui est le seul à ouvrir core/secrets.json — le fichier
contient aussi les clés des services LLM et ne doit pas être réécrit en entier
depuis QML.

    python3 calendrier_config.py etat
    python3 calendrier_config.py definir url https://cloud.exemple.org
    python3 calendrier_config.py definir user amaury
    python3 calendrier_config.py definir mot_de_passe xxxx-xxxx-xxxx-xxxx
    python3 calendrier_config.py oublier mot_de_passe

Sortie : un JSON sur une ligne, sur stdout. Aucune valeur secrète n'est jamais
renvoyée en clair, ni journalisée.
"""

import json
import os
import sys
import tempfile

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SECRETS_FILE = os.path.join(BASE_DIR, "secrets.json")

CHAMPS = ("url", "user", "app_password")


def lire():
    try:
        with open(SECRETS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return {}
    nc = data.get("nextcloud")
    return nc if isinstance(nc, dict) else {}


def ecrire(nc):
    """Écrit `nextcloud` sans toucher aux autres clés, en 0600 et atomique."""
    try:
        with open(SECRETS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        data = {}
    data["nextcloud"] = nc

    dossier = os.path.dirname(SECRETS_FILE)
    fd, tmp = tempfile.mkstemp(dir=dossier, prefix=".secrets-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, SECRETS_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def etat():
    nc = lire()
    mdp = str(nc.get("app_password") or "")
    return {
        "ok": True,
        "url": str(nc.get("url") or ""),
        "user": str(nc.get("user") or ""),
        "mot_de_passe_present": mdp != "",
        # Quatre derniers caractères : de quoi reconnaître le bon secret sans
        # jamais l'afficher. Jamais plus, même pour un mot de passe court.
        "mot_de_passe_fin": mdp[-4:] if len(mdp) >= 8 else "",
        "complet": bool(nc.get("url") and nc.get("user") and mdp),
    }


def main(argv):
    action = (argv[1] if len(argv) > 1 else "etat").strip()

    if action == "etat":
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    if action == "definir" and len(argv) > 3:
        champ, valeur = argv[2].strip(), argv[3]
        cle = champ if champ in CHAMPS else None
        if cle is None:
            print(json.dumps({"ok": False, "erreur": "champ inconnu"}, ensure_ascii=False))
            return 1
        nc = lire()
        nc[cle] = valeur.strip()
        if cle == "url":
            nc[cle] = nc[cle].rstrip("/")
        # Un champ vidé vaut effacement, pas une chaîne vide écrite.
        if nc[cle] == "":
            nc.pop(cle, None)
        ecrire(nc)
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    if action == "oublier" and len(argv) > 2:
        nc = lire()
        nc.pop(argv[2].strip(), None)
        ecrire(nc)
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    print(json.dumps({"ok": False, "erreur": "usage"}, ensure_ascii=False))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
