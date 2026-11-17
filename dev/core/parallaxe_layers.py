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
import os
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
NOMS = ("1-lointain.png", "2-moyen.png", "3-proche.png")
# Runtime partagé avec depth_mask.py : c'est lui qui porte numpy et Pillow.
DATA_DIR = Path.home() / ".cache" / "quickshell" / "depth"
VENV_PYTHON = DATA_DIR / "runtime" / "bin" / "python"


def _se_reexecuter_dans_le_venv():
    """Bascule dans le venv quand c'est lui qui porte numpy et Pillow.

    Le shell appelle ce script avec le Python du système, qui n'a pas ces
    modules : sans cette bascule la génération échouerait alors que le runtime
    est installé. La garde sur `sys.prefix` empêche la boucle (le python du venv
    est un lien vers celui de base, donc `sys.executable` ne distingue rien).
    """
    try:
        import numpy  # noqa: F401
        from PIL import Image  # noqa: F401
        return
    except Exception:
        pass
    if not VENV_PYTHON.is_file():
        return
    if Path(sys.prefix).resolve() == (DATA_DIR / "runtime").resolve():
        return
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])


def _numpy():
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        sys.exit("numpy et Pillow sont nécessaires (python3 -m pip install numpy pillow)")
    return np, Image


def masque_pour(fond, peint=None):
    """Rend la carte qui décide des plans : masque peint s'il existe, sinon profondeur.

    Le masque peint à la main (pinceau du panneau) est une image à fond
    transparent dont l'alpha vaut 255 là où l'utilisateur a jugé que l'objet est
    devant : il fait foi, sans passer par le modèle. Sinon on demande à
    depth_mask.py sa carte **continue** — pas le masque binarisé : le découpage a
    besoin de la gradation réelle, car sur une carte binaire la bande
    intermédiaire est vide et tout bascule d'un cran.
    """
    if peint:
        peint = Path(peint).expanduser()
        if peint.is_file():
            return peint
    cmd = [sys.executable, str(ICI / "depth_mask.py"), "generate",
           "--wallpaper", str(fond), "--brut"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("depth_mask.py a échoué : " + (r.stderr.strip() or r.stdout.strip())[:300])
    try:
        d = json.loads(r.stdout.strip())
    except json.JSONDecodeError:
        sys.exit("réponse illisible de depth_mask.py : " + r.stdout[:200])
    if not d.get("ok"):
        sys.exit("carte de profondeur indisponible : " + str(d.get("error")))
    return Path(d["brut"])


def _lissage(a, bas, haut):
    """Montée douce entre deux seuils (0 en bas, 1 en haut), sans marche dure."""
    np, _ = _numpy()
    if haut <= bas:
        return (a >= haut).astype(float)
    t = np.clip((a - bas) / (haut - bas), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _cover(image, largeur, hauteur):
    """Redimensionne en « cover » : remplit l'écran, recadre au centre.

    C'est le cadrage du démon de fond (awww recadre en crop). Mesuré contre une
    capture du compositeur : écart moyen 0,7 sur 255 avec LANCZOS — largement
    sous le seuil visible, alors qu'un redimensionnement par Qt dans la surface
    laissait 187. C'est ce qui permet de produire les calques depuis le fichier
    du fond, sans capture ni bureau vide.
    """
    _, Image = _numpy()
    ratio = max(largeur / image.width, hauteur / image.height)
    taille = (round(image.width * ratio), round(image.height * ratio))
    red = image.resize(taille, Image.LANCZOS)
    x = (red.width - largeur) // 2
    y = (red.height - hauteur) // 2
    return red.crop((x, y, x + largeur, y + hauteur))


def _inpaint_rgb(rgb_img, mask_bool):
    """Comble les zones masquées (derrière un avant-plan) sans dépendance externe.
    Utilise cv2.inpaint si présent, sinon une pyramide multi-échelle Pillow/numpy."""
    np, Image = _numpy()
    from PIL import ImageFilter

    if not np.any(mask_bool):
        return rgb_img

    # Dilate légèrement le masque pour absorber le halo de contour (3 px)
    m_img = Image.fromarray((mask_bool.astype(np.uint8) * 255), mode="L")
    m_dil = m_img.filter(ImageFilter.MaxFilter(7))
    dil_bool = np.asarray(m_dil) > 127

    try:
        import cv2  # type: ignore
        bgr = np.asarray(rgb_img, dtype=np.uint8)[:, :, ::-1]
        res = cv2.inpaint(bgr, (dil_bool.astype(np.uint8) * 255), 5, cv2.INPAINT_TELEA)
        return Image.fromarray(res[:, :, ::-1], mode="RGB")
    except Exception:
        pass

    arr = np.asarray(rgb_img, dtype=np.float32).copy()
    h, w = arr.shape[:2]
    # Pyramide rapide 1/8 -> diffusion itérative -> remontée douce
    sw, sh = max(32, w // 8), max(32, h // 8)
    small_rgb = np.asarray(rgb_img.resize((sw, sh), Image.BILINEAR), dtype=np.float32)
    small_m = np.asarray(m_dil.resize((sw, sh), Image.NEAREST)) > 127

    valid = ~small_m
    work = small_rgb.copy()
    if np.any(valid):
        mean_col = work[valid].mean(axis=0)
        work[small_m] = mean_col
        for _ in range(28):
            up = np.roll(work, 1, axis=0)
            dn = np.roll(work, -1, axis=0)
            lf = np.roll(work, 1, axis=1)
            rt = np.roll(work, -1, axis=1)
            avg = 0.25 * (up + dn + lf + rt)
            work[small_m] = avg[small_m]

    up_fill = np.asarray(
        Image.fromarray(np.clip(work, 0, 255).astype(np.uint8), mode="RGB")
        .resize((w, h), Image.BILINEAR)
        .filter(ImageFilter.GaussianBlur(radius=3)),
        dtype=np.float32,
    )
    # Adoucir la transition sur 2 px autour du trou
    soft_m = np.asarray(m_dil.filter(ImageFilter.GaussianBlur(radius=2)), dtype=np.float32) / 255.0
    soft_m = soft_m[:, :, None]
    blended = arr * (1.0 - soft_m) + up_fill * soft_m
    return Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8), mode="RGB")


def generate(fond, sortie, seuil_bas, seuil_haut, masque_de=None, ecran=None):
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

    chemin_masque = masque_pour(fond, masque_de)
    rgb = Image.open(fond).convert("RGB")
    if ecran:
        rgb = _cover(rgb, int(ecran[0]), int(ecran[1]))
    sortie = Path(sortie).expanduser()
    sortie.mkdir(parents=True, exist_ok=True)
    # Masque peint : l'alpha porte la sélection (le fond est transparent).
    # Carte du modèle : les niveaux de gris.
    with Image.open(chemin_masque) as _m:
        if _m.mode in ("RGBA", "LA") or (_m.mode == "P" and "transparency" in _m.info):
            alpha = _m.convert("RGBA").getchannel("A")
        else:
            alpha = _m.convert("L")
    if alpha.size != rgb.size:
        alpha = alpha.resize(rgb.size, Image.LANCZOS)

    a = np.asarray(alpha, dtype=float) / 255.0
    proche = _lissage(a, (seuil_haut - 10) / 100.0, (seuil_haut + 5) / 100.0)
    moyen = np.clip(_lissage(a, (seuil_bas - 5) / 100.0, (seuil_bas + 10) / 100.0) - proche, 0.0, 1.0)

    # Inpainting des plans arrière pour éviter tout trou/halo lors du décalage parallaxe :
    # - 1-lointain : fond opaque comblé derrière moyen + proche
    # - 2-moyen    : comblé derrière proche, avec alpha étendu sous proche
    # - 3-proche   : pixels originaux intacts
    rgb_lointain = _inpaint_rgb(rgb, (moyen + proche) > 0.25)
    rgb_moyen = _inpaint_rgb(rgb, proche > 0.25)

    poids_lointain = np.ones_like(proche)
    poids_moyen = np.clip(moyen + proche, 0.0, 1.0)
    poids_proche = proche

    sortie = Path(sortie).expanduser().resolve()
    sortie.mkdir(parents=True, exist_ok=True)
    for nom, img_base, poids in zip(NOMS, (rgb_lointain, rgb_moyen, rgb), (poids_lointain, poids_moyen, poids_proche)):
        calque = img_base.copy()
        calque.putalpha(Image.fromarray(np.rint(poids * 255.0).astype(np.uint8)))
        calque.save(sortie / nom, format="PNG", optimize=True)
        print("  %s  %s" % (nom, (sortie / nom).stat().st_size // 1024), "Kio")


def main():
    _se_reexecuter_dans_le_venv()
    ap = argparse.ArgumentParser(description="Trois calques de parallaxe depuis une carte de profondeur")
    sous = ap.add_subparsers(dest="cmd", required=True)
    g = sous.add_parser("generate")
    g.add_argument("--wallpaper", required=True)
    g.add_argument("--out", default=str(Path.home() / "Images/wallpapers/profondeur"))
    g.add_argument("--seuil-bas", type=int, default=30)
    g.add_argument("--seuil-haut", type=int, default=65)
    g.add_argument("--ecran", default=None, metavar="LxH",
                   help="taille cible des calques (ex. 1920x1080) ; recadrage cover")
    g.add_argument("--masque-de", default=None,
                   help="image dont on tire la profondeur (par défaut : --wallpaper)")
    a = ap.parse_args()
    if a.cmd == "generate":
        ecran = None
        if a.ecran:
            try:
                l, h = a.ecran.lower().split("x")
                ecran = (int(l), int(h))
            except ValueError:
                sys.exit("--ecran attend LARGEURxHAUTEUR, par exemple 1920x1080")
        generate(a.wallpaper, a.out, a.seuil_bas, a.seuil_haut, a.masque_de, ecran)


if __name__ == "__main__":
    main()
