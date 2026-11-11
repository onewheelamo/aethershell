#!/usr/bin/env python3
"""Installer des thèmes de couleurs téléchargés (.colors ou archives zip/tar).

Copie les schémas dans ~/.local/share/color-schemes/, les synchronise dans
style_vars.json via themes_scan.py, et les active optionnellement.

CLI :
    installer_theme_couleur.py <chemin_fichier> [--activate]
"""
import argparse
import json
import os
import shutil
import sys
import tarfile
import zipfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
COLOR_SCHEMES_DIR = Path.home() / ".local" / "share" / "color-schemes"
THEMES_SCAN = BASE_DIR / "themes_scan.py"


def notifier(titre, corps):
    if shutil.which("notify-send"):
        try:
            import subprocess
            subprocess.run(["notify-send", "-a", "AetherShell", titre, corps],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass


def extraire_archive(chemin_archive, dest_dir):
    fichiers_installes = []
    chemin = Path(chemin_archive)

    # 1. Archive ZIP
    if zipfile.is_zipfile(chemin):
        with zipfile.ZipFile(chemin, "r") as zf:
            for member in zf.namelist():
                if member.endswith(".colors") and not member.startswith("__MACOSX"):
                    nom_fichier = Path(member).name
                    cible = dest_dir / nom_fichier
                    with zf.open(member) as src, open(cible, "wb") as dst:
                        shutil.copyfileobj(src, dst)
                    fichiers_installes.append(cible)
        return fichiers_installes

    # 2. Archive TAR (tar.gz, tar.xz, tar.bz2)
    if tarfile.is_tarfile(chemin):
        with tarfile.open(chemin, "r:*") as tf:
            for member in tf.getmembers():
                if member.name.endswith(".colors") and not Path(member.name).name.startswith("."):
                    nom_fichier = Path(member.name).name
                    cible = dest_dir / nom_fichier
                    f = tf.extractfile(member)
                    if f:
                        with open(cible, "wb") as dst:
                            shutil.copyfileobj(f, dst)
                        fichiers_installes.append(cible)
        return fichiers_installes

    return fichiers_installes


def installer(chemin_str, activer=False):
    src = Path(chemin_str).expanduser().resolve()
    if not src.exists():
        res = {"ok": False, "erreur": f"Fichier introuvable : {chemin_str}"}
        print(json.dumps(res, ensure_ascii=False))
        return 1

    COLOR_SCHEMES_DIR.mkdir(parents=True, exist_ok=True)
    fichiers_installes = []

    nom_lower = src.name.lower()
    if nom_lower.endswith(".colors"):
        cible = COLOR_SCHEMES_DIR / src.name
        if src.resolve() != cible.resolve():
            shutil.copy2(src, cible)
        fichiers_installes.append(cible)
    elif any(nom_lower.endswith(ext) for ext in [".zip", ".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tar"]):
        try:
            fichiers_installes = extraire_archive(src, COLOR_SCHEMES_DIR)
        except Exception as e:
            res = {"ok": False, "erreur": f"Erreur lors de l'extraction de l'archive : {e}"}
            print(json.dumps(res, ensure_ascii=False))
            return 1
    else:
        # Tenter comme fichier .colors même si l'extension diffère
        try:
            contenu = src.read_text(encoding="utf-8", errors="ignore")
            if "[Colors:Window]" in contenu or "[General]" in contenu:
                nom = src.stem + ".colors"
                cible = COLOR_SCHEMES_DIR / nom
                if src.resolve() != cible.resolve():
                    shutil.copy2(src, cible)
                fichiers_installes.append(cible)
            else:
                res = {"ok": False, "erreur": "Le fichier sélectionné n'est ni un schéma .colors ni une archive reconnue."}
                print(json.dumps(res, ensure_ascii=False))
                return 1
        except Exception as e:
            res = {"ok": False, "erreur": f"Impossible de lire le fichier : {e}"}
            print(json.dumps(res, ensure_ascii=False))
            return 1

    if not fichiers_installes:
        res = {"ok": False, "erreur": "Aucun schéma de couleurs (.colors) trouvé dans le fichier."}
        print(json.dumps(res, ensure_ascii=False))
        return 1

    # Le catalogue est tenu par themes_scan : il relit le disque et n'écrit dans
    # style_vars.json que le nécessaire. Une erreur ici ne doit pas être avalée :
    # le fichier est installé, mais il ne serait pas listé.
    avertissements = []
    try:
        sys.path.insert(0, str(BASE_DIR))
        import themes_scan
    except Exception as e:
        themes_scan = None
        avertissements.append("themes_scan illisible : %s" % e)
    if themes_scan is not None:
        try:
            themes_scan.synchroniser(silencieux=True)
        except Exception as e:
            avertissements.append("catalogue non relu : %s" % e)

    noms = [f.stem for f in fichiers_installes]

    # Le thème activé est celui du **fichier choisi**, pas « le dernier ajouté »
    # au catalogue : une archive qui contient plusieurs schémas en activait un
    # autre, désigné par l'ordre alphabétique.
    slug_a_activer = None
    if activer and themes_scan is not None:
        try:
            slug_a_activer = themes_scan.slug(fichiers_installes[0])
            themes_scan.activer(slug_a_activer, silencieux=True)
        except (SystemExit, Exception) as e:
            avertissements.append("non activé : %s" % e)
            slug_a_activer = None

    titre_notif = "Thème installé" if len(noms) == 1 else "Thèmes installés"
    corps_notif = f"{', '.join(noms)} a été ajouté à votre liste de thèmes."
    notifier(titre_notif, corps_notif)

    res = {
        "ok": True,
        "fichiers": [str(f) for f in fichiers_installes],
        "noms": noms,
        "actif": slug_a_activer,
        "avertissements": avertissements,
        "message": (
            f"{len(noms)} thème(s) installé(s) avec succès !" if not avertissements
            else f"{len(noms)} thème(s) copié(s), avec réserve : " + " ; ".join(avertissements)
        )
    }
    print(json.dumps(res, ensure_ascii=False))
    return 0


def main():
    parser = argparse.ArgumentParser(description="Installe un schéma de couleurs (.colors) ou une archive.")
    parser.add_argument("fichier", help="Chemin vers le fichier .colors ou archive à installer")
    parser.add_argument("--activate", action="store_true", help="Active immédiatement le thème installé")
    args = parser.parse_args()

    return installer(args.fichier, activer=args.activate)


if __name__ == "__main__":
    sys.exit(main())
