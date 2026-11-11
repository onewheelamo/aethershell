#!/usr/bin/env python3
"""Schémas de couleurs installés : les lire sur le disque, pas les recopier ici.

Deux dossiers peuvent porter un schéma KDE (un fichier INI `.colors`) :
`~/.local/share/color-schemes` (ce que le panneau installe) et
`/usr/share/color-schemes` (ce que la distribution livre). Ce sont eux qui font
foi : un schéma supprimé du disque n'a rien à faire dans la liste du panneau.

D'où deux niveaux, et c'est la raison d'être de ce fichier :

  • `palette_cache.json` — le **catalogue**, recopié du disque à chaque scan
    (nom, palette convertie, chemin). Donnée dérivée : elle se jette et se refait,
    elle ne va pas dans le dépôt.
  • `style_vars.json` — la **configuration** : la palette active seulement, plus
    les palettes écrites à la main (`dynamic`, `tokyo-night`, `catppuccin`). Le
    panneau n'y ajoute plus soixante schémas à chaque ouverture.

Une palette importée n'est écrite dans `style_vars.json` qu'au moment où on
l'active : tout ce qui lit `palette[active_theme]` (rofi, terminal, SDDM, Theme)
continue de fonctionner sans rien savoir du cache.

CLI :
    themes_scan.py --list            un schéma par ligne : <slug>\\t<nom>
    themes_scan.py --json            dictionnaire complet des schémas détectés
    themes_scan.py --sync            relit le disque, retire les schémas disparus
    themes_scan.py --import <slug>   active ce schéma (copie sa palette au besoin)
    themes_scan.py --signature       empreinte du disque (diagnostic, sans écrire)
"""
import argparse
import configparser
import hashlib
import json
import os
import re
import subprocess
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
STYLE_FILE = BASE_DIR / "style_vars.json"

sys.path.insert(0, str(BASE_DIR))
import verrou_etat  # noqa: E402  (verrou des ecritures de style_vars.json)
CACHE_FILE = BASE_DIR / "palette_cache.json"
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
    """Nom de fichier utilisable en clé de palette : `Gruvbox.colors` → kde-gruvbox."""
    base = unicodedata.normalize("NFD", Path(chemin).stem.lower())
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

    nom = cfg.get("General", "Name", fallback="").strip() or Path(chemin).stem
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
    """Tous les schémas lisibles, indexés par slug. Un doublon de nom : le premier gagne.

    `~/.local` passe avant `/usr` : ce que l'utilisateur a installé l'emporte sur
    ce que la distribution livre sous le même nom.
    """
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


def empreinte(detectes):
    """Empreinte de ce que le disque propose : nom, mtime et taille de chaque schéma.

    Elle évite de réécrire le catalogue pour rien, et distingue un schéma nouveau
    d'un schéma simplement relu.
    """
    h = hashlib.sha256()
    for cle in sorted(detectes):
        p = Path(detectes[cle]["fichier"])
        try:
            st = p.stat()
            h.update(("%s|%d|%d\n" % (cle, st.st_mtime_ns, st.st_size)).encode("utf-8"))
        except OSError:
            h.update(("%s|absent\n" % cle).encode("utf-8"))
    return h.hexdigest()


