use crate::common::paths::home_dir;
use half::f16;
use image::imageops::FilterType;
use image::{GrayImage, ImageBuffer, Luma, RgbImage, Rgba, RgbaImage};
use ort::session::builder::GraphOptimizationLevel;
use ort::session::Session;
use ort::value::Tensor;
use sha2::{Digest, Sha256};
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

pub const MODEL_URL: &str =
    "https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/main/onnx/model.onnx";
pub const MODEL_SHA256: &str = "afb6a5c28f3b6bf1e9e0a6e11b7e7f2f6a298a1c69e7c3386d41f3f1d8c65e4c";
pub const MODEL_SIZE: u64 = 99_139_161;
pub const BIREFNET_URL: &str =
    "https://huggingface.co/onnx-community/BiRefNet_lite/resolve/main/onnx/model_fp16.onnx";
pub const BIREFNET_MIN_SIZE: u64 = 100_000_000;

pub fn depth_data_dir() -> PathBuf {
    let cache = env::var("XDG_CACHE_HOME")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".cache"));
    cache.join("quickshell/depth")
}

pub fn model_path() -> PathBuf {
    depth_data_dir().join("models/depth-anything-v2-small.onnx")
}

pub fn birefnet_path() -> PathBuf {
    depth_data_dir().join("models/birefnet-lite-fp16.onnx")
}

pub fn sha256_file(path: &Path) -> Result<String, String> {
    let mut f = File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    let res = hasher.finalize();
    Ok(res.iter().map(|b| format!("{b:02x}")).collect())
}

pub fn modele_valide() -> bool {
    let p = model_path();
    fs::metadata(&p)
        .map(|m| m.is_file() && m.len() == MODEL_SIZE)
        .unwrap_or(false)
}

pub fn birefnet_valide() -> bool {
    let p = birefnet_path();
    fs::metadata(&p)
        .map(|m| m.is_file() && m.len() >= BIREFNET_MIN_SIZE)
        .unwrap_or(false)
}

