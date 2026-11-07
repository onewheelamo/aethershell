#!/usr/bin/env python3
"""Applet « Todo » : les cases à cocher des fichiers Markdown de l'utilisateur.

Ce n'est pas un gestionnaire de tâches : c'est un pont entre ses fichiers et
l'agent. Le contrat, décidé avec lui le 2026-11-07 :

  - il coche dans le panneau → l'applet écrit `- [x]` **dans le fichier** et
    dépose une demande dans une file ;
  - l'agent consomme la file, fait l'étape, puis réécrit la ligne en
    `- [x] ✓ fait le <date>` ; s'il ne peut pas, il décoche et écrit la raison
    sous l'item ;
  - décocher avant la prise annule la demande.

Format reconnu, tel que ses fichiers l'écrivent déjà :

    ## Une section
    - [ ] **Titre de l'étape**
          détail, sur une ou plusieurs lignes indentées
    - [x] ✓ fait le 2026-11-08        ← ce que l'agent écrit

    python3 todo_applet.py etat                 # ce que lit la barre
    python3 todo_applet.py fichiers             # la liste surveillée
    python3 todo_applet.py cocher <id>
    python3 todo_applet.py decocher <id>
    python3 todo_applet.py demandes             # la file, pour l'agent
    python3 todo_applet.py prendre <id>
    python3 todo_applet.py fait <id>            # réécrit la ligne avec la date
    python3 todo_applet.py bloquer <id> "raison"
"""
from __future__ import annotations

import datetime
import fcntl
import hashlib
import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

BASE = os.path.dirname(os.path.abspath(__file__))
CONFIG = os.path.join(BASE, "todo.json")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
FILE = os.path.join(RUNTIME, "quickshell", "todo-demandes.json")
# L'applet ne montre qu'un fichier à la fois ; le widget voit tout. Le choix vit
# dans le cache, pas dans le dépôt : c'est une préférence de machine.
FOCUS = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "quickshell", "todo-focus.json")

# Les fichiers par défaut, chez lui. Le fichier de configuration les remplace.
DEFAUT = {
    "fichiers": [
        {"chemin": os.path.expanduser("~/Documents/homelab/todo.md"), "nom": "homelab"},
        {"chemin": "~/dev/quickshell_todo/RESTE_A_FAIRE.md", "nom": "shell"},
    ]
}

ITEM = re.compile(r"^(?P<indent>[ \t]*)- \[(?P<etat>[ xX])\] (?P<reste>.*)$")
SECTION = re.compile(r"^#{2,3} (?P<titre>.+)$")


# ── configuration ─────────────────────────────────────────────────────────────
def _chemin(chemin):
    return os.path.expanduser(str(chemin or ""))


def fichiers():
    """La liste surveillée : `todo.json` s'il existe, sinon les deux défauts."""
    try:
        with open(CONFIG, "r", encoding="utf-8") as f:
            donnees = json.load(f)
        liste = donnees.get("fichiers") if isinstance(donnees, dict) else donnees
    except (OSError, ValueError):
        liste = DEFAUT["fichiers"]
    sortie = []
    for entree in liste or []:
        if isinstance(entree, str):
            entree = {"chemin": entree, "nom": os.path.basename(entree)}
        chemin = _chemin(entree.get("chemin"))
        if chemin:
            sortie.append({"chemin": chemin,
                           "nom": str(entree.get("nom") or os.path.basename(chemin))})
    return sortie


# ── analyse d'un fichier ──────────────────────────────────────────────────────
def _titre_brut(reste):
    """Le texte d'un item, sans le gras Markdown qui ne sert qu'à l'œil."""
    return re.sub(r"\*\*(.+?)\*\*", r"\1", reste).strip()


def _identifiant(chemin, titre):
    """Empreinte stable : le titre, pas la position. Déplacer une ligne ne change
    rien ; reformuler le titre crée un nouvel item, et c'est voulu."""
    brut = "%s|%s" % (chemin, titre)
    return hashlib.sha1(brut.encode("utf-8")).hexdigest()[:10]


