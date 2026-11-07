#!/usr/bin/env python3
"""Masque de premier plan d'un fond d'écran — idée reprise de Noctalia.

Source de l'idée : `noctalia-dev/official-plugins`, plugin `wallpaper_depth`
(MIT) — https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth
Le code ci-dessous est écrit pour AetherShell : même principe (une carte de
profondeur par fond d'écran, seuil et adoucissement réglables), pas la même
mécanique (pas de Luau, cache et CLI propres au projet).

Ce que ça produit : un PNG en niveaux de gris, à la résolution du fond, où le
blanc est **devant** (premier plan) et le noir derrière. Dessiné au-dessus des
widgets de bureau mais sous les fenêtres, il fait passer les widgets *derrière*
les objets proches du fond — ce que layer-shell ne sait pas faire tout seul.

Modèle : Depth Anything V2 Small (Apache-2.0), ONNX, téléchargé une fois depuis
Hugging Face et vérifié par empreinte. Rien n'est envoyé nulle part : l'inférence
est locale. Le runtime vit dans un venv isolé sous `~/.cache/quickshell/depth/`
pour ne pas toucher au Python du système.

    depth_mask.py status
    depth_mask.py setup                    # venv + modèle (réseau, ~150 Mo)
    depth_mask.py generate --wallpaper <png> [--threshold 30] [--feather 8]
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
INPUT_SIZE = 518
PATCH = 14
VERSION_DEPTH = 1
VERSION_MASQUE = 2
PACKAGES = ("numpy", "onnxruntime", "pillow")

DATA_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "depth"
VENV_PYTHON = DATA_DIR / "runtime" / "bin" / "python"
MODEL_PATH = DATA_DIR / "models" / "depth-anything-v2-small.onnx"
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
    """Bascule dans le venv quand c'est lui qui porte numpy/onnxruntime.

    Le shell appelle ce script avec le Python du système, qui n'a pas ces
    modules : sans cette bascule, `generate` échouerait alors que le runtime est
    installé. La garde sur `sys.executable` empêche la boucle.
    """
    try:
        import numpy, onnxruntime  # noqa: F401
        return
    except Exception:
        pass
    if not VENV_PYTHON.is_file():
        return
    # On regarde `sys.prefix`, pas `sys.executable` : le python du venv est un
    # lien vers le python de base, donc les deux chemins résolus sont égaux alors
    # que les `site-packages` ne le sont pas.
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


# ── inférence ────────────────────────────────────────────────────────────────
def taille_inference(largeur: int, hauteur: int) -> tuple[int, int]:
    echelle = max(INPUT_SIZE / largeur, INPUT_SIZE / hauteur)
    return (max(INPUT_SIZE, round(largeur * echelle / PATCH) * PATCH),
            max(INPUT_SIZE, round(hauteur * echelle / PATCH) * PATCH))


def lisser(valeurs, rayon: int):
    """Moyenne par fenêtre (somme intégrale) — le guide du filtre guidé."""
    import numpy as np

    borde = np.pad(valeurs, ((rayon, rayon), (rayon, rayon)), mode="edge")
    integrale = np.pad(borde, ((1, 0), (1, 0)), mode="constant")
    integrale = np.cumsum(np.cumsum(integrale, axis=0, dtype=np.float64), axis=1, dtype=np.float64)
    d = rayon * 2 + 1
    total = (integrale[d:, d:] - integrale[:-d, d:]
             - integrale[d:, :-d] + integrale[:-d, :-d])
    return (total / (d * d)).astype(np.float32)


def affiner_guide(source, profondeur, max_dim=1920, rayon=8, epsilon=0.001):
    """Filtre guidé : recolle la carte de profondeur aux contours de l'image.

    Sans lui, le masque suit une carte floue de 518 px et bave sur les branches
    fines ; c'est le détail qui fait la différence entre « joli » et « faux ».
    """
    import numpy as np
    from PIL import Image

    l, h = source.size
    echelle = min(1.0, max_dim / max(l, h))
    taille = (max(1, round(l * echelle)), max(1, round(h * echelle)))
    guide = source.convert("L")
    if guide.size != taille:
        guide = guide.resize(taille, Image.Resampling.LANCZOS)
    guide = np.asarray(guide, dtype=np.float32) / 255.0
    grossier = np.asarray(Image.fromarray(profondeur).resize(taille, Image.Resampling.BICUBIC),
                          dtype=np.float32)

    mg = lisser(guide, rayon)
    mp = lisser(grossier, rayon)
    varg = lisser(guide * guide, rayon) - mg * mg
    cov = lisser(guide * grossier, rayon) - mg * mp
    a = cov / (varg + np.float32(epsilon))
    b = mp - a * mg
    affine = np.clip(lisser(a, rayon) * guide + lisser(b, rayon), 0.0, 1.0).astype(np.float32)

    if taille != (l, h):
        affine = np.asarray(Image.fromarray(affine).resize((l, h), Image.Resampling.BICUBIC),
                            dtype=np.float32)
    return affine


def generer(fond: Path, seuil: float, adouci: float) -> None:
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
    cle = "%s-m%s-d%d-i%d" % (empreinte, MODEL_SHA256[:16], VERSION_DEPTH, INPUT_SIZE)
    DEPTH_DIR.mkdir(parents=True, exist_ok=True)
    MASQUE_DIR.mkdir(parents=True, exist_ok=True)
    chemin_profondeur = DEPTH_DIR / ("%s.npy" % cle)
    cle_masque = "%s-v%d-t%.4f-f%.4f" % (cle, VERSION_MASQUE, seuil, adouci)
    chemin_masque = MASQUE_DIR / ("%s.png" % cle_masque)

    # Un verrou entre processus : deux appels concurrents (fond changé pendant
    # une génération) ne doivent pas écrire le même fichier en même temps.
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
                options = ort.SessionOptions()
                options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
                session = ort.InferenceSession(str(MODEL_PATH), sess_options=options,
                                               providers=["CPUExecutionProvider"])
                nom = session.get_inputs()[0].name
                brut = np.asarray(session.run(None, {nom: tenseur})[0], dtype=np.float32).squeeze()
                if brut.shape != (mh, ml):
                    raise RuntimeError("sortie du modèle de forme inattendue : %s" % (brut.shape,))
                mini, maxi = float(brut.min()), float(brut.max())
                if not np.isfinite(mini) or not np.isfinite(maxi) or maxi <= mini:
                    raise RuntimeError("carte de profondeur invalide")
                profondeur = (brut - mini) / (maxi - mini)
                with tempfile.NamedTemporaryFile("wb", dir=DEPTH_DIR, delete=False) as f:
                    np.save(f, profondeur, allow_pickle=False)
                    temporaire = Path(f.name)
                os.replace(temporaire, chemin_profondeur)

            if not chemin_masque.is_file():
                pleine = affiner_guide(source, profondeur)
                demi = adouci * 0.5
                alpha = np.clip((pleine - (seuil - demi)) / max(1e-6, 2 * demi), 0.0, 1.0) \
                    if demi > 0 else (pleine >= seuil).astype(np.float32)
                alpha = alpha * alpha * (3.0 - 2.0 * alpha)   # smoothstep
                # Le calque doit redessiner **le décor**, pas un masque blanc :
                # on garde les pixels du fond et on n'emprunte que l'alpha. Un
                # masque en niveaux de gris, dessiné tel quel, afficherait une
                # silhouette blanche par-dessus le fond au lieu de le laisser voir.
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
            generer(a.wallpaper.expanduser().resolve(), a.threshold, a.feather)
        return 0
    except Exception as e:                       # une seule ligne, actionnable
        print(str(e), file=sys.stderr, flush=True)
        emit({"ok": False, "error": str(e)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