def lire_json(chemin, defaut):
    try:
        return json.loads(Path(chemin).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return defaut


def ecrire_json(chemin, donnees):
    """Écrit en deux temps puis renomme : le shell relit ces fichiers en continu.

    Une écriture directe laissait Theme lire un JSON tronqué (« Failed to parse
    style_vars.json ») le temps de l'écriture — le panneau relit ce fichier au
    moment où il s'ouvre, donc les deux se croisent à coup sûr. Le nom temporaire
    porte le pid : deux services qui écrivent en même temps ne se marchent pas
    dessus.
    """
    chemin = Path(chemin)
    temporaire = chemin.with_name("%s.tmp.%d" % (chemin.name, os.getpid()))
    temporaire.write_text(json.dumps(donnees, ensure_ascii=False, indent=4) + "\n",
                          encoding="utf-8")
    os.replace(temporaire, chemin)


# ── Verrou ───────────────────────────────────────────────────────────────────
# Deux écrivains de `style_vars.json` pouvaient se croiser : le panneau et
# l'activation d'une palette. Chacun relisait le fichier, décidait, écrivait —
# le second écrasait la modification du premier. Les deux entrées publiques
# prennent le verrou pour tout le travail ; le corps reste dans la fonction
# privée, qui ne le reprend pas (pas de re-entrance : deux `flock` sur le même
# fichier depuis le même processus se bloqueraient).
def synchroniser(silencieux=False):
    with verrou_etat.verrou(STYLE_FILE):
        return _synchroniser(silencieux)


def activer(cle, silencieux=False):
    with verrou_etat.verrou(STYLE_FILE):
        return _activer(cle, silencieux)


def _synchroniser(silencieux=False):
    """Relit le disque : tient le catalogue à jour, retire les schémas disparus.

    Idempotent et bon marché : un appel sans changement n'écrit rien. C'est ce qui
    permet de l'appeler au démarrage, à la détection d'un nouveau `.colors` et à
    l'ouverture du panneau sans se demander si c'est « déjà fait ».
    """
    detectes = detecter()
    sig = empreinte(detectes)
    cache = lire_json(CACHE_FILE, {})
    if cache.get("signature") != sig:
        ecrire_json(CACHE_FILE, {
            "version": 1,
            "scan_at": datetime.now().isoformat(timespec="seconds"),
            "signature": sig,
            "dossiers": [str(d) for d in DOSSIERS],
            "themes": detectes,
        })

    donnees = lire_json(STYLE_FILE, {})
    actif = donnees.get("active_theme", "dynamic")
    palette = donnees.setdefault("palette", {})
    noms = donnees.setdefault("palette_noms", {})
    modifie = False

    # `style_vars.json` ne garde aucune palette importée, sauf celle qui est
    # active : le reste est le catalogue, et il vit sur le disque.
    for cle in [k for k in palette if k.startswith("kde-") and k != actif]:
        palette.pop(cle, None)
        noms.pop(cle, None)
        modifie = True

    # Les étiquettes du catalogue vivent dans le cache, pas ici : les recopier
    # dans la configuration y ferait entrer les noms des schémas de cette machine.
    # Seules les palettes maison gardent la leur.
    for cle in [k for k in noms if k.startswith("kde-")
                and k not in detectes and k != actif]:
        noms.pop(cle, None)
        modifie = True

    if modifie:
        ecrire_json(STYLE_FILE, donnees)

    anciens = set((cache.get("themes") or {}).keys())
    ajoutes = [{"cle": c, "nom": e["nom"]} for c, e in detectes.items() if c not in anciens]
    if not silencieux:
        print(json.dumps({"ok": True, "ajoutes": ajoutes,
                          "themes": len(detectes)}, ensure_ascii=False))
    return ajoutes


def _activer(cle, silencieux=False):
    """Rend `cle` active, en recopiant sa palette dans style_vars.json au besoin."""
    donnees = lire_json(STYLE_FILE, {})
    palette = donnees.setdefault("palette", {})
    modifie = False

    if cle not in palette:
        cache = lire_json(CACHE_FILE, {})
        entree = (cache.get("themes") or {}).get(cle)
        if entree is None:
            # Le disque a pu changer depuis le dernier scan : on relit avant de
            # refuser, sinon un schéma tout juste installé serait « inconnu ».
            entree = detecter().get(cle)
        if entree is None:
            sys.exit("thème inconnu : %s" % cle)
        palette[cle] = entree["palette"]
        donnees.setdefault("palette_noms", {})[cle] = entree["nom"].replace(".", " ").strip()
        modifie = True

    # Une seule palette importée à la fois dans style_vars.json, y compris quand on
    # revient à une palette maison : le catalogue reste sur le disque.
    for k in [k for k in palette if k.startswith("kde-") and k != cle]:
        palette.pop(k, None)
        donnees.setdefault("palette_noms", {}).pop(k, None)
        modifie = True

    if donnees.get("active_theme") != cle:
        donnees["active_theme"] = cle
        modifie = True

    if modifie:
        ecrire_json(STYLE_FILE, donnees)
    if ROFI_GEN.is_file():
        subprocess.run(["bash", str(ROFI_GEN)], check=False)
    if not silencieux:
        print(json.dumps({"ok": True, "actif": cle}, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list", action="store_true", help="un schéma par ligne")
    ap.add_argument("--json", action="store_true", help="dictionnaire des schémas")
    ap.add_argument("--sync", action="store_true", help="relire le disque, purger le disparu")
    ap.add_argument("--import", dest="importer", metavar="SLUG",
                    help="activer ce schéma")
    ap.add_argument("--signature", action="store_true", help="empreinte du disque")
    a = ap.parse_args()

    if a.list:
        for cle, entree in detecter().items():
            print("%s\t%s" % (cle, entree["nom"]))
        return
    if a.json:
        print(json.dumps(detecter(), ensure_ascii=False, indent=1))
        return
    if a.signature:
        print(empreinte(detecter()))
        return
    if a.importer:
        activer(a.importer)
        return
    if a.sync:
        synchroniser()
        return
    ap.print_help()


if __name__ == "__main__":
    main()
