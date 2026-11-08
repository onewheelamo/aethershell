#!/usr/bin/env python3
"""Découpe un fond d'écran en trois calques de parallaxe à partir de sa carte
de profondeur.

Idée et principe repris du plugin Noctalia `wallpaper_depth`
(https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth,
MIT) : la carte de profondeur dit ce qui est devant. Ici elle sert à découper
l'image en trois plans — lointain, moyen, proche — que `FondProfondeur.qml`
décale différemment quand on change de bureau.

Les trois calques gardent **les pixels du fond** et ne portent que leur poids
dans l'alpha, avec des poids qui somment à 1 : empilés, ils redonnent exactement
l'image d'origine (aucun trou, aucun doublon au repos). Le décalage ne fait
apparaître que ce qui est derrière, jamais de transparence.

Usage :
    python3 parallaxe_layers.py generate --wallpaper FOND.png [--out DOSSIER]
                                        [--seuil-bas 30] [--seuil-haut 65]

Le masque est calculé (ou relu du cache) par `depth_mask.py`, avec les mêmes
seuils que le masque de premier plan : le réglage du panneau vaut pour les deux.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
NOMS = ("1-lointain.png", "2-moyen.png", "3-proche.png")


def _numpy():
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        sys.exit("numpy et Pillow sont nécessaires (python3 -m pip install numpy pillow)")
    return np, Image


def masque_pour(fond, seuil_bas, seuil_haut):
    """Demande son masque à depth_mask.py (cache partagé) et rend son alpha."""
    cmd = [sys.executable, str(ICI / "depth_mask.py"), "generate",
           "--wallpaper", str(fond),
           "--threshold", str(seuil_haut / 100.0),
           "--feather", "0.02"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("depth_mask.py a échoué : " + (r.stderr.strip() or r.stdout.strip())[:300])
    try:
        d = json.loads(r.stdout.strip())
    except json.JSONDecodeError:
        sys.exit("réponse illisible de depth_mask.py : " + r.stdout[:200])
    if not d.get("ok"):
        sys.exit("masque indisponible : " + str(d.get("error")))
    return Path(d["masque"])


def _lissage(a, bas, haut):
    """Montée douce entre deux seuils (0 en bas, 1 en haut), sans marche dure."""
    np, _ = _numpy()
    if haut <= bas:
        return (a >= haut).astype(float)
    t = np.clip((a - bas) / (haut - bas), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def generate(fond, sortie, seuil_bas, seuil_haut, masque_de=None):
    """`fond` est l'image à découper ; `masque_de` est l'image dont on tire la
    carte de profondeur quand les deux diffèrent.

    Le cas d'usage : découper une **capture du bureau** plutôt que le fichier du
    fond. Les pixels sont alors ceux du compositeur, à l'échelle 1:1 ; les
    calques se superposent au fond sans le moindre écart, là où réduire un
    3904×2240 avec le filtre de Qt donnait une image légèrement différente de
    celle d'awww (couture visible sous la barre)."""
    np, Image = _numpy()
    fond = Path(fond).expanduser().resolve()
    if not fond.exists():
        sys.exit("fond introuvable : " + str(fond))

    chemin_masque = masque_pour(Path(masque_de).expanduser() if masque_de else fond,
                                seuil_bas, seuil_haut)
    rgb = Image.open(fond).convert("RGB")
    alpha = Image.open(chemin_masque).getchannel("A")
    if alpha.size != rgb.size:
        alpha = alpha.resize(rgb.size, Image.LANCZOS)

    a = np.asarray(alpha, dtype=float) / 255.0
    proche = _lissage(a, (seuil_haut - 10) / 100.0, (seuil_haut + 5) / 100.0)
    moyen = np.clip(_lissage(a, (seuil_bas - 5) / 100.0, (seuil_bas + 10) / 100.0) - proche, 0.0, 1.0)
    lointain = np.clip(1.0 - moyen - proche, 0.0, 1.0)

    sortie = Path(sortie).expanduser().resolve()
    sortie.mkdir(parents=True, exist_ok=True)
    for nom, poids in zip(NOMS, (lointain, moyen, proche)):
        calque = rgb.copy()
        calque.putalpha(Image.fromarray(np.rint(poids * 255.0).astype(np.uint8)))
        calque.save(sortie / nom, format="PNG", optimize=True)
        print("  %s  %s" % (nom, (sortie / nom).stat().st_size // 1024), "Kio")


def main():
    ap = argparse.ArgumentParser(description="Trois calques de parallaxe depuis une carte de profondeur")
    sous = ap.add_subparsers(dest="cmd", required=True)
    g = sous.add_parser("generate")
    g.add_argument("--wallpaper", required=True)
    g.add_argument("--out", default=str(Path.home() / "Images/wallpapers/profondeur"))
    g.add_argument("--seuil-bas", type=int, default=30)
    g.add_argument("--seuil-haut", type=int, default=65)
    g.add_argument("--masque-de", default=None,
                   help="image dont on tire la profondeur (par défaut : --wallpaper)")
    a = ap.parse_args()
    if a.cmd == "generate":
        generate(a.wallpaper, a.out, a.seuil_bas, a.seuil_haut, a.masque_de)


if __name__ == "__main__":
    main()
