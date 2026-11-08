#!/usr/bin/env python3
"""Thèmes de couleurs installés : lire les schémas KDE et les proposer au shell.

Le panneau listait trois noms en dur (`dynamic`, `tokyo-night`, `catppuccin`),
alors que les schémas de couleurs KDE déjà installés — Gruvbox, Nord, Dracula,
Breeze… — sont exactement ce qu'il faut : un fichier INI `.colors` par thème,
dans `~/.local/share/color-schemes` ou `/usr/share/color-schemes`.

Ce script les lit, les convertit dans la forme de `palette` de
`style_vars.json` (bg, fg, accent, accent_muted, surface, surface_variant,
error, warn, info, success) et les y ajoute. Le panneau n'a plus qu'à lister
les clés de `palette`.

CLI :
    themes_scan.py --list            un schéma par ligne : <slug>\t<nom>
    themes_scan.py --json            dictionnaire complet des schémas détectés
    themes_scan.py --sync            ajoute à `palette` ceux qui manquent
    themes_scan.py --import <slug>   ajoute ce schéma et l'active
"""
import argparse
import configparser
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
STYLE_FILE = BASE_DIR / "style_vars.json"
ROFI_GEN = BASE_DIR / "generate_rofi_theme.sh"

DOSSIERS = [Path.home() / ".local" / "share" / "color-schemes",
            Path("/usr/share/color-schemes")]

# Correspondance KDE → shell. KDE nomme ses rôles par section ; le shell a dix
# jetons. Les couleurs de rôle « négatif / neutre / positif » servent d'erreur,
# d'avertissement et de succès.
SECTION = {
    "fond": ("Colors:Window", "BackgroundNormal"),
    "texte": ("Colors:Window", "ForegroundNormal"),
    "surface": ("Colors:View", "BackgroundNormal"),
    "surface_variant": ("Colors:Button", "BackgroundNormal"),
    "accent": ("Colors:Selection", "BackgroundNormal"),
    "accent_muted": ("Colors:Window", "DecorationFocus"),
    "erreur": ("Colors:Window", "ForegroundNegative"),
    "avertissement": ("Colors:Window", "ForegroundNeutral"),
    "succes": ("Colors:Window", "ForegroundPositive"),
}


def slug(chemin):
    """Nom de fichier utilisable en clé de palette : `Gruvbox.colors` → gruvbox."""
    base = unicodedata.normalize("NFD", chemin.stem.lower())
    base = "".join(c for c in base if unicodedata.category(c) != "Mn")
    base = re.sub(r"[^a-z0-9]+", "-", base).strip("-")
    return "kde-" + (base or "sans-nom")


def normaliser(brut):
    """`#1e1e2e`, `#ff1e1e2e` ou `30,30,46` → `#1e1e2e`.

    KDE n'écrit pas toujours en hexadécimal : beaucoup de schémas utilisent des
    triplets décimaux « 18,24,26 ». Sans cette conversion, tous ces thèmes
    étaient ignorés — c'est pourquoi la détection ne rendait rien au premier
    essai.
    """
    valeur = (brut or "").strip()
    if not valeur:
        return None
    triplet = re.match(r"^(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})$", valeur)
    if triplet:
        r, v, b = (min(255, int(x)) for x in triplet.groups())
        return "#%02x%02x%02x" % (r, v, b)
    hexa = re.match(r"^#?([0-9a-fA-F]{8}|[0-9a-fA-F]{6})$", valeur)
    if hexa:
        chiffres = hexa.group(1)
        # #AARRGGBB : on ne garde que la couleur, l'alpha du schéma KDE ne sert pas.
        if len(chiffres) == 8:
            chiffres = chiffres[2:]
        return "#" + chiffres.lower()
    return None


