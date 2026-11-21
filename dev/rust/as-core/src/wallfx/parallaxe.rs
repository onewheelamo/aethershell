use crate::common::paths::{expand_home, home_dir};
use crate::wallfx::depth_mask;
use crate::wallfx::img_ops::{
    affiner_contour_rgb, birefnet_path, birefnet_valide, cover_gray, cover_rgb, depth_data_dir,
    dilate_bin, download_file, gaussian_blur_f32, lissage_smoothstep, make_rgb, percentile_f32,
    save_rgba_with_alpha, BIREFNET_MIN_SIZE, BIREFNET_URL,
};
use image::{GrayImage, RgbImage};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

const NOMS: [&str; 3] = ["1-lointain.png", "2-moyen.png", "3-proche.png"];

fn legacy_rmbg_model() -> PathBuf {
    depth_data_dir().join("models/rmbg-1.4.onnx")
}

fn statut() -> i32 {
    let ok_biref = birefnet_valide();
    let leg = legacy_rmbg_model();
    if !ok_biref && leg.is_file() {
        let _ = fs::remove_file(&leg);
    }
    let taille_mo = if ok_biref {
        let sz = fs::metadata(birefnet_path()).map(|m| m.len()).unwrap_or(0);
        ((sz as f64 / (1024.0 * 1024.0)) * 10.0).round() / 10.0
    } else {
        0.0
    };
    println!(
        "{}",
        json!({
            "ok": true,
            "rmbg": ok_biref,
            "installed": ok_biref,
            "model": if ok_biref { "BiRefNet-lite FP16 + Depth V2 HD" } else { "Depth Anything V2 Small HD" },
            "path": birefnet_path().to_string_lossy(),
            "size_mb": taille_mo,
        })
    );
    0
}

fn installer() -> i32 {
    let _ = depth_mask::run(&["setup".to_string()]);
    let leg = legacy_rmbg_model();
    if leg.is_file() {
        let _ = fs::remove_file(&leg);
    }
    if birefnet_valide() {
        return statut();
    }
    if let Err(e) = download_file(BIREFNET_URL, &birefnet_path(), None, Some(BIREFNET_MIN_SIZE)) {
        println!("{}", json!({ "ok": false, "rmbg": false, "error": e }));
        return 1;
    }
    let _ = depth_mask::run(&["clear-cache".to_string()]);
    statut()
}

fn supprimer() -> i32 {
    for p in [
        birefnet_path(),
        birefnet_path().with_extension("part"),
        legacy_rmbg_model(),
    ] {
        let _ = fs::remove_file(p);
    }
    let _ = depth_mask::run(&["clear-cache".to_string()]);
    statut()
}