pub fn download_file(url: &str, dest: &Path, expected_size: Option<u64>, min_size: Option<u64>) -> Result<(), String> {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let part = dest.with_extension("part");
    let _ = fs::remove_file(&part);
    let resp = ureq::get(url)
        .set("User-Agent", "AetherShell/1.0")
        .call()
        .map_err(|e| e.to_string())?;
    let mut reader = resp.into_reader();
    let mut out = File::create(&part).map_err(|e| e.to_string())?;
    std::io::copy(&mut reader, &mut out).map_err(|e| e.to_string())?;
    drop(out);
    let sz = fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
    if let Some(exp) = expected_size {
        if sz != exp {
            let _ = fs::remove_file(&part);
            return Err(format!("taille du modèle inattendue : {sz} octets"));
        }
    }
    if let Some(min_s) = min_size {
        if sz < min_s {
            let _ = fs::remove_file(&part);
            return Err("téléchargement incomplet".to_string());
        }
    }
    fs::rename(&part, dest).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn gaussian_blur_f32(a: &[f32], w: usize, h: usize, sigma: f32) -> Vec<f32> {
    if sigma <= 0.0 || w == 0 || h == 0 {
        return a.to_vec();
    }
    let r = (3.0 * sigma) as isize + 1;
    let mut k = Vec::with_capacity((2 * r + 1) as usize);
    let mut ksum = 0.0f32;
    for i in -r..=r {
        let x = i as f32;
        let v = (-x * x / (2.0 * sigma * sigma)).exp();
        k.push(v);
        ksum += v;
    }
    for v in &mut k {
        *v /= ksum;
    }

    let mut tmp = vec![0.0f32; w * h];
    for y in 0..h {
        let row = y * w;
        for x in 0..w {
            let mut acc = 0.0f32;
            for (ki, dx) in (-r..=r).enumerate() {
                let sx = (x as isize + dx).clamp(0, (w - 1) as isize) as usize;
                acc += k[ki] * a[row + sx];
            }
            tmp[row + x] = acc;
        }
    }
    let mut out = vec![0.0f32; w * h];
    for y in 0..h {
        for x in 0..w {
            let mut acc = 0.0f32;
            for (ki, dy) in (-r..=r).enumerate() {
                let sy = (y as isize + dy).clamp(0, (h - 1) as isize) as usize;
                acc += k[ki] * tmp[sy * w + x];
            }
            out[y * w + x] = acc;
        }
    }
    out
}

pub fn box_blur_2d(a: &[f32], w: usize, h: usize, r: usize) -> Vec<f32> {
    if r == 0 || w == 0 || h == 0 {
        return a.to_vec();
    }
    let k = (2 * r + 1) as f64;
    let mut horiz = vec![0.0f64; w * h];
    for y in 0..h {
        let row = y * w;
        let mut acc = 0.0f64;
        for dx in -(r as isize)..=(r as isize) {
            let sx = dx.clamp(0, (w - 1) as isize) as usize;
            acc += a[row + sx] as f64;
        }
        horiz[row] = acc / k;
        for x in 1..w {
            let add_x = (x as isize + r as isize).min((w - 1) as isize) as usize;
            let rem_x = (x as isize - 1 - r as isize).max(0) as usize;
            acc += a[row + add_x] as f64 - a[row + rem_x] as f64;
            horiz[row + x] = acc / k;
        }
    }
    let mut out = vec![0.0f32; w * h];
    for x in 0..w {
        let mut acc = 0.0f64;
        for dy in -(r as isize)..=(r as isize) {
            let sy = dy.clamp(0, (h - 1) as isize) as usize;
            acc += horiz[sy * w + x];
        }
        out[x] = (acc / k) as f32;
        for y in 1..h {
            let add_y = (y as isize + r as isize).min((h - 1) as isize) as usize;
            let rem_y = (y as isize - 1 - r as isize).max(0) as usize;
            acc += horiz[add_y * w + x] - horiz[rem_y * w + x];
            out[y * w + x] = (acc / k) as f32;
        }
    }
    out
}

pub fn dilate_bin(mask_bin: &[f32], w: usize, h: usize, radius: usize) -> Vec<f32> {
    if radius == 0 {
        return mask_bin.to_vec();
    }
    box_blur_2d(mask_bin, w, h, radius)
        .into_iter()
        .map(|v| if v > 1e-6 { 1.0 } else { 0.0 })
        .collect()
}

pub fn erode_bin(mask_bin: &[f32], w: usize, h: usize, radius: usize) -> Vec<f32> {
    if radius == 0 {
        return mask_bin.to_vec();
    }
    box_blur_2d(mask_bin, w, h, radius)
        .into_iter()
        .map(|v| if v > 1.0 - 1e-6 { 1.0 } else { 0.0 })
        .collect()
}

pub fn affiner_contour_rgb(
    src: &RgbImage,
    mask: &[f32],
    halo_px: usize,
    color_thresh: f32,
    passes: usize,
    porte_profondeur: Option<&[f32]>,
) -> Vec<f32> {
    let w = src.width() as usize;
    let h = src.height() as usize;
    let n = w * h;
    let raw = src.as_raw();
    let mut r_ch = vec![0.0f32; n];
    let mut g_ch = vec![0.0f32; n];
    let mut b_ch = vec![0.0f32; n];
    for i in 0..n {
        r_ch[i] = raw[i * 3] as f32 / 255.0;
        g_ch[i] = raw[i * 3 + 1] as f32 / 255.0;
        b_ch[i] = raw[i * 3 + 2] as f32 / 255.0;
    }

    let mut courant = mask.to_vec();
    let r_in = (halo_px / 4).max(1);
    let r_out = halo_px.max(2);
    let r_ero = 3;
    let r_est = (halo_px * 2).max(12);

    for _ in 0..passes.max(1) {
        let m_bin: Vec<f32> = courant
            .iter()
            .map(|&v| if v > 0.40 { 1.0 } else { 0.0 })
            .collect();
        let dil_inner = dilate_bin(&m_bin, w, h, r_in);
        let dil_outer = dilate_bin(&m_bin, w, h, r_out);
        let eroded = erode_bin(&m_bin, w, h, r_ero);

        let bg_weight: Vec<f32> = dil_inner.iter().map(|&v| 1.0 - v).collect();
        let w_blur = box_blur_2d(&bg_weight, w, h, r_est);

        let rw: Vec<f32> = r_ch.iter().zip(&bg_weight).map(|(&c, &wb)| c * wb).collect();
        let gw: Vec<f32> = g_ch.iter().zip(&bg_weight).map(|(&c, &wb)| c * wb).collect();
        let bw: Vec<f32> = b_ch.iter().zip(&bg_weight).map(|(&c, &wb)| c * wb).collect();

        let rb = box_blur_2d(&rw, w, h, r_est);
        let gb = box_blur_2d(&gw, w, h, r_est);
        let bb = box_blur_2d(&bw, w, h, r_est);

        for i in 0..n {
            let denom = w_blur[i].max(1e-4);
            let dr = r_ch[i] - rb[i] / denom;
            let dg = g_ch[i] - gb[i] / denom;
            let db = b_ch[i] - bb[i] / denom;
            let dist = (dr * dr + dg * dg + db * db).sqrt();
            let halo = (dil_outer[i] - eroded[i]).clamp(0.0, 1.0);
            let contrast = ((dist - color_thresh) / 0.06).clamp(0.0, 1.0);
            let mut ajout = halo * contrast;
            if let Some(porte) = porte_profondeur {
                ajout *= porte[i];
            }
            if ajout > courant[i] {
                courant[i] = ajout;
            }
        }
    }

    let clamped: Vec<f32> = courant.into_iter().map(|v| v.clamp(0.0, 1.0)).collect();
    gaussian_blur_f32(&clamped, w, h, 1.15)
}

pub fn cover_rgb(img: &RgbImage, target_w: u32, target_h: u32) -> RgbImage {
    let (l, h) = (img.width(), img.height());
    if l == target_w && h == target_h {
        return img.clone();
    }
    let scale = (target_w as f64 / l as f64).max(target_h as f64 / h as f64);
    let nl = (l as f64 * scale).round() as u32;
    let nh = (h as f64 * scale).round() as u32;
    let resized = image::imageops::resize(img, nl, nh, FilterType::Lanczos3);
    let x = (nl - target_w) / 2;
    let y = (nh - target_h) / 2;
    image::imageops::crop_imm(&resized, x, y, target_w, target_h).to_image()
}

pub fn cover_gray(img: &GrayImage, target_w: u32, target_h: u32) -> GrayImage {
    let (l, h) = (img.width(), img.height());
    if l == target_w && h == target_h {
        return img.clone();
    }
    let scale = (target_w as f64 / l as f64).max(target_h as f64 / h as f64);
    let nl = (l as f64 * scale).round() as u32;
    let nh = (h as f64 * scale).round() as u32;
    let resized = image::imageops::resize(img, nl, nh, FilterType::Lanczos3);
    let x = (nl - target_w) / 2;
    let y = (nh - target_h) / 2;
    image::imageops::crop_imm(&resized, x, y, target_w, target_h).to_image()
}

pub fn open_ort_session(model: &Path) -> Result<Session, String> {
    let env = ort::init()
        .with_name("as-core")
        .build()
        .map_err(|e| e.to_string())?;
    Session::builder(&env)
        .map_err(|e| e.to_string())?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| e.to_string())?
        .with_intra_threads(2)
        .map_err(|e| e.to_string())?
        .with_inter_threads(1)
        .map_err(|e| e.to_string())?
        .commit_from_file(model)
        .map_err(|e| e.to_string())
}

