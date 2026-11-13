#!/usr/bin/env python3
"""
Générateur de cartes de transition pour WallpaperFx.qml (contagio & perfil).
Inspiré de diegoMalagrida/pocket-dots (WallpaperFx.qml / wallfx.frag).
"""

import hashlib
import json
import os
import sys
import tempfile
import time
from pathlib import Path

DEPTH_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "depth"
VENV_PYTHON = DEPTH_DIR / "runtime" / "bin" / "python"
MODEL_PATH = DEPTH_DIR / "models" / "depth-anything-v2-small.onnx"
PROFONDEUR_DIR = DEPTH_DIR / "cache" / "profondeur"
MODEL_SHA256_PREFIX = "afb6a5c28f3b6bf1"
INPUT_SIZE = 518
PATCH = 14
VERSION_DEPTH = 1


def _reexec_in_venv():
    """Bascule dans le venv depth si présent et nécessaire (onnxruntime + numpy + PIL)."""
    try:
        import numpy  # noqa: F401
        import onnxruntime  # noqa: F401
        from PIL import Image  # noqa: F401
        return
    except ImportError:
        pass
    if VENV_PYTHON.is_file() and Path(sys.executable).resolve() != VENV_PYTHON.resolve():
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), os.path.abspath(__file__), *sys.argv[1:]])


if __name__ == "__main__":
    _reexec_in_venv()

try:
    import numpy as np
    from PIL import Image, ImageFilter
    HAS_NUMPY_PIL = True
except ImportError:
    HAS_NUMPY_PIL = False

W, H = 480, 270
FIELD_MAX = 960
SD_RANGE = 16.0
WIDE = 48.0
CACHE_DIR = os.path.expanduser("~/.cache/quickshell/wallfx")
PERFIL_DIR = os.path.join(CACHE_DIR, "perfil")
SIN_PERFIL_FILE = os.path.expanduser("~/.config/wallfx/sin-perfil")


def _value_noise(h, w, scale, rng):
    gh = max(2, int(h / scale) + 2)
    gw = max(2, int(w / scale) + 2)
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    up = img.resize((w, h), resample=Image.Resampling.BILINEAR)
    return np.asarray(up, dtype=np.float32) / 255.0


def _blur(a, sigma):
    """Flou gaussien séparable en numpy."""
    r = int(3 * sigma) + 1
    x = np.arange(-r, r + 1, dtype=np.float32)
    k = np.exp(-x * x / (2.0 * sigma * sigma))
    k /= k.sum()
    pad = np.pad(a.astype(np.float32), r, mode="edge")
    tmp = np.zeros_like(pad[:, r:-r])
    for i in range(2 * r + 1):
        tmp += k[i] * pad[:, i:i + pad.shape[1] - 2 * r]
    out = np.zeros_like(a, dtype=np.float32)
    for i in range(2 * r + 1):
        out += k[i] * tmp[i:i + a.shape[0], :]
    return out


def _rgb16(v, extra=None):
    """Encode un champ 0..1 sur 16 bits dans G (fort) et B (faible), R libre."""
    q = np.clip(v * 65535.0 + 0.5, 0, 65535).astype(np.uint16)
    rgb = np.zeros(v.shape + (3,), dtype=np.uint8)
    if extra is not None:
        rgb[..., 0] = extra
    rgb[..., 1] = (q >> 8).astype(np.uint8)
    rgb[..., 2] = (q & 0xFF).astype(np.uint8)
    return rgb


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


def _sin_perfil_names():
    if not os.path.isfile(SIN_PERFIL_FILE):
        return set()
    try:
        with open(SIN_PERFIL_FILE, "r", encoding="utf-8") as f:
            return {l.strip() for l in f if l.strip() and not l.startswith("#")}
    except OSError:
        return set()


def _perfil_key(wall_path):
    st = os.stat(wall_path)
    raw = f"{os.path.realpath(wall_path)}|{st.st_size}|{int(st.st_mtime)}|{FIELD_MAX}"
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _inference_size(w, h):
    if w <= h:
        scale = INPUT_SIZE / float(w)
        iw = INPUT_SIZE
        ih = max(PATCH, int(round((h * scale) / PATCH)) * PATCH)
    else:
        scale = INPUT_SIZE / float(h)
        ih = INPUT_SIZE
        iw = max(PATCH, int(round((w * scale) / PATCH)) * PATCH)
    return iw, ih