fn inpaint_rgb(img: &RgbImage, masque_trou: &[bool], rayon_dilat: usize) -> RgbImage {
    let (w, h) = (img.width() as usize, img.height() as usize);
    let n = w * h;
    let m_bin: Vec<f32> = masque_trou.iter().map(|&b| if b { 1.0 } else { 0.0 }).collect();
    let m_dil = dilate_bin(&m_bin, w, h, (rayon_dilat / 2).max(1));
    let hole: Vec<bool> = m_dil.iter().map(|&v| v > 0.5).collect();
    if !hole.iter().any(|&b| b) {
        return img.clone();
    }

    let raw = img.as_raw();
    let mut left_idx = vec![0usize; n];
    let mut has_left = vec![false; n];
    let mut right_idx = vec![0usize; n];
    let mut has_right = vec![false; n];

    for y in 0..h {
        let row = y * w;
        let mut last_l = 0usize;
        let mut seen_l = false;
        for x in 0..w {
            let idx = row + x;
            if !hole[idx] {
                last_l = x;
                seen_l = true;
            }
            left_idx[idx] = last_l;
            has_left[idx] = seen_l;
        }
        let mut last_r = w - 1;
        let mut seen_r = false;
        for x in (0..w).rev() {
            let idx = row + x;
            if !hole[idx] {
                last_r = x;
                seen_r = true;
            }
            right_idx[idx] = last_r;
            has_right[idx] = seen_r;
        }
    }

    let mut med = [0.0f32; 3];
    for c in 0..3 {
        let vals: Vec<f32> = (0..n).step_by(8).map(|i| raw[i * 3 + c] as f32).collect();
        med[c] = percentile_f32(&vals, 50.0);
    }

    let mut fill = vec![0u8; n * 3];
    for y in 0..h {
        let row = y * w;
        for x in 0..w {
            let idx = row + x;
            let li = row + left_idx[idx];
            let ri = row + right_idx[idx];
            let dl = (x as isize - left_idx[idx] as isize).abs().max(1) as f32;
            let dr = (right_idx[idx] as isize - x as isize).abs().max(1) as f32;
            let wl = if has_left[idx] { 1.0 / dl } else { 0.0 };
            let wr = if has_right[idx] { 1.0 / dr } else { 0.0 };
            let wsum = wl + wr;
            for c in 0..3 {
                let v = if wsum < 1e-6 {
                    med[c]
                } else {
                    (raw[li * 3 + c] as f32 * wl + raw[ri * 3 + c] as f32 * wr) / wsum
                };
                fill[idx * 3 + c] = v.clamp(0.0, 255.0) as u8;
            }
        }
    }

    let fill_im = make_rgb(w as u32, h as u32, fill);
    let small_w = (w as u32 / 4).max(16);
    let small_h = (h as u32 / 4).max(16);
    let small = image::imageops::resize(&fill_im, small_w, small_h, image::imageops::FilterType::Triangle);
    let sraw = small.as_raw();
    let sn = (small_w * small_h) as usize;
    let mut sr = vec![0.0f32; sn];
    let mut sg = vec![0.0f32; sn];
    let mut sb = vec![0.0f32; sn];
    for i in 0..sn {
        sr[i] = sraw[i * 3] as f32;
        sg[i] = sraw[i * 3 + 1] as f32;
        sb[i] = sraw[i * 3 + 2] as f32;
    }
    let srb = gaussian_blur_f32(&sr, small_w as usize, small_h as usize, 3.5);
    let sgb = gaussian_blur_f32(&sg, small_w as usize, small_h as usize, 3.5);
    let sbb = gaussian_blur_f32(&sb, small_w as usize, small_h as usize, 3.5);
    let mut blurred_small = vec![0u8; sn * 3];
    for i in 0..sn {
        blurred_small[i * 3] = srb[i].clamp(0.0, 255.0) as u8;
        blurred_small[i * 3 + 1] = sgb[i].clamp(0.0, 255.0) as u8;
        blurred_small[i * 3 + 2] = sbb[i].clamp(0.0, 255.0) as u8;
    }
    let up_fill = image::imageops::resize(
        &make_rgb(small_w, small_h, blurred_small),
        w as u32,
        h as u32,
        image::imageops::FilterType::Triangle,
    );
    let u_raw = up_fill.as_raw();
    let soft_m = gaussian_blur_f32(&m_dil, w, h, 4.0);
    let mut out = vec![0u8; n * 3];
    for i in 0..n {
        let sm = soft_m[i].clamp(0.0, 1.0);
        for c in 0..3 {
            let v = raw[i * 3 + c] as f32 * (1.0 - sm) + u_raw[i * 3 + c] as f32 * sm;
            out[i * 3 + c] = v.clamp(0.0, 255.0) as u8;
        }
    }
    make_rgb(w as u32, h as u32, out)
}

