#!/usr/bin/env python3
"""Masque de premier plan d'un fond d'écran — idée reprise de Noctalia.

Source de l'idée : `noctalia-dev/official-plugins`, plugin `wallpaper_depth`
(MIT) — https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth
Le code ci-dessous est écrit pour AetherShell : même principe (une carte de
profondeur par fond d'écran, seuil et adoucissement réglables), pas la même
mécanique (pas de Luau, cache et CLI propres au projet).

Modèle principal : Depth Anything V2 Small (Apache-2.0), ONNX, évalué en haute
résolution 16:9 (924×518) + affinage local des contours par contraste chromatique RGB.
Modèle optionnel : BiRefNet-lite FP16 (ONNX), fusionné avec la profondeur 3D
lorsqu'il est installé via le panneau.

    depth_mask.py status
    depth_mask.py setup                    # venv + modèle (réseau, ~150 Mo)
    depth_mask.py generate --wallpaper <png> [--threshold 0.30] [--feather 0.08] [--brut]
    depth_mask.py clear-cache
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

MODEL_REVISION = "4472b7362082ad9968fee890ca0f1e5aca36b93d"
MODEL_URL = ("https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/"
             f"{MODEL_REVISION}/onnx/model.onnx?download=true")
MODEL_SHA256 = "afb6a5c28f3b6bf1618c6e43f02073ef9dfdc70e937502d51603e57b0a1df10c"
MODEL_SIZE = 99_060_839
INPUT_SIZE = 924
PATCH = 14
VERSION_DEPTH = 3
VERSION_MASQUE = 13
PACKAGES = ("numpy", "onnxruntime", "pillow")

DATA_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "depth"
VENV_PYTHON = DATA_DIR / "runtime" / "bin" / "python"
MODEL_PATH = DATA_DIR / "models" / "depth-anything-v2-small.onnx"
BIREFNET_PATH = DATA_DIR / "models" / "birefnet-lite-fp16.onnx"
DEPTH_DIR = DATA_DIR / "cache" / "profondeur"
MASQUE_DIR = DATA_DIR / "cache" / "masques"


# ── sortie ───────────────────────────────────────────────────────────────────
def emit(valeur: dict) -> None:
    print(json.dumps(valeur, ensure_ascii=False, separators=(",", ":")), flush=True)


# ── empreintes et fichiers ───────────────────────────────────────────────────
def sha256(chemin: Path) -> str:
    h = hashlib.sha256()
    with chemin.open("rb") as f:
        for bloc in iter(lambda: f.read(1 << 20), b""):
            h.update(bloc)
    return h.hexdigest()


def modele_valide() -> bool:
    return MODEL_PATH.is_file() and MODEL_PATH.stat().st_size == MODEL_SIZE \
        and sha256(MODEL_PATH) == MODEL_SHA256


def runtime_pret() -> bool:
    """Le venv répond-il, ou le Python courant a-t-il déjà tout ?"""
    try:
        import numpy  # noqa: F401
        import onnxruntime  # noqa: F401
        from PIL import Image  # noqa: F401
        return True
    except Exception:
        pass
    if not VENV_PYTHON.is_file():
        return False
    r = subprocess.run([str(VENV_PYTHON), "-c", "import numpy, onnxruntime, PIL"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode == 0


def _se_reexecuter_dans_le_venv() -> None:
    """Bascule dans le venv quand c'est lui qui porte numpy/onnxruntime."""
    try:
        import numpy, onnxruntime  # noqa: F401
        return
    except Exception:
        pass
    if not VENV_PYTHON.is_file():
        return
    if Path(sys.prefix).resolve() == (DATA_DIR / "runtime").resolve():
        return
    os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])


def prune(dossier: Path, maximum: int) -> None:
    if not dossier.is_dir():
        return
    fichiers = sorted((p for p in dossier.iterdir() if p.is_file()),
                      key=lambda p: p.stat().st_mtime_ns, reverse=True)
    for p in fichiers[maximum:]:
        p.unlink(missing_ok=True)


