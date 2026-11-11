#!/usr/bin/env python3
"""Écritures de `style_vars.json` sous verrou.

Trois familles d'écrivains se croisent : le panneau (via `config_manager`),
`themes_scan` à l'activation d'une palette, et les services du shell. Chacun
fait lecture-modification-écriture. L'écriture est atomique (`tmp` +
`os.replace`), mais deux qui se croisent **perdent une modification** : le
second écrit son instantané, où la modification du premier n'existe pas encore.

Le verrou porte sur un fichier voisin (`style_vars.json.verrou`), jamais sur la
cible elle-même : `os.replace` remplace l'inode, un verrou posé dessus ne
protégerait plus rien au tour suivant.

`flock` ne protège que les processus qui passent par ici — c'est le cas de tous
les écrivains du shell. Un verrou est relâché à la fermeture du descripteur,
donc automatiquement à la fin du processus.
"""
import contextlib
import fcntl
import json
import os


@contextlib.contextmanager
def verrou(chemin):
    """Verrou exclusif le temps d'un bloc."""
    fichier_verrou = f"{chemin}.verrou"
    dossier = os.path.dirname(fichier_verrou) or "."
    os.makedirs(dossier, exist_ok=True)
    with open(fichier_verrou, "a+") as v:
        fcntl.flock(v, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(v, fcntl.LOCK_UN)


def prendre(chemin):
    """Prend le verrou et le garde jusqu'à la fin du processus.

    Pour une commande qui traite une action entière : le verrou doit couvrir la
    lecture, la décision et l'écriture. Rendre le descripteur pour que
    l'appelant le garde en vie — un ramasse-miettes le fermerait, et `flock`
    serait relâché.
    """
    fichier_verrou = f"{chemin}.verrou"
    dossier = os.path.dirname(fichier_verrou) or "."
    os.makedirs(dossier, exist_ok=True)
    v = open(fichier_verrou, "a+")
    fcntl.flock(v, fcntl.LOCK_EX)
    return v


def lire(chemin, defaut=None):
    try:
        with open(chemin, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {} if defaut is None else defaut


def ecrire(chemin, donnees):
    """Écriture atomique, comme `save_json` et `ecrire_json`."""
    tmp = f"{chemin}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(donnees, f, indent=4, ensure_ascii=False)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, chemin)


def maj(chemin, transformation, defaut=None):
    """Lecture-modification-écriture d'un bloc, sous verrou.

    `transformation` reçoit le contenu et le modifie sur place ; sa valeur de
    retour est rendue telle quelle.
    """
    with verrou(chemin):
        donnees = lire(chemin, defaut)
        resultat = transformation(donnees)
        ecrire(chemin, donnees)
        return resultat