def lire(chemin):
    """Lit un schéma `.colors` et rend l'entrée de palette, ou None."""
    cfg = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        # KDE écrit de l'UTF-8 sans en-tête ; `read` tolère les doublons.
        cfg.read(chemin, encoding="utf-8")
    except (OSError, configparser.Error):
        try:
            cfg.read(chemin, encoding="latin-1")
        except (OSError, configparser.Error):
            return None
    if not cfg.has_section("Colors:Window"):
        return None

    couleurs = {}
    for cle, (section, option) in SECTION.items():
        valeur = normaliser(cfg.get(section, option, fallback=""))
        if valeur:
            couleurs[cle] = valeur

    if "fond" not in couleurs or "texte" not in couleurs:
        return None

    nom = cfg.get("General", "Name", fallback="").strip() or chemin.stem
    palette = {
        "bg": couleurs["fond"],
        "fg": couleurs["texte"],
        "accent": couleurs.get("accent", couleurs["texte"]),
        "accent_muted": couleurs.get("accent_muted", couleurs.get("accent", couleurs["texte"])),
        "surface": couleurs.get("surface", couleurs["fond"]),
        "surface_variant": couleurs.get("surface_variant", couleurs.get("surface", couleurs["fond"])),
        "error": couleurs.get("erreur", "#ffb4ab"),
        "warn": couleurs.get("avertissement", "#f6bb7d"),
        "info": couleurs.get("accent", "#f3bb9a"),
        "success": couleurs.get("succes", "#a6e3a1"),
    }
    return {"nom": nom, "palette": palette, "fichier": str(chemin)}


def detecter():
    """Tous les schémas lisibles, indexés par slug. Un doublon de nom : le premier gagne."""
    trouves = {}
    for dossier in DOSSIERS:
        if not dossier.is_dir():
            continue
        for chemin in sorted(dossier.glob("*.colors")):
            cle = slug(chemin)
            if cle in trouves:
                continue
            entree = lire(chemin)
            if entree:
                trouves[cle] = entree
    return trouves


def style():
    if not STYLE_FILE.is_file():
        sys.exit("style_vars.json introuvable : %s" % STYLE_FILE)
    return json.loads(STYLE_FILE.read_text(encoding="utf-8"))


def ecrire(donnees):
    STYLE_FILE.write_text(json.dumps(donnees, ensure_ascii=False, indent=4) + "\n",
                          encoding="utf-8")


def synchroniser(silencieux=False):
    """Ajoute à `palette` les schémas détectés qui n'y sont pas encore."""
    donnees = style()
    palette = donnees.setdefault("palette", {})
    # Noms lisibles à part : la clé reste un identifiant, l'étiquette du panneau
    # est le nom du schéma (« Catppuccin.Mocha » → « Catppuccin Mocha »).
    noms = donnees.setdefault("palette_noms", {})
    detectes = detecter()
    ajoutes = []
    for cle, entree in detectes.items():
        if cle not in noms:
            noms[cle] = entree["nom"].replace(".", " ").strip()
        if cle in palette:
            continue
        palette[cle] = entree["palette"]
        ajoutes.append({"cle": cle, "nom": entree["nom"]})
    if ajoutes:
        ecrire(donnees)
        if not silencieux:
            print(json.dumps({"ok": True, "ajoutes": ajoutes}, ensure_ascii=False))
    elif not silencieux:
        print(json.dumps({"ok": True, "ajoutes": []}, ensure_ascii=False))
    return ajoutes


def activer(cle):
    donnees = style()
    if cle not in (donnees.get("palette") or {}):
        sys.exit("thème inconnu : %s" % cle)
    donnees["active_theme"] = cle
    ecrire(donnees)
    if ROFI_GEN.is_file():
        subprocess.run(["bash", str(ROFI_GEN)], check=False)
    print(json.dumps({"ok": True, "actif": cle}, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true", help="un schéma par ligne")
    ap.add_argument("--json", action="store_true", help="dictionnaire des schémas")
    ap.add_argument("--sync", action="store_true", help="ajouter les schémas manquants")
    ap.add_argument("--import", dest="importer", metavar="SLUG",
                    help="ajouter ce schéma à la palette et l'activer")
    a = ap.parse_args()

    if a.list:
        for cle, entree in detecter().items():
            print("%s\t%s" % (cle, entree["nom"]))
        return
    if a.json:
        print(json.dumps(detecter(), ensure_ascii=False, indent=1))
        return
    if a.importer:
        ajoutes = synchroniser(silencieux=True)
        connu = a.importer in detecter() or a.importer in (style().get("palette") or {})
        if not connu:
            sys.exit("schéma introuvable : %s" % a.importer)
        activer(a.importer)
        return
    if a.sync:
        synchroniser()
        return
    ap.print_help()


if __name__ == "__main__":
    main()
