use crate::common::lock::FileLock;
use crate::common::paths::expand_home;
use crate::wallfx::img_ops::{
    affiner_contour_rgb, birefnet_valide, depth_data_dir, dilate_bin, download_file, model_path,
    modele_valide, percentile_f32, resize_f32_gray, run_birefnet, run_depth_anything,
    save_rgba_with_alpha, sha256_file, MODEL_SHA256, MODEL_SIZE, MODEL_URL,
};
use image::{GrayImage, ImageBuffer, Luma};
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

const INPUT_SIZE: u32 = 924;
const PATCH: u32 = 14;
const VERSION_DEPTH: u32 = 2;
const VERSION_MASQUE: u32 = 10;

fn depth_dir() -> PathBuf {
    depth_data_dir().join("cache/profondeur")
}

fn masque_dir() -> PathBuf {
    depth_data_dir().join("cache/masques")
}

fn taille_inference(largeur: u32, hauteur: u32) -> (u32, u32) {
    if largeur >= hauteur {
        let mh = ((hauteur as f64 / largeur.max(1) as f64 * INPUT_SIZE as f64 / PATCH as f64).round()
            as u32
            * PATCH)
            .max(PATCH);
        (INPUT_SIZE, mh)
    } else {
        let ml = ((largeur as f64 / hauteur.max(1) as f64 * INPUT_SIZE as f64 / PATCH as f64).round()
            as u32
            * PATCH)
            .max(PATCH);
        (ml, INPUT_SIZE)
    }
}

fn prune(dir: &Path, garder: usize) {
    let Ok(rd) = fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<(PathBuf, std::time::SystemTime)> = rd
        .flatten()
        .filter_map(|e| {
            let p = e.path();
            if p.is_file() {
                let mt = e.metadata().ok()?.modified().ok()?;
                Some((p, mt))
            } else {
                None
            }
        })
        .collect();
    if files.len() <= garder {
        return;
    }
    files.sort_by(|a, b| b.1.cmp(&a.1));
    for (p, _) in files.into_iter().skip(garder) {
        let _ = fs::remove_file(p);
    }
}

fn load_bin(path: &Path, expected_w: u32, expected_h: u32) -> Option<Vec<f32>> {
    let bytes = fs::read(path).ok()?;
    if bytes.len() != 8 + expected_w as usize * expected_h as usize * 4 {
        return None;
    }
    let cw = u32::from_le_bytes(bytes[0..4].try_into().ok()?);
    let ch = u32::from_le_bytes(bytes[4..8].try_into().ok()?);
    if cw != expected_w || ch != expected_h {
        return None;
    }
    let mut out = Vec::with_capacity(expected_w as usize * expected_h as usize);
    for chunk in bytes[8..].chunks_exact(4) {
        out.push(f32::from_le_bytes(chunk.try_into().ok()?));
    }
    Some(out)
}

fn save_bin(path: &Path, w: u32, h: u32, data: &[f32]) {
    let mut raw = Vec::with_capacity(8 + data.len() * 4);
    raw.extend_from_slice(&w.to_le_bytes());
    raw.extend_from_slice(&h.to_le_bytes());
    for &v in data {
        raw.extend_from_slice(&v.to_le_bytes());
    }
    let tmp = path.with_extension("tmp");
    if fs::write(&tmp, &raw).is_ok() {
        let _ = fs::rename(&tmp, path);
    }
}

fn fusionner_profondeur_et_contours(
    source: &image::RgbImage,
    profondeur: &[f32],
    ml: u32,
    mh: u32,
    biref_cache: &Path,
) -> Vec<f32> {
    let (l, h) = (source.width(), source.height());
    let (w_u, h_u) = (l as usize, h as usize);
    let mut pleine = resize_f32_gray(profondeur, ml, mh, l, h);

    let biref = if let Some(cached) = load_bin(biref_cache, l, h) {
        Some(cached)
    } else if let Some(res) = run_birefnet(source, l, h) {
        save_bin(biref_cache, l, h, &res);
        Some(res)
    } else {
        None
    };

    if let Some(biref) = biref {
        let n = w_u * h_u;
        let ratio_fond_3d = pleine.iter().filter(|&&v| v < 0.22).count() as f32 / n as f32;
        let couv_biref = biref.iter().filter(|&&v| v > 0.5).count() as f32 / n as f32;
        if ratio_fond_3d > 0.54 && (0.03..0.48).contains(&couv_biref) {
            return pleine
                .iter()
                .zip(&biref)
                .map(|(&p, &b)| {
                    let porte_3d = ((p - 0.14) / 0.10).clamp(0.0, 1.0);
                    let sujet = ((b * porte_3d - 0.08) / 0.84).clamp(0.0, 1.0);
                    if sujet > 0.02 { 0.28 + 0.72 * sujet } else { 0.0 }
                })
                .collect();
        } else if (0.03..0.85).contains(&couv_biref) {
            let mut fg_seed: Vec<f32> = pleine.iter().map(|&p| if p > 0.48 { 1.0 } else { 0.0 }).collect();
            let cand: Vec<f32> = biref
                .iter()
                .zip(&pleine)
                .map(|(&b, &p)| if b > 0.25 && p > 0.14 { 1.0 } else { 0.0 })
                .collect();
            for _ in 0..4 {
                let dil = dilate_bin(&fg_seed, w_u, h_u, 32);
                for i in 0..n {
                    let add = dil[i] * cand[i];
                    if add > fg_seed[i] {
                        fg_seed[i] = add;
                    }
                }
            }
            for i in 0..n {
                let boost = fg_seed[i] * biref[i].max(0.85) * 0.92;
                if boost > pleine[i] {
                    pleine[i] = boost;
                }
            }
        }
    }
    pleine.into_iter().map(|v| v.clamp(0.0, 1.0)).collect()
}

