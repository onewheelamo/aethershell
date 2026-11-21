use crate::common::paths::home_dir;
use crate::wallfx::img_ops::{
    depth_data_dir, gaussian_blur_f32, make_rgb, model_path, percentile_f32, resize_f32_gray,
    run_depth_anything, save_rgb, sha256_file,
};
use image::imageops::FilterType;
use image::{GrayImage, ImageBuffer, Luma, RgbImage};
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const W: usize = 480;
const H: usize = 270;
const FIELD_MAX: usize = 960;
const SD_RANGE: f32 = 16.0;
const WIDE: f32 = 48.0;
const INPUT_SIZE: u32 = 518;
const PATCH: u32 = 14;
const MODEL_SHA256_PREFIX: &str = "afb6a5c28f3b6bf1";
const VERSION_DEPTH: u32 = 1;

struct Rng(u64);
impl Rng {
    fn new(seed: u64) -> Self {
        Self(if seed == 0 { 0x9e3779b97f4a7c15 } else { seed })
    }
    fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn f32(&mut self) -> f32 {
        (self.next_u64() >> 40) as f32 / ((1u64 << 24) as f32)
    }
    fn range_f32(&mut self, lo: f32, hi: f32) -> f32 {
        lo + (hi - lo) * self.f32()
    }
    fn range_usize(&mut self, lo: usize, hi_excl: usize) -> usize {
        lo + (self.next_u64() as usize % (hi_excl - lo).max(1))
    }
}

fn cache_dir() -> PathBuf {
    home_dir().join(".cache/quickshell/wallfx")
}

fn perfil_dir() -> PathBuf {
    cache_dir().join("perfil")
}

fn sin_perfil_file() -> PathBuf {
    home_dir().join(".config/wallfx/sin-perfil")
}

fn profondeur_dir() -> PathBuf {
    depth_data_dir().join("cache/profondeur")
}

fn value_noise(h: usize, w: usize, scale: f32, rng: &mut Rng) -> Vec<f32> {
    let gh = ((h as f32 / scale) as usize + 2).max(2);
    let gw = ((w as f32 / scale) as usize + 2).max(2);
    let mut grid = vec![0u8; gh * gw];
    for v in &mut grid {
        *v = (rng.f32() * 255.0).clamp(0.0, 255.0) as u8;
    }
    let img = ImageBuffer::<Luma<u8>, Vec<u8>>::from_raw(gw as u32, gh as u32, grid)
        .unwrap_or_else(|| GrayImage::new(gw as u32, gh as u32));
    let up = image::imageops::resize(&img, w as u32, h as u32, FilterType::Triangle);
    up.as_raw().iter().map(|&b| b as f32 / 255.0).collect()
}

fn rgb16(v: &[f32], w: usize, h: usize, extra: Option<&[u8]>) -> RgbImage {
    let mut rgb = vec![0u8; w * h * 3];
    for i in 0..(w * h) {
        let q = (v[i].clamp(0.0, 1.0) * 65535.0 + 0.5).clamp(0.0, 65535.0) as u16;
        if let Some(ex) = extra {
            rgb[i * 3] = ex[i];
        }
        rgb[i * 3 + 1] = (q >> 8) as u8;
        rgb[i * 3 + 2] = (q & 0xFF) as u8;
    }
    make_rgb(w as u32, h as u32, rgb)
}