def _load_or_compute_depth(wall_path):
    """Charge la carte de profondeur (0..1, 1=premier plan) ou la calcule via ONNX."""
    if not HAS_NUMPY_PIL or not wall_path or not os.path.isfile(wall_path):
        return None, None
    try:
        file_sha = _sha256_file(wall_path)
        cle = f"{file_sha}-m{MODEL_SHA256_PREFIX}-d{VERSION_DEPTH}-i{INPUT_SIZE}"
        npy_path = PROFONDEUR_DIR / f"{cle}.npy"
        with Image.open(wall_path) as img:
            src = img.convert("RGB")
            orig_w, orig_h = src.size
            ml, mh = _inference_size(orig_w, orig_h)
            if npy_path.is_file():
                depth = np.load(npy_path, allow_pickle=False)
                if depth.shape == (mh, ml):
                    return depth.astype(np.float32), (orig_w, orig_h)

            if not MODEL_PATH.is_file():
                return None, None
            try:
                import onnxruntime as ort
            except ImportError:
                return None, None

            reduit = src.resize((ml, mh), Image.Resampling.BICUBIC)
            px = np.asarray(reduit, dtype=np.float32) / 255.0
            px = (px - np.array([0.485, 0.456, 0.406], dtype=np.float32)) / np.array([0.229, 0.224, 0.225], dtype=np.float32)
            tenseur = np.transpose(px, (2, 0, 1))[None, ...]
            opts = ort.SessionOptions()
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            sess = ort.InferenceSession(str(MODEL_PATH), sess_options=opts, providers=["CPUExecutionProvider"])
            nom = sess.get_inputs()[0].name
            brut = np.asarray(sess.run(None, {nom: tenseur})[0], dtype=np.float32).squeeze()
            if brut.shape != (mh, ml):
                return None, None
            mini, maxi = float(brut.min()), float(brut.max())
            if not np.isfinite(mini) or not np.isfinite(maxi) or maxi <= mini:
                return None, None
            depth = ((brut - mini) / (maxi - mini)).astype(np.float32)
            try:
                PROFONDEUR_DIR.mkdir(parents=True, exist_ok=True)
                with tempfile.NamedTemporaryFile("wb", dir=PROFONDEUR_DIR, delete=False) as tf:
                    np.save(tf, depth, allow_pickle=False)
                    tmp_name = tf.name
                os.replace(tmp_name, npy_path)
            except OSError:
                pass
            return depth, (orig_w, orig_h)
    except Exception:
        return None, None


def _otsu_threshold(arr):
    hist, edges = np.histogram(arr.ravel(), bins=256, range=(0.0, 1.0))
    total = arr.size
    if total == 0:
        return 0.5
    centers = (edges[:-1] + edges[1:]) * 0.5
    weight1 = np.cumsum(hist)
    weight2 = total - weight1
    mean1 = np.cumsum(hist * centers) / np.maximum(weight1, 1)
    mean2 = (np.sum(hist * centers) - np.cumsum(hist * centers)) / np.maximum(weight2, 1)
    var_between = weight1[:-1] * weight2[:-1] * (mean1[:-1] - mean2[:-1]) ** 2
    idx = int(np.argmax(var_between))
    return float(centers[idx])


def _majority_smooth(mask):
    """Lissage morphologique 3x3 pour supprimer le bruit isolé."""
    p = np.pad(mask.astype(np.uint8), 1, mode="edge")
    h, w = mask.shape
    s = (
        p[0:h, 0:w] + p[0:h, 1:w+1] + p[0:h, 2:w+2]
        + p[1:h+1, 0:w] + p[1:h+1, 1:w+1] + p[1:h+1, 2:w+2]
        + p[2:h+2, 0:w] + p[2:h+2, 1:w+1] + p[2:h+2, 2:w+2]
    )
    return s >= 5


def _extract_subject_mask(depth, w, h):
    """Extrait un masque binaire de sujet premier plan ou renvoie None si paysage/abstrait."""
    up = np.asarray(
        Image.fromarray(np.clip(depth, 0.0, 1.0), mode="F").resize((w, h), Image.Resampling.BICUBIC),
        dtype=np.float32,
    )
    up = np.clip(up, 0.0, 1.0)
    t = _otsu_threshold(up)
    b = _majority_smooth(up >= max(0.35, min(0.75, t)))
    area = float(b.mean())
    if area < 0.03 or area > 0.72:
        return None
    fg_med = float(np.median(up[b]))
    bg_med = float(np.median(up[~b]))
    if (fg_med - bg_med) < 0.24:
        return None

    # Vérifier qu'il ne s'agit pas uniquement d'un gradient lisse haut->bas (horizon)
    gx = np.abs(np.diff(up, axis=1, prepend=up[:, :1]))
    gy = np.abs(np.diff(up, axis=0, prepend=up[:1, :]))
    grad = np.hypot(gx, gy)
    eroded = b & np.roll(b, 1, 0) & np.roll(b, -1, 0) & np.roll(b, 1, 1) & np.roll(b, -1, 1)
    edge = b & (~eroded)
    if not edge.any():
        return None
    edge_grad = float(np.median(grad[edge]))
    if edge_grad < 0.008 and float(edge.mean()) > 0.06:
        return None
    return b


