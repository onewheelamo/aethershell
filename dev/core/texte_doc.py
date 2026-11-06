#!/usr/bin/env python3
"""Texte d'un document, pour la recherche dans le contenu.

Appelé par `rg --pre` (une invocation par fichier correspondant aux
`--pre-glob`), il écrit sur la sortie standard le texte du document :

    .pdf            pdftotext -layout  (poppler)
    .docx           word/document.xml, balises retirées
    .odt, .odp      content.xml, balises retirées
    autre           le fichier tel quel

Sans lui, `rg` voit un PDF ou un DOCX comme un binaire et ne trouve rien : on
pouvait chercher « bail » dans un `.txt` mais pas dans le contrat qui porte ce
mot. Le format `.doc` (binaire ancien) n'est pas couvert — il faudrait antiword
ou catdoc, absents ici ; le fichier sort sans texte plutôt qu'avec du bruit.
"""
from __future__ import annotations

import hashlib
import html
import os
import re
import subprocess
import sys
import time
import zipfile
from pathlib import Path

# Plafond du cache, et cadence d'élagage : on ne parcourt pas le dossier à chaque
# fichier, seulement de temps en temps.
PLAFOND_OCTETS = 128 * 1024 * 1024
ELAGAGE_INTERVALLE = 30.0

CACHE_MEMOIRE = {}


def _cache_dir():
    """`$XDG_RUNTIME_DIR/quickshell/texte`, ou None s'il n'y a pas de session."""
    if "chemin" in CACHE_MEMOIRE:
        return CACHE_MEMOIRE["chemin"]
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    dossier = Path(base) / "quickshell" / "texte"
    try:
        dossier.mkdir(parents=True, exist_ok=True)
        os.chmod(dossier, 0o700)
    except OSError:
        dossier = None
    CACHE_MEMOIRE["chemin"] = dossier
    return dossier


def _cle(chemin, etat):
    return hashlib.sha1(f"{chemin}:{etat.st_size}:{etat.st_mtime_ns}".encode()).hexdigest()


def _elaguer(dossier, total_ajoute=0):
    """Retire les plus anciens tant que le dossier dépasse le plafond."""
    dernier = CACHE_MEMOIRE.get("elagage", 0.0)
    if time.time() - dernier < ELAGAGE_INTERVALLE:
        return
    CACHE_MEMOIRE["elagage"] = time.time()
    entrees, total = [], 0
    for fichier in dossier.iterdir():
        try:
            st = fichier.stat()
        except OSError:
            continue
        total += st.st_size
        entrees.append((st.st_atime, st.st_size, fichier))
    if total <= PLAFOND_OCTETS:
        return
    entrees.sort()
    for _, taille, fichier in entrees:
        if total <= PLAFOND_OCTETS:
            break
        try:
            fichier.unlink()
            total -= taille
        except OSError:
            pass


def _lire_cache(chemin, etat):
    dossier = _cache_dir()
    if dossier is None:
        return None
    try:
        return (dossier / _cle(chemin, etat)).read_text(encoding="utf-8")
    except OSError:
        return None


def _ecrire_cache(chemin, etat, texte):
    dossier = _cache_dir()
    if dossier is None:
        return
    try:
        (dossier / _cle(chemin, etat)).write_text(texte, encoding="utf-8")
    except OSError:
        return
    _elaguer(dossier)

BALISE = re.compile(r"<[^>]+>")


def _nettoyer(xml: str) -> str:
    # Les fins de paragraphe et de ligne de tableau deviennent des retours à la
    # ligne : sans ça, tout le document tiendrait sur une seule ligne et chaque
    # correspondance afficherait la totalité du texte.
    xml = xml.replace("</w:p>", "\n").replace("</text:p>", "\n")
    xml = xml.replace("</w:tr>", "\n").replace("</text:h>", "\n")
    xml = xml.replace("<w:tab/>", " ").replace("<text:tab/>", " ")
    texte = BALISE.sub(" ", xml)
    texte = html.unescape(texte)
    lignes = [re.sub(r"[ \t]+", " ", ligne).strip() for ligne in texte.splitlines()]
    return "\n".join(ligne for ligne in lignes if ligne)


def _depuis_zip(chemin: str, membre: str) -> str:
    try:
        with zipfile.ZipFile(chemin) as z:
            nom = membre
            if nom not in z.namelist():
                # ODT et DOCX nomment parfois autrement ; on prend le premier XML
                # de contenu qui ressemble à du texte.
                candidats = [n for n in z.namelist()
                             if n.endswith((".xml",)) and "document" in n or n == "content.xml"]
                if not candidats:
                    return ""
                nom = candidats[0]
            return _nettoyer(z.read(nom).decode("utf-8", "replace"))
    except (zipfile.BadZipFile, OSError, KeyError):
        return ""


def texte(chemin: str) -> str:
    extension = os.path.splitext(chemin)[1].lower()
    if extension in (".pdf", ".docx", ".odt", ".odp", ".ods"):
        try:
            etat = os.stat(chemin)
        except OSError:
            return ""
        memo = _lire_cache(chemin, etat)
        if memo is not None:
            return memo
        extrait = _extraire(chemin, extension)
        _ecrire_cache(chemin, etat, extrait)
        return extrait
    return _extraire(chemin, extension)


def _extraire(chemin: str, extension: str) -> str:
    if extension == ".pdf":
        try:
            return subprocess.run(["pdftotext", "-q", "-layout", chemin, "-"],
                                  capture_output=True, text=True, timeout=15,
                                  errors="replace").stdout
        except (OSError, subprocess.TimeoutExpired):
            return ""
    if extension == ".docx":
        return _depuis_zip(chemin, "word/document.xml")
    if extension in (".odt", ".odp", ".ods"):
        return _depuis_zip(chemin, "content.xml")
    # Tout le reste : du texte s'il en est, rien si c'est binaire. Un `.doc`
    # ancien ne doit pas déverser ses octets dans la recherche — sinon un motif
    # de trois lettres trouve n'importe quoi au hasard des entêtes.
    try:
        with open(chemin, "rb") as f:
            debut = f.read(8192)
        if b"\x00" in debut:
            return ""
        with open(chemin, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    try:
        sys.stdout.write(texte(sys.argv[1]))
        sys.stdout.flush()
    except BrokenPipeError:      # rg a fini de lire : ce n'est pas une erreur
        os._exit(0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
