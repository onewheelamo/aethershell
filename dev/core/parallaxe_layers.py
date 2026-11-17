#!/usr/bin/env python3
"""Découpe un fond d'écran en trois calques de parallaxe à partir de sa carte
de profondeur.

Combine :
- Profondeur 3D haute résolution (Depth Anything V2 Small en 924×518 16:9)
- Détourage haute précision BiRefNet-lite FP16 (optionnel, géré via `status|setup|remove`)
- Affinage chromatique RGB des contours (pétales, antennes, sans trous dans les bâtiments)
- Inpainting horizontal pondéré par la distance (zéro tache grise derrière les sujets)

Usage :
    python3 parallaxe_layers.py status | setup | remove
    python3 parallaxe_layers.py generate --wallpaper FOND.png [--out DOSSIER]
                                         [--seuil-bas 30] [--seuil-haut 65]
                                         [--ecran 1920x1080] [--masque-de MASQUE.png]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ICI = Path(__file__).resolve().parent
NOMS = ("1-lointain.png", "2-moyen.png", "3-proche.png")
DATA_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "depth"
VENV_PYTHON = DATA_DIR / "runtime" / "bin" / "python"
MODELS_DIR = DATA_DIR / "models"
BIREFNET_MODEL = MODELS_DIR / "birefnet-lite-fp16.onnx"
LEGACY_RMBG_MODEL = MODELS_DIR / "rmbg-1.4.onnx"
BIREFNET_URL = (
    "https://huggingface.co/onnx-community/BiRefNet_lite/resolve/main/onnx/model_fp16.onnx"
)
TAILLE_MIN = 100_000_000  # ~218 Mo


def _se_reexecuter_dans_le_venv():
    """Bascule dans le venv partagé avec depth_mask.py."""
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


def statut() -> int:
    ok_biref = BIREFNET_MODEL.is_file() and BIREFNET_MODEL.stat().st_size >= TAILLE_MIN
    if not ok_biref and LEGACY_RMBG_MODEL.is_file():
        LEGACY_RMBG_MODEL.unlink(missing_ok=True)
    taille_mo = round(BIREFNET_MODEL.stat().st_size / (1024 * 1024), 1) if ok_biref else 0.0
    print(json.dumps({
        "ok": True,
        "rmbg": ok_biref,
        "installed": ok_biref,
        "model": "BiRefNet-lite FP16 + Depth V2 HD" if ok_biref else "Depth Anything V2 Small HD",
        "path": str(BIREFNET_MODEL),
        "size_mb": taille_mo,
    }), flush=True)
    return 0


def installer() -> int:
    # S'assure d'abord que le runtime et Depth Anything V2 sont prêts
    subprocess.run([sys.executable, str(ICI / "depth_mask.py"), "setup"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    if LEGACY_RMBG_MODEL.is_file():
        LEGACY_RMBG_MODEL.unlink(missing_ok=True)

    if BIREFNET_MODEL.is_file() and BIREFNET_MODEL.stat().st_size >= TAILLE_MIN:
        return statut()

    tmp = BIREFNET_MODEL.with_suffix(".part")
    tmp.unlink(missing_ok=True)
    try:
        req = urllib.request.Request(BIREFNET_URL, headers={"User-Agent": "AetherShell/1.0"})
        with urllib.request.urlopen(req, timeout=300) as r, tmp.open("wb") as f:
            while True:
                chunk = r.read(256 * 1024)
                if not chunk:
                    break
                f.write(chunk)
        if tmp.stat().st_size < TAILLE_MIN:
            raise RuntimeError("téléchargement incomplet")
        os.replace(tmp, BIREFNET_MODEL)
        # Invalide les masques bruts en cache pour forcer l'usage de BiRefNet
        subprocess.run([sys.executable, str(ICI / "depth_mask.py"), "clear-cache"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return statut()
    except Exception as exc:
        tmp.unlink(missing_ok=True)
        print(json.dumps({"ok": False, "rmbg": False, "error": str(exc)}), flush=True)
        return 1


def supprimer() -> int:
    for p in (BIREFNET_MODEL, BIREFNET_MODEL.with_suffix(".part"), LEGACY_RMBG_MODEL):
        p.unlink(missing_ok=True)
    subprocess.run([sys.executable, str(ICI / "depth_mask.py"), "clear-cache"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return statut()


def masque_pour(fond, peint=None):
    """Rend la carte qui décide des plans : masque peint s'il existe, sinon profondeur."""
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
        d = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
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
    """Redimensionne en « cover » : remplit l'écran, recadre au centre."""
    _, Image = _numpy()
    l, h = image.size
    if (l, h) == (largeur, hauteur):
        return image
    echelle = max(largeur / l, hauteur / h)
    nl, nh = round(l * echelle), round(h * echelle)
    redim = image.resize((nl, nh), Image.LANCZOS)
    x = (nl - largeur) // 2
    y = (nh - hauteur) // 2
    return redim.crop((x, y, x + largeur, y + hauteur))