fn generate_contagio(out_field: &Path, out_line: &Path) -> bool {
    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(42);
    let mut rng = Rng::new(seed);
    let aspect = W as f32 / H as f32;
    let n_colonies = rng.range_usize(5, 9);
    let mut field = vec![1e9f32; W * H];

    for i in 0..n_colonies {
        let cx = rng.range_f32(0.08, 0.92);
        let cy = rng.range_f32(0.08, 0.92);
        let delay = if i == 0 { 0.0 } else { rng.range_f32(0.02, 0.28) };
        let speed = rng.range_f32(0.85, 1.20);
        for y in 0..H {
            let fy = y as f32 / H as f32;
            for x in 0..W {
                let fx = x as f32 / W as f32;
                let dx = (fx - cx) * aspect;
                let dy = fy - cy;
                let d = (dx * dx + dy * dy).sqrt() / speed + delay;
                let idx = y * W + x;
                if d < field[idx] {
                    field[idx] = d;
                }
            }
        }
    }

    let n1 = value_noise(H, W, 24.0, &mut rng);
    let n2 = value_noise(H, W, 10.0, &mut rng);
    let n3 = value_noise(H, W, 4.0, &mut rng);
    let mut fmin = f32::INFINITY;
    let mut fmax = f32::NEG_INFINITY;
    for i in 0..(W * H) {
        let noise = 0.55 * n1[i] + 0.30 * n2[i] + 0.15 * n3[i];
        field[i] += (noise - 0.5) * 0.22;
        if field[i] < fmin { fmin = field[i]; }
        if field[i] > fmax { fmax = field[i]; }
    }
    let span = (fmax - fmin).max(1e-6);
    let mut norm = vec![0.0f32; W * H];
    let mut field_rgb = vec![0u8; W * H * 3];
    for i in 0..(W * H) {
        let v = ((field[i] - fmin) / span).clamp(0.0, 1.0);
        norm[i] = v;
        let q = (v * 65535.0) as u16;
        field_rgb[i * 3] = (q >> 8) as u8;
        field_rgb[i * 3 + 1] = (q & 0xFF) as u8;
    }
    if save_rgb(&make_rgb(W as u32, H as u32, field_rgb), out_field).is_err() {
        return false;
    }

    let bnorm = gaussian_blur_f32(&norm, W, H, 4.5);
    let mut line_rgb = vec![0u8; W * H * 3];
    for i in 0..(W * H) {
        let q = (bnorm[i].clamp(0.0, 1.0) * 65535.0) as u16;
        line_rgb[i * 3 + 1] = (q >> 8) as u8;
        line_rgb[i * 3 + 2] = (q & 0xFF) as u8;
    }
    save_rgb(&make_rgb(W as u32, H as u32, line_rgb), out_line).is_ok()
}

fn sin_perfil_names() -> HashSet<String> {
    let p = sin_perfil_file();
    let Ok(txt) = fs::read_to_string(&p) else {
        return HashSet::new();
    };
    txt.lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|s| s.to_string())
        .collect()
}