def lire_fichier(chemin, nom):
    """[{id, fichier, nom_fichier, section, titre, detail, fait, date}] dans l'ordre."""
    try:
        with open(chemin, "r", encoding="utf-8") as f:
            lignes = f.readlines()
    except OSError:
        return []
    items = []
    section = ""
    courant = None
    for ligne in lignes:
        sec = SECTION.match(ligne.rstrip("\n"))
        if sec:
            section = sec.group("titre").strip()
            courant = None
            continue
        m = ITEM.match(ligne.rstrip("\n"))
        if m:
            titre = _titre_brut(m.group("reste"))
            if not titre:
                courant = None
                continue
            courant = {
                "id": _identifiant(chemin, titre),
                "fichier": chemin,
                "nom_fichier": nom,
                "section": section,
                "titre": titre,
                "detail": "",
                "fait": m.group("etat") in ("x", "X"),
                "date": "",
            }
            # « ✓ fait le 2026-11-08 » : la date est relue, pas recalculée.
            date = re.search(r"fait le (\d{4}-\d{2}-\d{2})", titre)
            if date:
                courant["date"] = date.group(1)
            items.append(courant)
            continue
        # Ligne de détail : indentée sous l'item courant.
        if courant is not None and ligne.strip() and ligne.startswith((" ", "\t")):
            if len(courant["detail"]) < 240:
                suite = ligne.strip()
                courant["detail"] = (courant["detail"] + " " + suite).strip()
    return items


def focus(options=None):
    """Le nom du fichier que l'applet montre : option, sinon choix mémorisé,
    sinon le premier de la liste."""
    option = str((options or {}).get("fichier") or "").strip()
    if option == "*":
        return "*"
    liste = fichiers()
    noms = [f["nom"] for f in liste]
    if option in noms:
        return option
    try:
        with open(FOCUS, "r", encoding="utf-8") as f:
            memo = str(json.load(f).get("fichier") or "")
        if memo in noms:
            return memo
    except (OSError, ValueError):
        pass
    return noms[0] if noms else ""


def memoriser_focus(nom):
    noms = [f["nom"] for f in fichiers()]
    if nom not in noms:
        return False, "fichier inconnu"
    os.makedirs(os.path.dirname(FOCUS), exist_ok=True)
    tmp = FOCUS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"fichier": nom}, f, ensure_ascii=False)
    os.replace(tmp, FOCUS)
    return True, nom


def items(seulement=None):
    tout = []
    for f in fichiers():
        if seulement and seulement != "*" and f["nom"] != seulement:
            continue
        tout.extend(lire_fichier(f["chemin"], f["nom"]))
    return tout


def _trouver(identifiant):
    for item in items("*"):
        if item["id"] == identifiant:
            return item
    return None


# ── la file des demandes ──────────────────────────────────────────────────────
def _lire_file():
    try:
        with open(FILE, "r", encoding="utf-8") as f:
            donnees = json.load(f)
        liste = donnees.get("demandes") if isinstance(donnees, dict) else []
        return [d for d in liste or [] if isinstance(d, dict)]
    except (OSError, ValueError):
        return []


def _ecrire_file(demandes):
    os.makedirs(os.path.dirname(FILE), exist_ok=True)
    tmp = FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"demandes": demandes}, f, ensure_ascii=False, indent=1)
    os.replace(tmp, FILE)


def _demande(identifiant):
    for d in _lire_file():
        if d.get("id") == identifiant:
            return d
    return None