pub fn generer_brut(fond: &Path) -> Result<PathBuf, String> {
    let resolved = fs::canonicalize(fond).unwrap_or_else(|_| fond.to_path_buf());
    let val = generer(&resolved, 0.30, 0.08, true)?;
    val.get("brut")
        .and_then(|v| v.as_str())
        .map(PathBuf::from)
        .ok_or_else(|| "carte de profondeur indisponible".to_string())
}

fn generer(fond: &Path, seuil: f32, adouci: f32, brut: bool) -> Result<Value, String> {
    if !fond.is_file() {
        return Err(format!("fond introuvable : {}", fond.display()));
    }
    if !modele_valide() {
        return Err("modèle absent ou invalide — lancer `setup`".to_string());
    }
    let seuil = seuil.clamp(0.0, 1.0);
    let adouci = adouci.clamp(0.0, 0.5);
    let debut = Instant::now();

    let empreinte = sha256_file(fond)?;
    let biref_tag = if birefnet_valide() { "b1" } else { "b0" };
    let cle = format!("{empreinte}-m{}-d{VERSION_DEPTH}-i{INPUT_SIZE}-{biref_tag}", &MODEL_SHA256[..16]);
    let ddir = depth_dir();
    let mdir = masque_dir();
    fs::create_dir_all(&ddir).map_err(|e| e.to_string())?;
    fs::create_dir_all(&mdir).map_err(|e| e.to_string())?;

    let chemin_profondeur = ddir.join(format!("{cle}.bin"));
    let chemin_biref = ddir.join(format!("{empreinte}-biref.bin"));
    let cle_masque = format!("{cle}-v{VERSION_MASQUE}-t{seuil:.4}-f{adouci:.4}");
    let chemin_masque = mdir.join(format!("{cle_masque}.png"));
    let chemin_brut = mdir.join(format!("{cle}-brut-v{VERSION_MASQUE}.png"));

    let _lock = FileLock::acquire(&depth_data_dir().join("generation"));
    let source = image::open(fond).map_err(|e| e.to_string())?.to_rgb8();
    let (l, h) = (source.width(), source.height());
    let (ml, mh) = taille_inference(l, h);

    let (profondeur, cache) = if let Some(cached) = load_bin(&chemin_profondeur, ml, mh) {
        (cached, true)
    } else {
        let brut_out = run_depth_anything(&source, ml, mh)?;
        let mini = percentile_f32(&brut_out, 1.5);
        let maxi = percentile_f32(&brut_out, 99.2);
        if !mini.is_finite() || !maxi.is_finite() || maxi <= mini {
            return Err("carte de profondeur invalide".to_string());
        }
        let prof: Vec<f32> = brut_out
            .iter()
            .map(|&v| ((v - mini) / (maxi - mini)).clamp(0.0, 1.0))
            .collect();
        save_bin(&chemin_profondeur, ml, mh, &prof);
        (prof, false)
    };

    if brut && !chemin_brut.is_file() {
        let pleine = fusionner_profondeur_et_contours(&source, &profondeur, ml, mh, &chemin_biref);
        let bytes: Vec<u8> = pleine
            .iter()
            .map(|&v| (v.clamp(0.0, 1.0) * 255.0).round() as u8)
            .collect();
        let gris = ImageBuffer::<Luma<u8>, Vec<u8>>::from_raw(l, h, bytes)
            .unwrap_or_else(|| GrayImage::new(l, h));
        let tmp = chemin_brut.with_extension("tmp.png");
        gris.save(&tmp).map_err(|e| e.to_string())?;
        fs::rename(&tmp, &chemin_brut).map_err(|e| e.to_string())?;
    }

    if !brut && !chemin_masque.is_file() {
        let pleine = fusionner_profondeur_et_contours(&source, &profondeur, ml, mh, &chemin_biref);
        let demi = adouci * 0.5;
        let mut alpha: Vec<f32> = pleine
            .iter()
            .map(|&p| {
                let t = if demi > 0.0 {
                    ((p - (seuil - demi)) / (2.0 * demi).max(1e-6)).clamp(0.0, 1.0)
                } else if p >= seuil {
                    1.0
                } else {
                    0.0
                };
                t * t * (3.0 - 2.0 * t)
            })
            .collect();
        let ratio_fond = pleine.iter().filter(|&&v| v < 0.20).count() as f32 / pleine.len().max(1) as f32;
        if ratio_fond <= 0.54 {
            let (w_u, h_u) = (l as usize, h as usize);
            let mut porte_ciel = vec![1.0f32; w_u * h_u];
            let y_split = (h_u as f32 * 0.56) as usize;
            for i in (y_split * w_u)..(w_u * h_u) {
                porte_ciel[i] = ((pleine[i] - 0.10) / 0.08).clamp(0.0, 1.0);
            }
            alpha = affiner_contour_rgb(&source, &alpha, 18, 0.070, 5, Some(&porte_ciel));
        }
        for v in &mut alpha {
            *v = ((*v - 0.06) / 0.88).clamp(0.0, 1.0);
        }
        save_rgba_with_alpha(&source, &alpha, &chemin_masque)?;
    }

    prune(&ddir, 8);
    prune(&mdir, 32);

    if brut {
        Ok(json!({ "ok": true, "brut": chemin_brut.to_string_lossy() }))
    } else {
        Ok(json!({
            "ok": true,
            "cache": cache,
            "duree_ms": debut.elapsed().as_millis() as u64,
            "largeur": l,
            "hauteur": h,
            "masque": chemin_masque.to_string_lossy(),
            "fond": fond.to_string_lossy(),
        }))
    }
}