fn sha256_hex(s: &str) -> String {
    let mut h = Sha256::new();
    h.update(s.as_bytes());
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

fn inference_size(w: u32, h: u32) -> (u32, u32) {
    if w <= h {
        let scale = INPUT_SIZE as f64 / w as f64;
        let ih = ((h as f64 * scale / PATCH as f64).round() as u32 * PATCH).max(PATCH);
        (INPUT_SIZE, ih)
    } else {
        let scale = INPUT_SIZE as f64 / h as f64;
        let iw = ((w as f64 * scale / PATCH as f64).round() as u32 * PATCH).max(PATCH);
        (iw, INPUT_SIZE)
    }
}

fn load_or_compute_depth(wall_path: &Path) -> Option<(Vec<f32>, u32, u32, u32, u32)> {
    let file_sha = sha256_file(wall_path).ok()?;
    let cle = format!("{file_sha}-m{MODEL_SHA256_PREFIX}-d{VERSION_DEPTH}-i{INPUT_SIZE}");
    let bin_path = profondeur_dir().join(format!("{cle}.bin"));
    let img = image::open(wall_path).ok()?.to_rgb8();
    let (orig_w, orig_h) = (img.width(), img.height());
    let (ml, mh) = inference_size(orig_w, orig_h);

    if let Ok(bytes) = fs::read(&bin_path) {
        if bytes.len() == 8 + (ml as usize * mh as usize * 4) {
            let cw = u32::from_le_bytes(bytes[0..4].try_into().ok()?);
            let ch = u32::from_le_bytes(bytes[4..8].try_into().ok()?);
            if cw == ml && ch == mh {
                let mut out = Vec::with_capacity(ml as usize * mh as usize);
                for chunk in bytes[8..].chunks_exact(4) {
                    out.push(f32::from_le_bytes(chunk.try_into().ok()?));
                }
                return Some((out, ml, mh, orig_w, orig_h));
            }
        }
    }

    if !model_path().is_file() {
        return None;
    }
    let brut = run_depth_anything(&img, ml, mh).ok()?;
    let mut mini = f32::INFINITY;
    let mut maxi = f32::NEG_INFINITY;
    for &v in &brut {
        if !v.is_finite() {
            return None;
        }
        if v < mini { mini = v; }
        if v > maxi { maxi = v; }
    }
    if maxi <= mini {
        return None;
    }
    let depth: Vec<f32> = brut.iter().map(|&v| (v - mini) / (maxi - mini)).collect();

    let pdir = profondeur_dir();
    if fs::create_dir_all(&pdir).is_ok() {
        let mut raw = Vec::with_capacity(8 + depth.len() * 4);
        raw.extend_from_slice(&ml.to_le_bytes());
        raw.extend_from_slice(&mh.to_le_bytes());
        for &v in &depth {
            raw.extend_from_slice(&v.to_le_bytes());
        }
        let tmp = bin_path.with_extension("tmp");
        if fs::write(&tmp, &raw).is_ok() {
            let _ = fs::rename(&tmp, &bin_path);
        }
    }
    Some((depth, ml, mh, orig_w, orig_h))
}

fn otsu_threshold(arr: &[f32]) -> f32 {
    if arr.is_empty() {
        return 0.5;
    }
    let mut hist = [0usize; 256];
    for &v in arr {
        let bin = ((v.clamp(0.0, 0.9999)) * 256.0) as usize;
        hist[bin] += 1;
    }
    let total = arr.len() as f64;
    let mut sum_all = 0.0f64;
    for (i, &c) in hist.iter().enumerate() {
        let center = (i as f64 + 0.5) / 256.0;
        sum_all += c as f64 * center;
    }
    let mut w1 = 0.0f64;
    let mut sum1 = 0.0f64;
    let mut best_var = -1.0f64;
    let mut best_t = 0.5f32;
    for (i, &c) in hist.iter().enumerate().take(255) {
        w1 += c as f64;
        if w1 == 0.0 {
            continue;
        }
        let w2 = total - w1;
        if w2 == 0.0 {
            break;
        }
        let center = (i as f64 + 0.5) / 256.0;
        sum1 += c as f64 * center;
        let m1 = sum1 / w1;
        let m2 = (sum_all - sum1) / w2;
        let var = w1 * w2 * (m1 - m2) * (m1 - m2);
        if var > best_var {
            best_var = var;
            best_t = center as f32;
        }
    }
    best_t
}

fn extract_subject_mask(depth: &[f32], ml: u32, mh: u32, w: usize, h: usize) -> Option<Vec<bool>> {
    let up = resize_f32_gray(depth, ml, mh, w as u32, h as u32);
    let t = otsu_threshold(&up).clamp(0.35, 0.75);
    let raw_b: Vec<bool> = up.iter().map(|&v| v >= t).collect();

    let mut b = vec![false; w * h];
    let mut fg_count = 0usize;
    for y in 0..h {
        for x in 0..w {
            let mut cnt = 0usize;
            for dy in -1isize..=1 {
                for dx in -1isize..=1 {
                    let sy = (y as isize + dy).clamp(0, (h - 1) as isize) as usize;
                    let sx = (x as isize + dx).clamp(0, (w - 1) as isize) as usize;
                    if raw_b[sy * w + sx] {
                        cnt += 1;
                    }
                }
            }
            if cnt >= 5 {
                b[y * w + x] = true;
                fg_count += 1;
            }
        }
    }
    let area = fg_count as f32 / (w * h) as f32;
    if !(0.03..=0.72).contains(&area) {
        return None;
    }
    let fg_vals: Vec<f32> = up.iter().zip(&b).filter(|(_, &m)| m).map(|(&v, _)| v).collect();
    let bg_vals: Vec<f32> = up.iter().zip(&b).filter(|(_, &m)| !m).map(|(&v, _)| v).collect();
    if (percentile_f32(&fg_vals, 50.0) - percentile_f32(&bg_vals, 50.0)) < 0.24 {
        return None;
    }

    let mut edge_grads = Vec::new();
    let mut edge_count = 0usize;
    for y in 0..h {
        for x in 0..w {
            let idx = y * w + x;
            if !b[idx] {
                continue;
            }
            let up_b = b[((y + h - 1) % h) * w + x];
            let dn_b = b[((y + 1) % h) * w + x];
            let lf_b = b[y * w + (x + w - 1) % w];
            let rt_b = b[y * w + (x + 1) % w];
            if !(up_b && dn_b && lf_b && rt_b) {
                edge_count += 1;
                let gx = (up[idx] - up[y * w + x.saturating_sub(1)]).abs();
                let gy = (up[idx] - up[y.saturating_sub(1) * w + x]).abs();
                edge_grads.push((gx * gx + gy * gy).sqrt());
            }
        }
    }
    if edge_count == 0 {
        return None;
    }
    let edge_med = percentile_f32(&edge_grads, 50.0);
    if edge_med < 0.008 && (edge_count as f32 / (w * h) as f32) > 0.06 {
        return None;
    }
    Some(b)
}

fn jfa_edt(seeds: &[bool], w: usize, h: usize) -> (Vec<f32>, Vec<i32>, Vec<i32>) {
    let n = w * h;
    let mut sy = vec![-1i32; n];
    let mut sx = vec![-1i32; n];
    let mut d2 = vec![1e12f32; n];
    for y in 0..h {
        for x in 0..w {
            let idx = y * w + x;
            if seeds[idx] {
                sy[idx] = y as i32;
                sx[idx] = x as i32;
                d2[idx] = 0.0;
            }
        }
    }
    let max_dim = w.max(h) as isize;
    let mut step = 1isize;
    while step * 2 < max_dim {
        step *= 2;
    }
    let mut steps = Vec::new();
    while step >= 1 {
        steps.push(step);
        step /= 2;
    }
    steps.push(1);

    let dirs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)];
    for st in steps {
        let mut next_sy = sy.clone();
        let mut next_sx = sx.clone();
        let mut next_d2 = d2.clone();
        for &(dy, dx) in &dirs {
            let oy = dy * st;
            let ox = dx * st;
            for y in 0..h {
                let src_y = y as isize - oy;
                if src_y < 0 || src_y >= h as isize {
                    continue;
                }
                for x in 0..w {
                    let src_x = x as isize - ox;
                    if src_x < 0 || src_x >= w as isize {
                        continue;
                    }
                    let sidx = src_y as usize * w + src_x as usize;
                    let csy = sy[sidx];
                    if csy < 0 {
                        continue;
                    }
                    let csx = sx[sidx];
                    let cd2 = (y as i32 - csy) as f32 * (y as i32 - csy) as f32
                        + (x as i32 - csx) as f32 * (x as i32 - csx) as f32;
                    let didx = y * w + x;
                    if cd2 < next_d2[didx] {
                        next_d2[didx] = cd2;
                        next_sy[didx] = csy;
                        next_sx[didx] = csx;
                    }
                }
            }
        }
        sy = next_sy;
        sx = next_sx;
        d2 = next_d2;
    }
    let dist = d2.into_iter().map(|v| v.sqrt()).collect();
    (dist, sy, sx)
}

