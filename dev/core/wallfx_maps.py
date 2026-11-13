#!/usr/bin/env python3
"""
Générateur de cartes de transition pour WallpaperFx.qml (contagio & perfil).
Inspiré de diegoMalagrida/pocket-dots (WallpaperFx.qml / wallfx.frag).
"""

import hashlib
import json
import os
import random
import sys
import time

try:
    import numpy as np
    from PIL import Image, ImageFilter
    HAS_NUMPY_PIL = True
except ImportError:
    HAS_NUMPY_PIL = False

W, H = 480, 270
CACHE_DIR = os.path.expanduser("~/.cache/quickshell/wallfx")


def _value_noise(h, w, scale, rng):
    gh = max(2, h // scale + 2)
    gw = max(2, w // scale + 2)
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    up = img.resize((w, h), resample=Image.Resampling.BILINEAR)
    return np.asarray(up, dtype=np.float32) / 255.0


def generate_contagio(out_field, out_line, seed=None):
    if not HAS_NUMPY_PIL:
        return False

    rng = np.random.default_rng(seed if seed is not None else int(time.time() * 1000) & 0xFFFFFFFF)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    xx /= float(W)
    yy /= float(H)
    aspect = float(W) / float(H)

    n_colonies = int(rng.integers(5, 9))
    field = np.full((H, W), 1e9, dtype=np.float32)

    for i in range(n_colonies):
        cx = float(rng.uniform(0.08, 0.92))
        cy = float(rng.uniform(0.08, 0.92))
        delay = 0.0 if i == 0 else float(rng.uniform(0.02, 0.28))
        speed = float(rng.uniform(0.85, 1.20))
        d = np.sqrt(((xx - cx) * aspect) ** 2 + (yy - cy) ** 2) / speed + delay
        field = np.minimum(field, d)

    noise = (
        0.55 * _value_noise(H, W, 24, rng)
        + 0.30 * _value_noise(H, W, 10, rng)
        + 0.15 * _value_noise(H, W, 4, rng)
    )
    field = field + (noise - 0.5) * 0.22

    fmin, fmax = float(field.min()), float(field.max())
    norm = (field - fmin) / max(1e-6, fmax - fmin)
    norm = np.clip(norm, 0.0, 1.0)
    u16 = (norm * 65535.0).astype(np.uint16)
    hi = (u16 >> 8).astype(np.uint8)
    lo = (u16 & 0xFF).astype(np.uint8)
    zeros = np.zeros((H, W), dtype=np.uint8)

    field_rgb = np.stack([hi, lo, zeros], axis=-1)
    Image.fromarray(field_rgb, mode="RGB").save(out_field)

    # Flou gaussien sur la carte d'arrivée pour la lueur de front (lineTex G/B)
    blur_img = Image.fromarray((norm * 255.0).astype(np.uint8), mode="L").filter(
        ImageFilter.GaussianBlur(radius=4.5)
    )
    bnorm = np.asarray(blur_img, dtype=np.float32) / 255.0
    bu16 = (bnorm * 65535.0).astype(np.uint16)
    bhi = (bu16 >> 8).astype(np.uint8)
    blo = (bu16 & 0xFF).astype(np.uint8)
    line_rgb = np.stack([zeros, bhi, blo], axis=-1)
    Image.fromarray(line_rgb, mode="RGB").save(out_line)
    return True


def _find_depth_mask(wall_path):
    if not wall_path:
        return None
    depth_dir = os.path.expanduser("~/.cache/quickshell/depth")
    if not os.path.isdir(depth_dir):
        return None
    h = hashlib.sha256(os.path.abspath(wall_path).encode("utf-8")).hexdigest()[:16]
    for name in (f"{h}_mask.png", f"{h}.png"):
        p = os.path.join(depth_dir, name)
        if os.path.isfile(p):
            return p
    return None


def main(argv):
    wall_path = argv[1] if len(argv) > 1 else ""
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = hashlib.sha256(f"{wall_path}:{time.time()}".encode("utf-8")).hexdigest()[:12]
    out_field = os.path.join(CACHE_DIR, f"field_{key}.png")
    out_line = os.path.join(CACHE_DIR, f"line_{key}.png")

    # Nettoyage des anciens fichiers (> 12) pour garder un cache léger
    try:
        files = sorted(
            [os.path.join(CACHE_DIR, f) for f in os.listdir(CACHE_DIR) if f.endswith(".png")],
            key=os.path.getmtime,
        )
        for old in files[:-12]:
            os.remove(old)
    except Exception:
        pass

    ok = generate_contagio(out_field, out_line)
    if not ok:
        print(json.dumps({"ok": False, "kind": "none"}))
        return 1

    print(json.dumps({
        "ok": True,
        "kind": "contagio",
        "field": out_field,
        "line": out_line,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