pub fn run(args: &[String]) -> i32 {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("status");
    let mut wallpaper: Option<PathBuf> = None;
    let mut threshold = 0.30f32;
    let mut feather = 0.08f32;
    let mut brut = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--wallpaper" if i + 1 < args.len() => {
                wallpaper = Some(expand_home(&args[i + 1]));
                i += 2;
            }
            "--threshold" if i + 1 < args.len() => {
                threshold = args[i + 1].parse().unwrap_or(0.30);
                i += 2;
            }
            "--feather" if i + 1 < args.len() => {
                feather = args[i + 1].parse().unwrap_or(0.08);
                i += 2;
            }
            "--brut" => {
                brut = true;
                i += 1;
            }
            _ => i += 1,
        }
    }

    match cmd {
        "setup" => {
            if !modele_valide() {
                if let Err(e) = download_file(MODEL_URL, &model_path(), Some(MODEL_SIZE), None) {
                    eprintln!("{e}");
                    println!("{}", json!({ "ok": false, "error": e }));
                    return 1;
                }
            }
            println!(
                "{}",
                json!({
                    "ok": true,
                    "runtime": true,
                    "modele": modele_valide(),
                    "cheminModele": model_path().to_string_lossy(),
                })
            );
            0
        }
        "status" => {
            println!(
                "{}",
                json!({
                    "ok": true,
                    "runtime": true,
                    "modele": modele_valide(),
                    "cheminModele": model_path().to_string_lossy(),
                    "cache": masque_dir().to_string_lossy(),
                })
            );
            0
        }
        "clear-cache" => {
            let _ = fs::remove_dir_all(depth_data_dir().join("cache"));
            println!("{}", json!({ "ok": true, "vide": true }));
            0
        }
        "generate" => {
            let Some(wp) = wallpaper else {
                let err = "--wallpaper est requis";
                eprintln!("{err}");
                println!("{}", json!({ "ok": false, "error": err }));
                return 1;
            };
            let resolved = fs::canonicalize(&wp).unwrap_or(wp);
            match generer(&resolved, threshold, feather, brut) {
                Ok(v) => {
                    println!("{v}");
                    0
                }
                Err(e) => {
                    eprintln!("{e}");
                    println!("{}", json!({ "ok": false, "error": e }));
                    1
                }
            }
        }
        _ => {
            println!("{}", json!({ "ok": false, "error": format!("commande inconnue: {cmd}") }));
            2
        }
    }
}