fn trace_contours(edge: &[bool], w: usize, h: usize) -> Vec<f32> {
    let mut pts: HashSet<(usize, usize)> = HashSet::new();
    for y in 0..h {
        for x in 0..w {
            if edge[y * w + x] {
                pts.insert((y, x));
            }
        }
    }
    let mut param_at = vec![0.0f32; w * h];
    let nbrs: [(isize, isize); 8] = [
        (-1, 0), (-1, 1), (0, 1), (1, 1),
        (1, 0), (1, -1), (0, -1), (-1, -1),
    ];
    while !pts.is_empty() {
        let start = *pts.iter().min().unwrap();
        pts.remove(&start);
        let mut chain = vec![start];
        let mut cur = start;
        loop {
            let mut nxt = None;
            for &(dy, dx) in &nbrs {
                let ny = cur.0 as isize + dy;
                let nx = cur.1 as isize + dx;
                if ny >= 0 && nx >= 0 && (ny as usize) < h && (nx as usize) < w {
                    let cand = (ny as usize, nx as usize);
                    if pts.contains(&cand) {
                        nxt = Some(cand);
                        break;
                    }
                }
            }
            let Some(npt) = nxt else { break };
            pts.remove(&npt);
            chain.push(npt);
            cur = npt;
        }
        if chain.len() < 40 {
            continue;
        }
        let m = chain.len();
        let mut s = vec![0.0f32; m];
        let mut total_l = 0.0f32;
        for i in 0..m {
            let a = chain[i];
            let b = chain[(i + 1) % m];
            let dy = b.0 as f32 - a.0 as f32;
            let dx = b.1 as f32 - a.1 as f32;
            let seg = (dy * dy + dx * dx).sqrt();
            if i + 1 < m {
                s[i + 1] = s[i] + seg;
            }
            total_l += seg;
        }
        if total_l <= 1e-6 {
            continue;
        }
        let top_idx = chain
            .iter()
            .enumerate()
            .min_by_key(|(_, &(y, _))| y)
            .map(|(i, _)| i)
            .unwrap_or(0);
        let s0 = s[top_idx];
        for (i, &(y, x)) in chain.iter().enumerate() {
            let si = (s[i] - s0).rem_euclid(total_l);
            let mut p = si.min(total_l - si) / (total_l * 0.5);
            if x <= 1 || x >= w - 2 || y <= 1 || y >= h - 2 {
                p = -1.0;
            }
            param_at[y * w + x] = p;
        }
    }
    param_at
}