# ── installation ─────────────────────────────────────────────────────────────
def telecharger_modele() -> None:
    MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    partiel = MODEL_PATH.with_suffix(".part")
    partiel.unlink(missing_ok=True)
    requete = urllib.request.Request(MODEL_URL, headers={"User-Agent": "AetherShell/1.0"})
    try:
        with urllib.request.urlopen(requete, timeout=60) as r, partiel.open("wb") as f:
            while bloc := r.read(1 << 20):
                f.write(bloc)
        if partiel.stat().st_size != MODEL_SIZE:
            raise RuntimeError("taille du modèle inattendue : %d octets" % partiel.stat().st_size)
        if sha256(partiel) != MODEL_SHA256:
            raise RuntimeError("empreinte du modèle incorrecte")
        os.replace(partiel, MODEL_PATH)
    finally:
        partiel.unlink(missing_ok=True)


def installer() -> None:
    """Venv isolé + modèle. Rien n'est installé dans le Python du système."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not runtime_pret():
        subprocess.run([sys.executable, "-m", "venv", "--clear", str(DATA_DIR / "runtime")],
                       check=True)
        subprocess.run([str(VENV_PYTHON), "-m", "pip", "install", "--disable-pip-version-check",
                        "--no-input", "--only-binary=:all:", *PACKAGES],
                       stdin=subprocess.DEVNULL, check=True)
    if not modele_valide():
        telecharger_modele()
    emit({"ok": True, "runtime": runtime_pret(), "modele": modele_valide(),
          "cheminModele": str(MODEL_PATH)})


def statut() -> None:
    emit({"ok": True, "runtime": runtime_pret(), "modele": modele_valide(),
          "cheminModele": str(MODEL_PATH), "cache": str(MASQUE_DIR)})


# ── inférence et affinage ────────────────────────────────────────────────────
def taille_inference(largeur: int, hauteur: int) -> tuple[int, int]:
    """Côté long = INPUT_SIZE (924 px), côté court = multiple de 14 respectant le ratio (ex. 518 px)."""
    if largeur >= hauteur:
        ml = INPUT_SIZE
        mh = max(PATCH, round((hauteur / max(1, largeur)) * INPUT_SIZE / PATCH) * PATCH)
    else:
        mh = INPUT_SIZE
        ml = max(PATCH, round((largeur / max(1, hauteur)) * INPUT_SIZE / PATCH) * PATCH)
    return ml, mh


def _box_blur_2d(a, r: int):
    import numpy as np
    if r <= 0:
        return a
    k = 2 * r + 1
    p = np.pad(a, ((r, r), (r, r)), mode="edge")
    cs = np.cumsum(np.pad(p, ((1, 0), (0, 0))), axis=0, dtype=np.float64)
    v = (cs[k:, :] - cs[:-k, :]) / float(k)
    cs2 = np.cumsum(np.pad(v, ((0, 0), (1, 0))), axis=1, dtype=np.float64)
    return ((cs2[:, k:] - cs2[:, :-k]) / float(k)).astype(np.float32)


def _dilate_bin(mask_bin, radius: int):
    if radius <= 0:
        return mask_bin
    return (_box_blur_2d(mask_bin, radius) > 1e-6).astype(mask_bin.dtype)


def _erode_bin(mask_bin, radius: int):
    if radius <= 0:
        return mask_bin
    return (_box_blur_2d(mask_bin, radius) > (1.0 - 1e-6)).astype(mask_bin.dtype)


def affiner_contour_rgb(
    source_rgb,
    mask,
    halo_px: int = 16,
    color_thresh: float = 0.075,
    passes: int = 1,
    porte_profondeur=None,
):
    """Affine la bordure externe d'un masque par contraste chromatique RGB
    avec le fond local immédiat :
    - Ne perce JAMAIS de trous dans les fenêtres de bâtiments ou rayures internes (contrairement au filtre guidé en luminance).
    - Avec `passes > 1`, propage le masque le long des brindilles/antennes fines colorées.
    """
    import numpy as np
    from PIL import Image, ImageFilter

    rgb = np.asarray(source_rgb, dtype=np.float32) / 255.0
    courant = np.asarray(mask, dtype=np.float32)
    r_in = max(1, halo_px // 4)
    r_out = max(2, halo_px)
    r_ero = 3
    r_est = max(12, halo_px * 2)

    for _ in range(max(1, passes)):
        m_bin = (courant > 0.40).astype(np.float32)
        dil_inner = _dilate_bin(m_bin, r_in)
        dil_outer = _dilate_bin(m_bin, r_out)
        eroded = _erode_bin(m_bin, r_ero)

        bg_weight = 1.0 - dil_inner
        w_blur = np.maximum(_box_blur_2d(bg_weight, r_est), 1e-4)

        bg_rgb = np.zeros_like(rgb)
        for c in range(3):
            bg_rgb[:, :, c] = _box_blur_2d(rgb[:, :, c] * bg_weight, r_est) / w_blur

        dist = np.sqrt(np.sum((rgb - bg_rgb) ** 2, axis=2))
        halo_zone = np.clip(dil_outer - eroded, 0.0, 1.0)
        contrast_alpha = np.clip((dist - color_thresh) / 0.06, 0.0, 1.0)
        ajout = halo_zone * contrast_alpha
        if porte_profondeur is not None:
            ajout = ajout * porte_profondeur
        courant = np.maximum(courant, ajout)

    ref_pil = Image.fromarray((np.clip(courant, 0.0, 1.0) * 255.0).astype(np.uint8), mode="L")
    ref_pil = ref_pil.filter(ImageFilter.GaussianBlur(radius=1.15))
    return np.asarray(ref_pil, dtype=np.float32) / 255.0


def _ort_options():
    import onnxruntime as ort
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    return options


def _inferer_birefnet(source, ml_cible: int, mh_cible: int, cache_path: Path | None = None):
    """Exécute BiRefNet-lite FP16 s'il est installé dans ~/.cache/quickshell/depth/models/."""
    if not (BIREFNET_PATH.is_file() and BIREFNET_PATH.stat().st_size > 100_000_000):
        return None
    try:
        import numpy as np
        import onnxruntime as ort
        from PIL import Image

        if cache_path is not None and cache_path.is_file():
            try:
                cached = np.load(cache_path, allow_pickle=False)
                if cached.shape == (mh_cible, ml_cible):
                    return cached.astype(np.float32)
            except Exception:
                cache_path.unlink(missing_ok=True)

        im = source.resize((1024, 1024), Image.Resampling.BILINEAR)
        arr = np.asarray(im, dtype=np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        x = ((arr - mean) / std).transpose(2, 0, 1)[None].astype(np.float16)

        sess = ort.InferenceSession(str(BIREFNET_PATH), sess_options=_ort_options(),
                                    providers=["CPUExecutionProvider"])
        out = sess.run(None, {sess.get_inputs()[0].name: x})[-1]
        pred = np.squeeze(out).astype(np.float32)
        prob = 1.0 / (1.0 + np.exp(-np.clip(pred, -30.0, 30.0)))
        pmin, pmax = float(prob.min()), float(prob.max())
        if pmax - pmin > 1e-6:
            prob = (prob - pmin) / (pmax - pmin)
        prob_im = Image.fromarray((prob * 255.0).astype(np.uint8), mode="L").resize(
            (ml_cible, mh_cible), Image.Resampling.BICUBIC
        )
        res = np.asarray(prob_im, dtype=np.float32) / 255.0
        if cache_path is not None:
            try:
                with tempfile.NamedTemporaryFile("wb", dir=cache_path.parent, delete=False) as f:
                    np.save(f, res.astype(np.float16), allow_pickle=False)
                    tmp = Path(f.name)
                os.replace(tmp, cache_path)
            except Exception:
                pass
        return res
    except Exception:
        return None


def _fusionner_profondeur_et_contours(source, profondeur, biref_cache: Path | None = None):
    """Produit la carte de profondeur continue pleine résolution [0..1] sans trous internes."""
    import numpy as np
    from PIL import Image

    l, h = source.size
    pleine = np.asarray(
        Image.fromarray((np.clip(profondeur, 0.0, 1.0) * 255.0).astype(np.uint8), mode="L")
        .resize((l, h), Image.Resampling.BICUBIC),
        dtype=np.float32,
    ) / 255.0

    biref = _inferer_birefnet(source, l, h, biref_cache)
    if biref is not None:
        ratio_fond_3d = float((pleine < 0.22).mean())
        couv_biref = float((biref > 0.5).mean())
        if ratio_fond_3d > 0.54 and 0.03 < couv_biref < 0.48:
            # Sujet isolé (ex. X-Wing, personnage/droïde) : la silhouette BiRefNet
            # donne le contour exact, filtré par la présence 3D (d > 0.14)
            # pour exclure tout élément plat du fond.
            porte_3d = np.clip((pleine - 0.14) / 0.10, 0.0, 1.0)
            sujet = np.clip((biref * porte_3d - 0.08) / 0.84, 0.0, 1.0)
            return (0.28 + 0.72 * sujet) * (sujet > 0.02).astype(np.float32)

        elif 0.03 < couv_biref < 0.85:
            # Scène multi-plans : complète les rameaux/extrémités fines (pétales, antennes)
            # qui prolongent une zone de premier plan 3D (pleine > 0.48) sur plusieurs passes
            # d'hystérésis, sans jamais toucher aux plans moyens éloignés (pont, horizon).
            fg_seed = (pleine > 0.48).astype(np.float32)
            cand = ((biref > 0.25) & (pleine > 0.14)).astype(np.float32)
            for _ in range(4):
                dil = _dilate_bin(fg_seed, 32)
                fg_seed = np.maximum(fg_seed, dil * cand)
            pleine = np.maximum(pleine, fg_seed * np.maximum(biref, 0.85) * 0.92)

    # Scène multi-plans ou sans BiRefNet : conserve les plans 3D (lointain / moyen / proche)
    return np.clip(pleine, 0.0, 1.0).astype(np.float32)


def generer(fond: Path, seuil: float, adouci: float, brut: bool = False) -> None:
    if not fond.is_file():
        raise RuntimeError("fond introuvable : %s" % fond)
    if not modele_valide():
        raise RuntimeError("modèle absent ou invalide — lancer `setup`")
    if not runtime_pret():
        raise RuntimeError("runtime absent — lancer `setup`")

    seuil = min(1.0, max(0.0, seuil))
    adouci = min(0.5, max(0.0, adouci))
    debut = time.monotonic()

    import numpy as np
    import onnxruntime as ort
    from PIL import Image

    empreinte = sha256(fond)
    biref_tag = "b1" if (BIREFNET_PATH.is_file() and BIREFNET_PATH.stat().st_size > 100_000_000) else "b0"
    cle = "%s-m%s-d%d-i%d-%s" % (empreinte, MODEL_SHA256[:16], VERSION_DEPTH, INPUT_SIZE, biref_tag)
    DEPTH_DIR.mkdir(parents=True, exist_ok=True)
    MASQUE_DIR.mkdir(parents=True, exist_ok=True)
    chemin_profondeur = DEPTH_DIR / ("%s.npy" % cle)
    chemin_biref = DEPTH_DIR / ("%s-biref.npy" % empreinte)
    cle_masque = "%s-v%d-t%.4f-f%.4f" % (cle, VERSION_MASQUE, seuil, adouci)
    chemin_masque = MASQUE_DIR / ("%s.png" % cle_masque)
    chemin_brut = MASQUE_DIR / ("%s-brut-v%d.png" % (cle, VERSION_MASQUE))

    try:
        os.nice(10)
    except OSError:
        pass

    verrou = (DATA_DIR / "runtime" / "generation.lock").open("w")
    try:
        import fcntl
        fcntl.flock(verrou, fcntl.LOCK_EX)

        cache = chemin_profondeur.is_file()
        with Image.open(fond) as img:
            source = img.convert("RGB")
            l, h = source.size
            ml, mh = taille_inference(l, h)
            if cache:
                profondeur = np.load(chemin_profondeur, allow_pickle=False)
                if profondeur.shape != (mh, ml):
                    chemin_profondeur.unlink(missing_ok=True)
                    cache = False
            if not cache:
                reduit = source.resize((ml, mh), Image.Resampling.BICUBIC)
                pixels = np.asarray(reduit, dtype=np.float32) / 255.0
                pixels = (pixels - np.array([0.485, 0.456, 0.406], dtype=np.float32)) \
                    / np.array([0.229, 0.224, 0.225], dtype=np.float32)
                tenseur = np.transpose(pixels, (2, 0, 1))[None, ...]
                session = ort.InferenceSession(str(MODEL_PATH), sess_options=_ort_options(),
                                               providers=["CPUExecutionProvider"])
                nom = session.get_inputs()[0].name
                brut_out = np.asarray(session.run(None, {nom: tenseur})[0], dtype=np.float32).squeeze()
                if brut_out.shape != (mh, ml):
                    raise RuntimeError("sortie du modèle de forme inattendue : %s" % (brut_out.shape,))
                mini = float(np.percentile(brut_out, 1.5))
                maxi = float(np.percentile(brut_out, 99.2))
                if not np.isfinite(mini) or not np.isfinite(maxi) or maxi <= mini:
                    raise RuntimeError("carte de profondeur invalide")
                profondeur = np.clip((brut_out - mini) / (maxi - mini), 0.0, 1.0)
                with tempfile.NamedTemporaryFile("wb", dir=DEPTH_DIR, delete=False) as f:
                    np.save(f, profondeur, allow_pickle=False)
                    temporaire = Path(f.name)
                os.replace(temporaire, chemin_profondeur)

            if brut and not chemin_brut.is_file():
                pleine = _fusionner_profondeur_et_contours(source, profondeur, chemin_biref)
                gris = Image.fromarray(np.rint(np.clip(pleine, 0.0, 1.0) * 255.0).astype("uint8"))
                with tempfile.NamedTemporaryFile("wb", dir=MASQUE_DIR, delete=False) as f:
                    gris.save(f, format="PNG", optimize=True)
                    temporaire = Path(f.name)
                os.replace(temporaire, chemin_brut)

            if not brut and not chemin_masque.is_file():
                pleine = _fusionner_profondeur_et_contours(source, profondeur, chemin_biref)
                demi = adouci * 0.5
                alpha = np.clip((pleine - (seuil - demi)) / max(1e-6, 2 * demi), 0.0, 1.0) \
                    if demi > 0 else (pleine >= seuil).astype(np.float32)
                alpha = alpha * alpha * (3.0 - 2.0 * alpha)
                if float((pleine < 0.20).mean()) <= 0.54:
                    porte_3d = np.clip((pleine - 0.10) / 0.08, 0.0, 1.0)
                    porte_ciel = np.ones((h, l), dtype=np.float32)
                    porte_ciel[int(h * 0.56):, :] = porte_3d[int(h * 0.56):, :]
                    alpha = affiner_contour_rgb(
                        source, alpha, halo_px=18, color_thresh=0.070, passes=5, porte_profondeur=porte_ciel
                    )
                alpha = np.clip((alpha - 0.06) / 0.88, 0.0, 1.0)

                masque = Image.fromarray(np.rint(alpha * 255.0).astype(np.uint8))
                image = source.copy().convert("RGBA")
                image.putalpha(masque)
                with tempfile.NamedTemporaryFile("wb", dir=MASQUE_DIR, delete=False) as f:
                    image.save(f, format="PNG", optimize=True)
                    temporaire = Path(f.name)
                os.replace(temporaire, chemin_masque)

        prune(DEPTH_DIR, 8)
        prune(MASQUE_DIR, 32)
    finally:
        verrou.close()

    if brut:
        print(json.dumps({"ok": True, "brut": str(chemin_brut)}))
        return

    emit({"ok": True, "cache": cache, "duree_ms": round((time.monotonic() - debut) * 1000),
          "largeur": l, "hauteur": h, "masque": str(chemin_masque), "fond": str(fond)})


def vider_cache() -> None:
    import shutil
    shutil.rmtree(DATA_DIR / "cache", ignore_errors=True)
    emit({"ok": True, "vide": True})


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("commande", choices=("setup", "status", "generate", "clear-cache"))
    p.add_argument("--wallpaper", type=Path)
    p.add_argument("--threshold", type=float, default=0.30)
    p.add_argument("--feather", type=float, default=0.08)
    p.add_argument("--brut", action="store_true",
                   help="écrire la carte de profondeur continue, sans seuil")
    a = p.parse_args()
    try:
        if a.commande == "generate":
            _se_reexecuter_dans_le_venv()
        if a.commande == "setup":
            installer()
        elif a.commande == "status":
            statut()
        elif a.commande == "clear-cache":
            vider_cache()
        else:
            if not a.wallpaper:
                raise RuntimeError("--wallpaper est requis")
            generer(a.wallpaper.expanduser().resolve(), a.threshold, a.feather, a.brut)
        return 0
    except Exception as e:
        print(str(e), file=sys.stderr, flush=True)
        emit({"ok": False, "error": str(e)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