def _jfa_edt(seeds_mask):
    """Jump Flooding Algorithm (JFA+1) en numpy pur : distance euclidienne et graine la plus proche."""
    h, w = seeds_mask.shape
    sy = np.full((h, w), -1, dtype=np.int32)
    sx = np.full((h, w), -1, dtype=np.int32)
    d2 = np.full((h, w), 1e12, dtype=np.float32)

    yy, xx = np.mgrid[0:h, 0:w].astype(np.int32)
    sy[seeds_mask] = yy[seeds_mask]
    sx[seeds_mask] = xx[seeds_mask]
    d2[seeds_mask] = 0.0

    max_dim = max(h, w)
    step = 1
    while step * 2 < max_dim:
        step *= 2
    steps = []
    while step >= 1:
        steps.append(step)
        step //= 2
    steps.append(1)

    dirs = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))
    for st in steps:
        for dy, dx in dirs:
            oy = dy * st
            ox = dx * st
            y0_dst = max(0, oy)
            y1_dst = min(h, h + oy)
            x0_dst = max(0, ox)
            x1_dst = min(w, w + ox)
            if y0_dst >= y1_dst or x0_dst >= x1_dst:
                continue
            y0_src = y0_dst - oy
            y1_src = y1_dst - oy
            x0_src = x0_dst - ox
            x1_src = x1_dst - ox

            cand_sy = sy[y0_src:y1_src, x0_src:x1_src]
            cand_sx = sx[y0_src:y1_src, x0_src:x1_src]
            valid = cand_sy >= 0
            if not valid.any():
                continue

            cur_y = yy[y0_dst:y1_dst, x0_dst:x1_dst]
            cur_x = xx[y0_dst:y1_dst, x0_dst:x1_dst]
            cd2 = (cur_y - cand_sy).astype(np.float32) ** 2 + (cur_x - cand_sx).astype(np.float32) ** 2
            cur_d2 = d2[y0_dst:y1_dst, x0_dst:x1_dst]
            better = valid & (cd2 < cur_d2)
            if better.any():
                cur_d2[better] = cd2[better]
                sy[y0_dst:y1_dst, x0_dst:x1_dst][better] = cand_sy[better]
                sx[y0_dst:y1_dst, x0_dst:x1_dst][better] = cand_sx[better]

    return np.sqrt(d2), sy, sx


def _trace_contours(edge):
    """Trace les contours 8-connexes et calcule le paramètre [0..1] depuis le point le plus haut."""
    h, w = edge.shape
    ys, xs = np.nonzero(edge)
    if len(ys) == 0:
        return np.zeros((h, w), dtype=np.float32)

    pts = set(zip(ys.tolist(), xs.tolist()))
    nbrs = ((-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1))
    param_at = np.zeros((h, w), dtype=np.float32)

    while pts:
        start = min(pts)
        pts.remove(start)
        chain = [start]
        cur = start
        while True:
            cy, cx = cur
            nxt = None
            for dy, dx in nbrs:
                cand = (cy + dy, cx + dx)
                if cand in pts:
                    nxt = cand
                    break
            if nxt is None:
                break
            pts.remove(nxt)
            chain.append(nxt)
            cur = nxt

        if len(chain) < 40:
            continue

        c = np.array(chain, dtype=np.float32)  # (N, 2) -> (y, x)
        nxt_c = np.roll(c, -1, axis=0)
        seg = np.sqrt(((nxt_c - c) ** 2).sum(axis=1))
        s = np.concatenate([[0.0], np.cumsum(seg)[:-1]])
        L = float(s[-1] + seg[-1])
        if L <= 1e-6:
            continue
        top_idx = int(np.argmin(c[:, 0]))
        s = (s - s[top_idx]) % L
        p = np.minimum(s, L - s) / (L * 0.5)
        border = (c[:, 1] <= 1) | (c[:, 1] >= w - 2) | (c[:, 0] <= 1) | (c[:, 0] >= h - 2)
        p[border] = -1.0
        iy = c[:, 0].astype(np.int32)
        ix = c[:, 1].astype(np.int32)
        param_at[iy, ix] = p

    return param_at