fn generate_perfil(wall_path: &Path) -> Option<(String, String)> {
    let fname = wall_path.file_name().and_then(|s| s.to_str())?;
    if sin_perfil_names().contains(fname) {
        return None;
    }
    let meta = fs::metadata(wall_path).ok()?;
    let real = fs::canonicalize(wall_path).unwrap_or_else(|_| wall_path.to_path_buf());
    let raw_key = format!("{}|{}|{}|{}", real.to_string_lossy(), meta.len(), meta.mtime(), FIELD_MAX);
    let key = &sha256_hex(&raw_key)[..16];

    let pdir = perfil_dir();
    let _ = fs::create_dir_all(&pdir);
    let cached_field = pdir.join(format!("{key}-campo.png"));
    let cached_line = pdir.join(format!("{key}-linea.png"));
    if cached_field.is_file() && cached_line.is_file() {
        return Some((
            cached_field.to_string_lossy().to_string(),
            cached_line.to_string_lossy().to_string(),
        ));
    }

    let (depth, ml, mh, orig_w, orig_h) = load_or_compute_depth(wall_path)?;
    let scale = (FIELD_MAX as f64 / orig_w.max(orig_h) as f64).min(1.0);
    let w = (orig_w as f64 * scale).round().max(64.0) as usize;
    let h = (orig_h as f64 * scale).round().max(64.0) as usize;

    let b = extract_subject_mask(&depth, ml, mh, w, h)?;
    let mut edge = vec![false; w * h];
    let mut has_edge = false;
    for y in 0..h {
        for x in 0..w {
            let idx = y * w + x;
            if !b[idx] {
                continue;
            }
            let interior = y > 0
                && y + 1 < h
                && x > 0
                && x + 1 < w
                && b[(y - 1) * w + x]
                && b[(y + 1) * w + x]
                && b[y * w + (x - 1)]
                && b[y * w + (x + 1)];
            if !interior {
                edge[idx] = true;
                has_edge = true;
            }
        }
    }
    if !has_edge {
        return None;
    }

    let (dist, sy, sx) = jfa_edt(&edge, w, h);
    let mut din_fg = Vec::new();
    for i in 0..(w * h) {
        if b[i] {
            din_fg.push(dist[i]);
        }
    }
    let denom = percentile_f32(&din_fg, 99.0).max(1.0);

    let seed = u64::from_str_radix(&key[..8], 16).unwrap_or(1);
    let mut rng = Rng::new(seed);
    let n1 = value_noise(h, w, (w as f32 / 9.0).max(2.0), &mut rng);
    let n2 = value_noise(h, w, (w as f32 / 28.0).max(2.0), &mut rng);

    let mut outside_vals: Vec<(usize, f32)> = Vec::new();
    for i in 0..(w * h) {
        if !b[i] {
            let noise = 0.6 * n1[i] + 0.4 * n2[i];
            let warped = dist[i] * (0.75 + 0.5 * noise) + noise * 0.08 * w.max(h) as f32;
            outside_vals.push((i, warped));
        }
    }
    outside_vals.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    let mut order = vec![0.0f32; w * h];
    if outside_vals.len() > 1 {
        let denom_o = (outside_vals.len() - 1) as f32;
        for (rank, (idx, _)) in outside_vals.into_iter().enumerate() {
            order[idx] = rank as f32 / denom_o;
        }
    }

    let param_at = trace_contours(&edge, w, h);
    let mut line = vec![0u8; w * h];
    let mut field_rgb = vec![0u8; w * h * 3];
    for i in 0..(w * h) {
        let din = if b[i] { dist[i] } else { 0.0 };
        let dout = if !b[i] { dist[i] } else { 0.0 };
        let sd = dout - din;
        let inner = (din / denom).clamp(0.0, 1.0);
        if sd.abs() < SD_RANGE && sy[i] >= 0 {
            let pidx = sy[i] as usize * w + sx[i] as usize;
            let v = param_at[pidx];
            if v > 0.0 {
                line[i] = (v * 255.0).clamp(1.0, 255.0) as u8;
            }
        }
        field_rgb[i * 3] = (dout / WIDE * 255.0).clamp(0.0, 255.0) as u8;
        field_rgb[i * 3 + 1] = (inner * 255.0).clamp(0.0, 255.0) as u8;
        field_rgb[i * 3 + 2] = ((sd + SD_RANGE) / (2.0 * SD_RANGE) * 255.0).clamp(0.0, 255.0) as u8;
    }

    let smooth = gaussian_blur_f32(&order, w, h, 4.0);
    let linea = rgb16(&smooth, w, h, Some(&line));
    let field_img = make_rgb(w as u32, h as u32, field_rgb);

    if save_rgb(&field_img, &cached_field).is_err() || save_rgb(&linea, &cached_line).is_err() {
        return None;
    }
    Some((
        cached_field.to_string_lossy().to_string(),
        cached_line.to_string_lossy().to_string(),
    ))
}