fn generate(
    fond: &Path,
    sortie: &Path,
    seuil_bas: i32,
    seuil_haut: i32,
    masque_de: Option<&str>,
    ecran: Option<(u32, u32)>,
) -> i32 {
    let fond = fs::canonicalize(fond).unwrap_or_else(|_| fond.to_path_buf());
    if !fond.exists() {
        eprintln!("fond introuvable : {}", fond.display());
        return 1;
    }

    let masque_peint_path = masque_de
        .map(expand_home)
        .filter(|p| p.is_file());
    let masque_peint = masque_peint_path.is_some();

    let chemin_masque = if let Some(p) = masque_peint_path {
        p
    } else {
        match depth_mask::generer_brut(&fond) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("carte de profondeur indisponible : {e}");
                return 1;
            }
        }
    };

    let Ok(dyn_fond) = image::open(&fond) else {
        eprintln!("impossible d'ouvrir {}", fond.display());
        return 1;
    };
    let mut rgb = dyn_fond.to_rgb8();
    if let Some((ew, eh)) = ecran {
        rgb = cover_rgb(&rgb, ew, eh);
    }
    let _ = fs::create_dir_all(sortie);

    let Ok(dyn_m) = image::open(&chemin_masque) else {
        eprintln!("impossible d'ouvrir {}", chemin_masque.display());
        return 1;
    };
    let mut alpha_img: GrayImage = if dyn_m.color().has_alpha() {
        let rgba = dyn_m.to_rgba8();
        GrayImage::from_fn(rgba.width(), rgba.height(), |x, y| image::Luma([rgba.get_pixel(x, y)[3]]))
    } else {
        dyn_m.to_luma8()
    };
    if (alpha_img.width(), alpha_img.height()) != (rgb.width(), rgb.height()) {
        alpha_img = if ecran.is_some() {
            cover_gray(&alpha_img, rgb.width(), rgb.height())
        } else {
            image::imageops::resize(&alpha_img, rgb.width(), rgb.height(), image::imageops::FilterType::Lanczos3)
        };
    }

    let (w, h) = (rgb.width() as usize, rgb.height() as usize);
    let n = w * h;
    let a: Vec<f32> = alpha_img.as_raw().iter().map(|&v| v as f32 / 255.0).collect();

    let (proche, moyen) = if masque_peint {
        let p = lissage_smoothstep(&a, (seuil_haut - 10) as f32 / 100.0, (seuil_haut + 5) as f32 / 100.0);
        let m_raw = lissage_smoothstep(&a, (seuil_bas - 5) as f32 / 100.0, (seuil_bas + 10) as f32 / 100.0);
        let m: Vec<f32> = m_raw.iter().zip(&p).map(|(&mv, &pv)| (mv - pv).clamp(0.0, 1.0)).collect();
        (p, m)
    } else {
        let part_fond = a.iter().filter(|&&v| v < 0.22).count() as f32 / n as f32;
        let part_moyen = a.iter().filter(|&&v| (0.22..=0.48).contains(&v)).count() as f32 / n as f32;
        if part_fond > 0.54 && part_moyen < 0.10 {
            let mut p = lissage_smoothstep(&a, 0.25, 0.42);
            if !birefnet_valide() {
                p = affiner_contour_rgb(&rgb, &p, 10, 0.09, 1, None);
            }
            for v in &mut p {
                *v = ((*v - 0.04) / 0.92).clamp(0.0, 1.0);
            }
            (p, vec![0.0f32; n])
        } else {
            let s_haut_lo = ((seuil_haut - 17) as f32 / 100.0).max(0.42);
            let s_haut_hi = ((seuil_haut - 7) as f32 / 100.0).min(0.72);
            let mut proche_brut = lissage_smoothstep(&a, s_haut_lo, s_haut_hi);

            let y90 = (h as f32 * 0.90) as usize;
            let couv_bas = proche_brut[y90 * w..].iter().filter(|&&v| v > 0.5).count() as f32
                / ((h - y90) * w).max(1) as f32;
            let y45 = (h as f32 * 0.45) as usize;
            let y75 = (h as f32 * 0.75) as usize;
            let couv_milieu = proche_brut[y45 * w..y75 * w].iter().filter(|&&v| v > 0.5).count() as f32
                / ((y75 - y45) * w).max(1) as f32;
            if couv_bas > 0.70 && couv_milieu < 0.25 {
                for y in 0..h {
                    let yy = y as f32 / (h - 1).max(1) as f32;
                    let t = ((yy - 0.80) / 0.10).clamp(0.0, 1.0);
                    let att = 1.0 - t * t * (3.0 - 2.0 * t);
                    for x in 0..w {
                        proche_brut[y * w + x] *= att;
                    }
                }
            }

            let porte_3d: Vec<f32> = a.iter().map(|&v| ((v - 0.10) / 0.08).clamp(0.0, 1.0)).collect();
            let p1 = affiner_contour_rgb(&rgb, &proche_brut, 18, 0.075, 6, Some(&porte_3d));
            let mut porte_ciel = vec![1.0f32; n];
            let y56 = (h as f32 * 0.56) as usize;
            porte_ciel[y56 * w..].copy_from_slice(&porte_3d[y56 * w..]);
            let mut p2 = affiner_contour_rgb(&rgb, &p1, 20, 0.068, 5, Some(&porte_ciel));
            for v in &mut p2 {
                *v = ((*v - 0.06) / 0.88).clamp(0.0, 1.0);
            }

            let s_bas_lo = ((seuil_bas - 12) as f32 / 100.0).max(0.14);
            let s_bas_hi = ((seuil_bas - 2) as f32 / 100.0).max(s_bas_lo + 0.08);
            let fg_brut = lissage_smoothstep(&a, s_bas_lo, s_bas_hi);
            let fg_total = affiner_contour_rgb(&rgb, &fg_brut, 12, 0.085, 1, None);
            let m: Vec<f32> = fg_total
                .iter()
                .zip(&p2)
                .map(|(&f, &pv)| (f.max(pv) - pv).clamp(0.0, 1.0))
                .collect();
            (p2, m)
        }
    };

    let mask_lointain: Vec<bool> = moyen.iter().zip(&proche).map(|(&m, &p)| (m + p) > 0.15).collect();
    let mask_moyen: Vec<bool> = proche.iter().map(|&p| p > 0.15).collect();
    let rgb_lointain = inpaint_rgb(&rgb, &mask_lointain, 11);
    let rgb_moyen = if moyen.iter().any(|&v| v > 0.05) {
        inpaint_rgb(&rgb, &mask_moyen, 9)
    } else {
        rgb.clone()
    };
    let poids_lointain = vec![1.0f32; n];

    for (nom, base_img, poids) in [
        (NOMS[0], &rgb_lointain, &poids_lointain),
        (NOMS[1], &rgb_moyen, &moyen),
        (NOMS[2], &rgb, &proche),
    ] {
        let dest = sortie.join(nom);
        if let Err(e) = save_rgba_with_alpha(base_img, poids, &dest) {
            eprintln!("erreur sauvegarde {nom}: {e}");
            return 1;
        }
        let kio = fs::metadata(&dest).map(|m| m.len() / 1024).unwrap_or(0);
        println!("  {nom}  {kio} Kio");
    }
    0
}