pub fn run_depth_anything(src: &RgbImage, ml: u32, mh: u32) -> Result<Vec<f32>, String> {
    let resized = image::imageops::resize(src, ml, mh, FilterType::CatmullRom);
    let raw = resized.as_raw();
    let (w, h) = (ml as usize, mh as usize);
    let plane = w * h;
    let mut tensor_data = vec![0.0f32; 3 * plane];
    let mean = [0.485f32, 0.456, 0.406];
    let std = [0.229f32, 0.224, 0.225];
    for y in 0..h {
        for x in 0..w {
            let p_idx = y * w + x;
            let idx = p_idx * 3;
            for c in 0..3 {
                let p = raw[idx + c] as f32 / 255.0;
                tensor_data[c * plane + p_idx] = (p - mean[c]) / std[c];
            }
        }
    }
    let mut sess = open_ort_session(&model_path())?;
    let input_tensor =
        Tensor::from_array(([1usize, 3, h, w], tensor_data.into_boxed_slice()))
            .map_err(|e| e.to_string())?;
    let outputs = sess.run(ort::inputs![input_tensor]).map_err(|e| e.to_string())?;
    let (_, data) = outputs[0].try_extract_tensor::<f32>().map_err(|e| e.to_string())?;
    if data.len() != plane {
        return Err(format!("sortie du modèle de forme inattendue ({} != {})", data.len(), plane));
    }
    Ok(data.to_vec())
}