# ── écriture dans le fichier ──────────────────────────────────────────────────
def _reecrire(chemin, identifiant, transformation):
    """Remplace la ligne de l'item `identifiant`. `transformation(ligne, item)`
    rend la nouvelle ligne, ou None pour laisser tel quel.

    Verrou exclusif et écriture atomique : l'applet et l'agent peuvent écrire le
    même fichier, et un fichier tronqué perdrait des items.
    """
    with open(chemin, "r+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        contenu = f.read()
        lignes = contenu.splitlines(keepends=True)
        items_vus = []
        section = ""
        cible = None
        for numero, ligne in enumerate(lignes):
            sec = SECTION.match(ligne.rstrip("\n"))
            if sec:
                section = sec.group("titre").strip()
                continue
            m = ITEM.match(ligne.rstrip("\n"))
            if not m:
                continue
            titre = _titre_brut(m.group("reste"))
            if not titre:
                continue
            if _identifiant(chemin, titre) == identifiant:
                cible = (numero, m, titre)
                break
        if cible is None:
            fcntl.flock(f, fcntl.LOCK_UN)
            return False
        numero, m, titre = cible
        nouvelle = transformation(lignes[numero].rstrip("\n"), m, titre, lignes, numero)
        if nouvelle is None:
            fcntl.flock(f, fcntl.LOCK_UN)
            return True
        lignes[numero] = nouvelle + "\n"
        # Comparer le contenu entier, pas la seule ligne de l'item : une
        # transformation peut aussi insérer ou retirer des lignes autour (la
        # raison d'un blocage, par exemple). Comparer la ligne seule faisait
        # sortir ici sans écrire, et la raison disparaissait.
        nouveau = "".join(lignes)
        if nouveau == contenu:
            fcntl.flock(f, fcntl.LOCK_UN)
            return True
        f.seek(0)
        f.truncate()
        f.write(nouveau)
        f.flush()
        os.fsync(f.fileno())
        fcntl.flock(f, fcntl.LOCK_UN)
    return True


def _retirer_alerte(lignes, numero):
    """Retire les lignes « ⚠ … » indentées sous l'item."""
    suivant = numero + 1
    while suivant < len(lignes) and lignes[suivant].startswith((" ", "\t")) \
            and lignes[suivant].strip():
        if ITEM.match(lignes[suivant].rstrip("\n")):
            break
        if lignes[suivant].strip().startswith("⚠"):
            del lignes[suivant]
            continue
        suivant += 1


def cocher(identifiant, fait=True):
    item = _trouver(identifiant)
    if not item:
        return False, "item inconnu"

    def transformation(ligne, m, titre, lignes, numero):
        if fait:
            _retirer_alerte(lignes, numero)
        etat = "x" if fait else " "
        return "%s- [%s] %s" % (m.group("indent"), etat, m.group("reste"))

    if not _reecrire(item["fichier"], identifiant, transformation):
        return False, "ligne introuvable"
    demandes = [d for d in _lire_file() if d.get("id") != identifiant]
    if fait:
        demandes.append({
            "id": identifiant,
            "titre": item["titre"],
            "fichier": item["fichier"],
            "nom_fichier": item["nom_fichier"],
            "section": item["section"],
            "quand": datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "etat": "attente",
        })
    _ecrire_file(demandes)
    return True, "coché" if fait else "décoché"


def fait(identifiant, date=None):
    """Réécrit la ligne en « - [x] ✓ fait le <date> » et vide la demande."""
    item = _trouver(identifiant)
    if not item:
        return False, "item inconnu"
    le_jour = date or datetime.date.today().isoformat()

    def transformation(ligne, m, titre, lignes, numero):
        _retirer_alerte(lignes, numero)
        titre_propre = re.sub(r"\s*✓ fait le \d{4}-\d{2}-\d{2}\s*$", "", m.group("reste")).rstrip()
        return "%s- [x] %s ✓ fait le %s" % (m.group("indent"), titre_propre, le_jour)

    if not _reecrire(item["fichier"], identifiant, transformation):
        return False, "ligne introuvable"
    _ecrire_file([d for d in _lire_file() if d.get("id") != identifiant])
    return True, "fait le %s" % le_jour


def bloquer(identifiant, raison):
    """Décoche et écrit la raison sous l'item : rien ne disparaît en silence."""
    item = _trouver(identifiant)
    if not item:
        return False, "item inconnu"

    def transformation(ligne, m, titre, lignes, numero):
        indent = m.group("indent")
        # Une raison déjà écrite est remplacée, pas empilée.
        _retirer_alerte(lignes, numero)
        lignes.insert(numero + 1, "%s      ⚠ %s\n" % (indent, raison.strip()))
        return "%s- [ ] %s" % (indent, m.group("reste"))

    if not _reecrire(item["fichier"], identifiant, transformation):
        return False, "ligne introuvable"
    _ecrire_file([d for d in _lire_file() if d.get("id") != identifiant])
    return True, "bloqué"


def prendre(identifiant):
    demandes = _lire_file()
    for d in demandes:
        if d.get("id") == identifiant:
            d["etat"] = "en_cours"
            _ecrire_file(demandes)
            return True, "prise"
    return False, "aucune demande"


# ── état pour la barre ────────────────────────────────────────────────────────
def analyser(options=None):
    options = options or {}
    choisi = focus(options)
    tout = items(choisi)
    file = _lire_file()
    attente = [d for d in file if d.get("etat") in ("attente", "en_cours")]
    ouverts = [i for i in tout if not i["fait"]]
    if not tout:
        # Deux cas très différents : aucun fichier lisible (une panne, on
        # n'affiche rien) ou un fichier lisible sans aucune case (le focus est
        # simplement sur un fichier qui n'en a pas — ce n'est pas une erreur, et
        # l'en-tête doit continuer à dire lequel).
        if not fichiers():
            return {"ok": True, "compact": compact("", "aucun fichier lisible"),
                    "items": [], "fichiers": [], "focus": "", "demandes": []}
        return {"ok": True, "compact": compact("0", "aucune case ouverte"),
                "items": [], "fichiers": fichiers(), "focus": choisi,
                "ouverts": 0, "demandes": attente}
    valeur = str(len(ouverts))
    libelle = "%d tâche%s" % (len(ouverts), "s" if len(ouverts) > 1 else "")
    if attente:
        libelle = "%d en attente" % len(attente)
    return {
        "ok": True,
        # Un item coché attend l'agent : la barre le dit, sinon on croit que la
        # coche n'a rien fait.
        "compact": compact(valeur, libelle, alerte=bool(attente)),
        "items": [dict(i, demande=(i["id"] in {d.get("id") for d in attente}))
                  for i in tout],
        "ouverts": len(ouverts),
        "fichiers": fichiers(),
        "focus": choisi,
        "demandes": attente,
    }


def _options_cli(argv):
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                return json.loads(arg.split("=", 1)[1])
            except ValueError:
                return {}
    return {}


def main(argv):
    action = argv[1] if len(argv) > 1 else ""
    if action == "focus":
        if len(argv) > 2:
            ok, message = memoriser_focus(argv[2])
            print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
            return 0 if ok else 1
        print(json.dumps({"focus": focus()}, ensure_ascii=False))
        return 0
    if action == "fichiers":
        print(json.dumps(fichiers(), ensure_ascii=False))
        return 0
    if action in ("cocher", "decocher", "prendre", "fait") and len(argv) > 2:
        if action == "cocher":
            ok, message = cocher(argv[2], True)
        elif action == "decocher":
            ok, message = cocher(argv[2], False)
        elif action == "prendre":
            ok, message = prendre(argv[2])
        else:
            ok, message = fait(argv[2])
        print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
        return 0 if ok else 1
    if action == "bloquer" and len(argv) > 3:
        ok, message = bloquer(argv[2], argv[3])
        print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
        return 0 if ok else 1
    if action == "demandes":
        print(json.dumps({"demandes": _lire_file()}, ensure_ascii=False, indent=1))
        return 0

    donnees = analyser(_options_cli(argv))
    presenter(donnees, "todo", "check", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