def _inpaint_rgb(image_rgb, masque_trou, rayon_dilat=11):
    """Reconstruit les zones occultées par propagation horizontale pondérée des
    couleurs de bord gauche/droit sur chaque ligne de balayage.
    Élimine 100 % des halos gris laissés par une initialisation à la couleur moyenne.
    """
    np, Image = _numpy()
    from PIL import ImageFilter

    arr = np.asarray(image_rgb, dtype=np.float32)
    h, w, _ = arr.shape
    m_u8 = (np.asarray(masque_trou, dtype=np.uint8) * 255)
    k = max(3, int(rayon_dilat) | 1)
    m_dil_pil = Image.fromarray(m_u8, mode="L").filter(ImageFilter.MaxFilter(k))
    m_dil = np.asarray(m_dil_pil, dtype=np.float32) / 255.0

    hole = m_dil > 0.5
    if not np.any(hole):
        return image_rgb

    valid = ~hole
    idx = np.arange(w, dtype=np.int32)[None, :]

    left_idx = np.where(valid, idx, 0)
    np.maximum.accumulate(left_idx, axis=1, out=left_idx)
    has_left = np.maximum.accumulate(valid.astype(np.int8), axis=1) > 0

    right_idx = np.where(valid, idx, w - 1)
    right_idx = np.minimum.accumulate(right_idx[:, ::-1], axis=1)[:, ::-1]
    has_right = np.maximum.accumulate(valid[:, ::-1].astype(np.int8), axis=1)[:, ::-1] > 0

    rows = np.arange(h, dtype=np.int32)[:, None]
    left_col = arr[rows, left_idx]
    right_col = arr[rows, right_idx]

    dist_l = np.maximum(1.0, (idx - left_idx).astype(np.float32))
    dist_r = np.maximum(1.0, (right_idx - idx).astype(np.float32))

    wl = np.where(has_left, 1.0 / dist_l, 0.0)
    wr = np.where(has_right, 1.0 / dist_r, 0.0)
    wsum = wl + wr
    both_missing = wsum < 1e-6
    wsum = np.where(both_missing, 1.0, wsum)

    fill = (left_col * wl[:, :, None] + right_col * wr[:, :, None]) / wsum[:, :, None]
    if np.any(both_missing):
        med = np.median(arr.reshape(-1, 3), axis=0).astype(np.float32)
        fill[both_missing] = med

    fill_im = Image.fromarray(np.clip(fill, 0, 255).astype(np.uint8), mode="RGB")
    fill_im = fill_im.resize((max(16, w // 4), max(16, h // 4)), Image.BILINEAR)
    fill_im = fill_im.filter(ImageFilter.GaussianBlur(radius=3.5))
    up_fill = np.asarray(fill_im.resize((w, h), Image.BILINEAR), dtype=np.float32)

    soft_m = np.asarray(m_dil_pil.filter(ImageFilter.GaussianBlur(radius=4.0)), dtype=np.float32) / 255.0
    soft_m = soft_m[:, :, None]
    blended = arr * (1.0 - soft_m) + up_fill * soft_m
    return Image.fromarray(np.clip(blended, 0, 255).astype(np.uint8), mode="RGB")


def generate(fond, sortie, seuil_bas, seuil_haut, masque_de=None, ecran=None):
    np, Image = _numpy()
    sys.path.insert(0, str(ICI))
    import depth_mask

    fond = Path(fond).expanduser().resolve()
    if not fond.exists():
        sys.exit("fond introuvable : " + str(fond))

    chemin_masque = masque_pour(fond, masque_de)
    rgb = Image.open(fond).convert("RGB")
    if ecran:
        rgb = _cover(rgb, int(ecran[0]), int(ecran[1]))
    sortie = Path(sortie).expanduser().resolve()
    sortie.mkdir(parents=True, exist_ok=True)

    masque_peint = bool(masque_de and Path(masque_de).expanduser().is_file())
    with Image.open(chemin_masque) as _m:
        if _m.mode in ("RGBA", "LA") or (_m.mode == "P" and "transparency" in _m.info):
            alpha = _m.convert("RGBA").getchannel("A")
        else:
            alpha = _m.convert("L")
    if alpha.size != rgb.size:
        alpha = _cover(alpha, rgb.size[0], rgb.size[1]) if ecran else alpha.resize(rgb.size, Image.LANCZOS)

    a = np.asarray(alpha, dtype=np.float32) / 255.0
    h, w = a.shape

    if masque_peint:
        proche = _lissage(a, (seuil_haut - 10) / 100.0, (seuil_haut + 5) / 100.0)
        moyen = np.clip(_lissage(a, (seuil_bas - 5) / 100.0, (seuil_bas + 10) / 100.0) - proche, 0.0, 1.0)
    else:
        # Détection sujet isolé (ex. X-Wing sur fond rayé, où le plan moyen [0.22..0.48] est quasi vide)
        # vs scène multi-plans (ex. paysage/ville avec premier plan, plan moyen et horizon)
        part_fond = float((a < 0.22).mean())
        part_moyen = float(((a >= 0.22) & (a <= 0.48)).mean())
        est_sujet_isole = part_fond > 0.54 and part_moyen < 0.10
        if est_sujet_isole:
            proche = _lissage(a, 0.25, 0.42)
            if not (BIREFNET_MODEL.is_file() and BIREFNET_MODEL.stat().st_size >= TAILLE_MIN):
                proche = depth_mask.affiner_contour_rgb(rgb, proche, halo_px=10, color_thresh=0.09)
            proche = np.clip((proche - 0.04) / 0.92, 0.0, 1.0)
            moyen = np.zeros_like(proche)
        else:
            s_haut_lo = max(0.42, (seuil_haut - 17) / 100.0)
            s_haut_hi = min(0.72, (seuil_haut - 7) / 100.0)
            proche_brut = _lissage(a, s_haut_lo, s_haut_hi)

            # Évite qu'une bande d'eau/sol tout en bas sur toute la largeur ne coupe les reflets du plan moyen
            couv_bas = float((proche_brut[int(h * 0.90):, :] > 0.5).mean())
            couv_milieu = float((proche_brut[int(h * 0.45):int(h * 0.75), :] > 0.5).mean())
            if couv_bas > 0.70 and couv_milieu < 0.25:
                yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
                att_bas = 1.0 - _lissage(yy, 0.80, 0.90)
                proche_brut = proche_brut * att_bas

            # Passe 1 : propage le long des rameaux/antennes (contraste fort) avec porte 3D
            porte_3d = np.clip((a - 0.10) / 0.08, 0.0, 1.0)
            proche = depth_mask.affiner_contour_rgb(
                rgb, proche_brut, halo_px=18, color_thresh=0.075, passes=6, porte_profondeur=porte_3d
            )
            # Passe 2 : rattache tous les rameaux terminaux et pétales proches des branches (jusqu'aux pointes)
            porte_ciel = np.ones((h, w), dtype=np.float32)
            porte_ciel[int(h * 0.56):, :] = porte_3d[int(h * 0.56):, :]
            proche = depth_mask.affiner_contour_rgb(
                rgb, proche, halo_px=20, color_thresh=0.068, passes=5, porte_profondeur=porte_ciel
            )
            proche = np.clip((proche - 0.06) / 0.88, 0.0, 1.0)

            s_bas_lo = max(0.14, (seuil_bas - 12) / 100.0)
            s_bas_hi = max(s_bas_lo + 0.08, (seuil_bas - 2) / 100.0)
            fg_total_brut = _lissage(a, s_bas_lo, s_bas_hi)
            fg_total = depth_mask.affiner_contour_rgb(rgb, fg_total_brut, halo_px=12, color_thresh=0.085)
            fg_total = np.maximum(fg_total, proche)
            moyen = np.clip(fg_total - proche, 0.0, 1.0)

    rgb_lointain = _inpaint_rgb(rgb, (moyen + proche) > 0.15, rayon_dilat=11)
    rgb_moyen = _inpaint_rgb(rgb, proche > 0.15, rayon_dilat=9) if np.any(moyen > 0.05) else rgb

    poids_lointain = np.ones_like(proche)
    poids_moyen = moyen
    poids_proche = proche

    for nom, img_base, poids in zip(NOMS, (rgb_lointain, rgb_moyen, rgb), (poids_lointain, poids_moyen, poids_proche)):
        calque = img_base.copy()
        calque.putalpha(Image.fromarray(np.rint(poids * 255.0).astype(np.uint8)))
        calque.save(sortie / nom, format="PNG", optimize=True)
        print("  %s  %s" % (nom, (sortie / nom).stat().st_size // 1024), "Kio")


def main():
    _se_reexecuter_dans_le_venv()
    if len(sys.argv) >= 2 and sys.argv[1] in ("status", "setup", "remove"):
        cmd = sys.argv[1]
        if cmd == "status":
            raise SystemExit(statut())
        if cmd == "setup":
            raise SystemExit(installer())
        if cmd == "remove":
            raise SystemExit(supprimer())

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