pub fn run_birefnet(src: &RgbImage, ml_cible: u32, mh_cible: u32) -> Option<Vec<f32>> {
    if !birefnet_valide() {
        return None;
    }
    let im = image::imageops::resize(src, 1024, 1024, FilterType::Triangle);
    let raw = im.as_raw();
    let plane = 1024usize * 1024usize;
    let mut tensor_data = vec![f16::ZERO; 3 * plane];
    let mean = [0.485f32, 0.456, 0.406];
    let std = [0.229f32, 0.224, 0.225];
    for y in 0..1024 {
        for x in 0..1024 {
            let p_idx = y * 1024 + x;
            let idx = p_idx * 3;
            for c in 0..3 {
                let p = raw[idx + c] as f32 / 255.0;
                tensor_data[c * plane + p_idx] = f16::from_f32((p - mean[c]) / std[c]);
            }
        }
    }
    let mut sess = open_ort_session(&birefnet_path()).ok()?;
    let input_tensor =
        Tensor::from_array(([1usize, 3, 1024, 1024], tensor_data.into_boxed_slice())).ok()?;
    let outputs = sess.run(ort::inputs![input_tensor]).ok()?;
    let last_idx = outputs.len().checked_sub(1)?;
    let probs: Vec<f32> = if let Ok((_, d)) = outputs[last_idx].try_extract_tensor::<f16>() {
        d.iter().map(|v| {
            let p = v.to_f32().clamp(-30.0, 30.0);
            1.0 / (1.0 + (-p).exp())
        }).collect()
    } else if let Ok((_, d)) = outputs[last_idx].try_extract_tensor::<f32>() {
        d.iter().map(|&v| {
            let p = v.clamp(-30.0, 30.0);
            1.0 / (1.0 + (-p).exp())
        }).collect()
    } else {
        return None;
    };
    if probs.len() != 1024 * 1024 {
        return None;
    }
    let mut pmin = f32::INFINITY;
    let mut pmax = f32::NEG_INFINITY;
    for &p in &probs {
        if p < pmin { pmin = p; }
        if p > pmax { pmax = p; }
    }
    let span = (pmax - pmin).max(1e-6);
    let bytes: Vec<u8> = probs
        .iter()
        .map(|&p| (((p - pmin) / span) * 255.0).clamp(0.0, 255.0) as u8)
        .collect();
    let prob_im = GrayImage::from_raw(1024, 1024, bytes)?;
    let up = image::imageops::resize(&prob_im, ml_cible, mh_cible, FilterType::CatmullRom);
    Some(up.as_raw().iter().map(|&b| b as f32 / 255.0).collect())
}

pub fn resize_f32_gray(arr: &[f32], src_w: u32, src_h: u32, dst_w: u32, dst_h: u32) -> Vec<f32> {
    let bytes: Vec<u8> = arr
        .iter()
        .map(|&v| (v.clamp(0.0, 1.0) * 255.0).round() as u8)
        .collect();
    let im = ImageBuffer::<Luma<u8>, Vec<u8>>::from_raw(src_w, src_h, bytes)
        .unwrap_or_else(|| GrayImage::new(src_w, src_h));
    let up = image::imageops::resize(&im, dst_w, dst_h, FilterType::CatmullRom);
    up.as_raw().iter().map(|&b| b as f32 / 255.0).collect()
}

pub fn save_rgba_with_alpha(rgb: &RgbImage, alpha_f32: &[f32], dest: &Path) -> Result<(), String> {
    let (w, h) = (rgb.width(), rgb.height());
    let mut rgba = RgbaImage::new(w, h);
    let raw = rgb.as_raw();
    for y in 0..h {
        for x in 0..w {
            let idx = (y * w + x) as usize;
            let a = (alpha_f32[idx].clamp(0.0, 1.0) * 255.0).round() as u8;
            rgba.put_pixel(x, y, Rgba([raw[idx * 3], raw[idx * 3 + 1], raw[idx * 3 + 2], a]));
        }
    }
    let tmp = dest.with_extension(format!("{}.tmp.png", std::process::id()));
    rgba.save(&tmp).map_err(|e| e.to_string())?;
    fs::rename(&tmp, dest).map_err(|e| e.to_string())
}

pub fn save_rgb(rgb: &RgbImage, dest: &Path) -> Result<(), String> {
    let tmp = dest.with_extension(format!("{}.tmp.png", std::process::id()));
    rgb.save(&tmp).map_err(|e| e.to_string())?;
    fs::rename(&tmp, dest).map_err(|e| e.to_string())
}

pub fn percentile_f32(vals: &[f32], pct: f32) -> f32 {
    if vals.is_empty() {
        return 0.0;
    }
    let mut sorted: Vec<f32> = vals.iter().copied().filter(|v| v.is_finite()).collect();
    if sorted.is_empty() {
        return 0.0;
    }
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let pos = (pct / 100.0) * (sorted.len() - 1) as f32;
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    if lo == hi {
        sorted[lo]
    } else {
        sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo as f32)
    }
}

pub fn lissage_smoothstep(a: &[f32], bas: f32, haut: f32) -> Vec<f32> {
    if haut <= bas {
        return a.iter().map(|&v| if v >= haut { 1.0 } else { 0.0 }).collect();
    }
    a.iter()
        .map(|&v| {
            let t = ((v - bas) / (haut - bas)).clamp(0.0, 1.0);
            t * t * (3.0 - 2.0 * t)
        })
        .collect()
}

pub fn make_rgb(w: u32, h: u32, data: Vec<u8>) -> RgbImage {
    RgbImage::from_raw(w, h, data).unwrap_or_else(|| RgbImage::new(w, h))
}