def generate_perfil(wall_path, out_field, out_line):
    if not HAS_NUMPY_PIL or not wall_path or not os.path.isfile(wall_path):
        return False
    if os.path.basename(wall_path) in _sin_perfil_names():
        return False

    key = _perfil_key(wall_path)
    os.makedirs(PERFIL_DIR, exist_ok=True)
    cached_field = os.path.join(PERFIL_DIR, f"{key}-campo.png")
    cached_line = os.path.join(PERFIL_DIR, f"{key}-linea.png")
    if os.path.isfile(cached_field) and os.path.isfile(cached_line):
        return cached_field, cached_line

    depth, orig_size = _load_or_compute_depth(wall_path)
    if depth is None:
        return False

    orig_w, orig_h = orig_size
    scale = min(1.0, FIELD_MAX / float(max(orig_w, orig_h)))
    w = max(64, int(round(orig_w * scale)))
    h = max(64, int(round(orig_h * scale)))

    b = _extract_subject_mask(depth, w, h)
    if b is None:
        return False

    # Contour interne du masque (pixels de b adjacents au fond)
    p = np.pad(b, 1, mode="constant", constant_values=False)
    interior = p[0:h, 1:w+1] & p[2:h+2, 1:w+1] & p[1:h+1, 0:w] & p[1:h+1, 2:w+2]
    edge = b & (~interior)
    if not edge.any():
        return False

    dist, sy, sx = _jfa_edt(edge)
    din = np.where(b, dist, 0.0).astype(np.float32)
    dout = np.where(~b, dist, 0.0).astype(np.float32)
    sd = dout - din  # > 0 à l'extérieur du personnage

    din_fg = din[b]
    denom = max(float(np.percentile(din_fg, 99)), 1.0) if din_fg.size > 0 else 1.0
    inner = np.clip(din / denom, 0.0, 1.0)

    rng = np.random.default_rng(int(key[:8], 16))
    noise = 0.6 * _value_noise(h, w, max(2.0, w / 9.0), rng) + 0.4 * _value_noise(h, w, max(2.0, w / 28.0), rng)
    warped = dout * (0.75 + 0.5 * noise) + noise * 0.08 * max(w, h)
    outside = ~b
    order = np.zeros((h, w), dtype=np.float32)
    vals = warped[outside]
    if vals.size > 1:
        r = np.empty(vals.size, dtype=np.float32)
        r[np.argsort(vals, kind="stable")] = np.arange(vals.size, dtype=np.float32)
        order[outside] = r / float(vals.size - 1)

    param_at = _trace_contours(edge)
    line = np.zeros((h, w), dtype=np.uint8)
    near = (np.abs(sd) < SD_RANGE) & (sy >= 0)
    if near.any():
        v = param_at[sy[near], sx[near]]
        line[near] = np.where(v <= 0.0, 0, np.clip(v * 255.0, 1, 255)).astype(np.uint8)

    rgb = np.zeros((h, w, 3), dtype=np.uint8)
    rgb[..., 0] = np.clip(dout / WIDE * 255.0, 0, 255).astype(np.uint8)
    rgb[..., 1] = np.clip(inner * 255.0, 0, 255).astype(np.uint8)
    rgb[..., 2] = np.clip((sd + SD_RANGE) / (2.0 * SD_RANGE) * 255.0, 0, 255).astype(np.uint8)

    smooth = _blur(order, 4.0)
    linea = _rgb16(smooth, extra=line)

    for dest, arr in ((cached_field, rgb), (cached_line, linea)):
        tmp = f"{dest}.{os.getpid()}.tmp.png"
        Image.fromarray(arr, "RGB").save(tmp)
        os.replace(tmp, dest)

    return cached_field, cached_line


def _cleanup_old_cache(max_files=16):
    try:
        files = [
            os.path.join(CACHE_DIR, fn)
            for fn in os.listdir(CACHE_DIR)
            if (fn.startswith("field_") or fn.startswith("line_")) and fn.endswith(".png")
        ]
        if len(files) <= max_files:
            return
        files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        for old in files[max_files:]:
            try:
                os.remove(old)
            except OSError:
                pass
    except OSError:
        pass


def main(argv):
    wall_path = argv[1] if len(argv) > 1 else ""
    os.makedirs(CACHE_DIR, exist_ok=True)
    _cleanup_old_cache()

    if wall_path and os.path.isfile(wall_path):
        perfil_res = generate_perfil(wall_path, None, None)
        if perfil_res:
            out_field, out_line = perfil_res
            print(json.dumps({
                "ok": True,
                "kind": "perfil",
                "field": out_field,
                "line": out_line,
            }))
            return 0

    key = hashlib.sha256(f"{wall_path}:{time.time()}".encode("utf-8")).hexdigest()[:12]
    out_field = os.path.join(CACHE_DIR, f"field_{key}.png")
    out_line = os.path.join(CACHE_DIR, f"line_{key}.png")

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
    raise SystemExit(main(sys.argv))