pub fn run(args: &[String]) -> i32 {
    let first = args.first().map(|s| s.as_str()).unwrap_or("status");
    match first {
        "status" => return statut(),
        "setup" => return installer(),
        "remove" => return supprimer(),
        _ => {}
    }

    let mut wallpaper = String::new();
    let mut out = home_dir().join("Images/wallpapers/profondeur");
    let mut seuil_bas = 30i32;
    let mut seuil_haut = 65i32;
    let mut masque_de: Option<String> = None;
    let mut ecran: Option<(u32, u32)> = None;

    let mut i = if first == "generate" { 1 } else { 0 };
    while i < args.len() {
        match args[i].as_str() {
            "--wallpaper" if i + 1 < args.len() => { wallpaper = args[i + 1].clone(); i += 2; }
            "--out" if i + 1 < args.len() => { out = expand_home(&args[i + 1]); i += 2; }
            "--seuil-bas" if i + 1 < args.len() => { seuil_bas = args[i + 1].parse().unwrap_or(30); i += 2; }
            "--seuil-haut" if i + 1 < args.len() => { seuil_haut = args[i + 1].parse().unwrap_or(65); i += 2; }
            "--masque-de" if i + 1 < args.len() => { masque_de = Some(args[i + 1].clone()); i += 2; }
            "--ecran" if i + 1 < args.len() => {
                let parts: Vec<&str> = args[i + 1].split('x').collect();
                if parts.len() == 2 {
                    if let (Ok(w), Ok(h)) = (parts[0].parse(), parts[1].parse()) {
                        ecran = Some((w, h));
                    }
                }
                i += 2;
            }
            _ => i += 1,
        }
    }
    if wallpaper.is_empty() {
        eprintln!("--wallpaper est requis");
        return 2;
    }
    generate(&expand_home(&wallpaper), &out, seuil_bas, seuil_haut, masque_de.as_deref(), ecran)
}