fn cleanup_old_cache(max_files: usize) {
    let dir = cache_dir();
    let Ok(rd) = fs::read_dir(&dir) else {
        return;
    };
    let mut files: Vec<(PathBuf, SystemTime)> = rd
        .flatten()
        .filter_map(|e| {
            let p = e.path();
            let name = p.file_name()?.to_str()?;
            if (name.starts_with("field_") || name.starts_with("line_")) && name.ends_with(".png") {
                let mt = e.metadata().ok()?.modified().ok()?;
                Some((p, mt))
            } else {
                None
            }
        })
        .collect();
    if files.len() <= max_files {
        return;
    }
    files.sort_by(|a, b| b.1.cmp(&a.1));
    for (old, _) in files.into_iter().skip(max_files) {
        let _ = fs::remove_file(old);
    }
}

pub fn run(args: &[String]) -> i32 {
    let wall_path = args.first().map(|s| s.as_str()).unwrap_or("");
    let cdir = cache_dir();
    let _ = fs::create_dir_all(&cdir);
    cleanup_old_cache(16);

    if !wall_path.is_empty() && Path::new(wall_path).is_file() {
        if let Some((out_field, out_line)) = generate_perfil(Path::new(wall_path)) {
            println!(
                "{}",
                json!({ "ok": true, "kind": "perfil", "field": out_field, "line": out_line })
            );
            return 0;
        }
    }

    let now_f = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0);
    let key = &sha256_hex(&format!("{wall_path}:{now_f}"))[..12];
    let out_field = cdir.join(format!("field_{key}.png"));
    let out_line = cdir.join(format!("line_{key}.png"));

    if !generate_contagio(&out_field, &out_line) {
        println!("{}", json!({ "ok": false, "kind": "none" }));
        return 1;
    }
    println!(
        "{}",
        json!({
            "ok": true,
            "kind": "contagio",
            "field": out_field.to_string_lossy(),
            "line": out_line.to_string_lossy(),
        })
    );
    0
}
