#!/usr/bin/env python3
"""Peinture du masque de parallaxe : transforme des traits en PNG.

Le panneau envoie sur l'entrée standard un JSON de traits en coordonnées
normalisées (0–1) :

    [{"points": [[0.1, 0.2], [0.12, 0.24], ...], "taille": 90}, ...]

On rastérise à la taille de l'écran : blanc sur fond transparent, bord adouci.
L'alpha du fichier est la sélection — 255 là où l'objet passe devant, 0
ailleurs — et c'est exactement ce que lit `parallaxe_layers.py --masque-de`.

Ce détour par Python existe parce que l'export d'un Canvas QML plein écran est
peu commode et difficile à vérifier ; ici le résultat est reproductible et
testable depuis un terminal.
"""
import argparse
import json
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sortie", required=True, help="PNG à écrire")
    ap.add_argument("--ecran", default="1920x1080", metavar="LxH")
    ap.add_argument("--douceur", type=float, default=0.15,
                    help="rayon du flou de bord, en fraction du pinceau")
    a = ap.parse_args()

    try:
        largeur, hauteur = (int(v) for v in a.ecran.lower().split("x"))
    except ValueError:
        sys.exit("--ecran attend LARGEURxHAUTEUR, par exemple 1920x1080")

    brut = sys.stdin.read().strip()
    if brut == "":
        sys.exit("aucun trait sur l'entrée standard")
    try:
        traits = json.loads(brut)
    except json.JSONDecodeError as e:
        sys.exit("traits illisibles : %s" % e)
    if not isinstance(traits, list):
        sys.exit("les traits doivent être une liste")

    from PIL import Image, ImageDraw, ImageFilter

    masque = Image.new("L", (largeur, hauteur), 0)
    dessin = ImageDraw.Draw(masque)
    rayons = []

    for trait in traits:
        points = trait.get("points") or []
        if not points:
            continue
        r = max(1.0, float(trait.get("taille", 60)) * max(largeur, hauteur) / 1920.0 / 2.0)
        rayons.append(r)
        pts = [(float(x) * largeur, float(y) * hauteur) for x, y in points]
        # Un disque par point (le geste est échantillonné par le panneau), puis
        # des segments entre les points pour ne pas laisser de jours.
        for x, y in pts:
            dessin.ellipse((x - r, y - r, x + r, y + r), fill=255)
        for i in range(1, len(pts)):
            dessin.line((pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]),
                        fill=255, width=int(2 * r))

    if a.douceur > 0 and rayons:
        # Le bord doux n'est pas un détail : c'est lui qui donne la couche
        # intermédiaire. Une sélection à bord net bascule d'un coup du lointain
        # au proche et la parallaxe saute.
        masque = masque.filter(ImageFilter.GaussianBlur(max(2.0, a.douceur * sum(rayons) / len(rayons))))

    sortie = Path(a.sortie).expanduser()
    sortie.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (largeur, hauteur), (255, 255, 255, 0))
    image.putalpha(masque)
    image.save(sortie, format="PNG", optimize=True)
    print(json.dumps({"ok": True, "masque": str(sortie), "traits": len(traits)}))


if __name__ == "__main__":
    main()
