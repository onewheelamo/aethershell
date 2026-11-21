use crate::common::paths::expand_home;
use crate::wallfx::img_ops::gaussian_blur_f32;
use image::{Rgba, RgbaImage};
use serde_json::{json, Value};
use std::fs;
use std::io::{self, BufRead, Read};

fn fill_disk(buf: &mut [u8], w: usize, h: usize, cx: f64, cy: f64, r: f64) {
    let x0 = ((cx - r).floor() as isize).max(0) as usize;
    let x1 = ((cx + r).ceil() as isize).min((w - 1) as isize) as usize;
    let y0 = ((cy - r).floor() as isize).max(0) as usize;
    let y1 = ((cy + r).ceil() as isize).min((h - 1) as isize) as usize;
    let r2 = r * r;
    for y in y0..=y1 {
        let dy = y as f64 - cy;
        for x in x0..=x1 {
            let dx = x as f64 - cx;
            if dx * dx + dy * dy <= r2 {
                buf[y * w + x] = 255;
            }
        }
    }
}

fn fill_capsule(buf: &mut [u8], w: usize, h: usize, p0: (f64, f64), p1: (f64, f64), r: f64) {
    let (x0, y0) = p0;
    let (x1, y1) = p1;
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len2 = dx * dx + dy * dy;
    let minx = (x0.min(x1) - r).floor().max(0.0) as usize;
    let maxx = (x0.max(x1) + r).ceil().min((w - 1) as f64) as usize;
    let miny = (y0.min(y1) - r).floor().max(0.0) as usize;
    let maxy = (y0.max(y1) + r).ceil().min((h - 1) as f64) as usize;
    let r2 = r * r;
    for y in miny..=maxy {
        for x in minx..=maxx {
            let px = x as f64;
            let py = y as f64;
            let t = if len2 > 1e-9 {
                (((px - x0) * dx + (py - y0) * dy) / len2).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let cx = x0 + t * dx;
            let cy = y0 + t * dy;
            let ddx = px - cx;
            let ddy = py - cy;
            if ddx * ddx + ddy * ddy <= r2 {
                buf[y * w + x] = 255;
            }
        }
    }
}

fn fill_polygon(buf: &mut [u8], w: usize, h: usize, pts: &[(f64, f64)]) {
    if pts.len() < 3 {
        return;
    }
    let mut min_y = h as f64;
    let mut max_y = 0.0f64;
    for &(_, y) in pts {
        if y < min_y { min_y = y; }
        if y > max_y { max_y = y; }
    }
    let y0 = (min_y.floor() as isize).max(0) as usize;
    let y1 = (max_y.ceil() as isize).min((h - 1) as isize) as usize;
    for y in y0..=y1 {
        let fy = y as f64 + 0.5;
        let mut xs = Vec::new();
        for i in 0..pts.len() {
            let (x1, y1p) = pts[i];
            let (x2, y2p) = pts[(i + 1) % pts.len()];
            if (y1p <= fy && y2p > fy) || (y2p <= fy && y1p > fy) {
                let t = (fy - y1p) / (y2p - y1p);
                xs.push(x1 + t * (x2 - x1));
            }
        }
        xs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        for pair in xs.chunks_exact(2) {
            let x_start = (pair[0].floor() as isize).max(0) as usize;
            let x_end = (pair[1].ceil() as isize).min((w - 1) as isize) as usize;
            for x in x_start..=x_end {
                buf[y * w + x] = 255;
            }
        }
    }
}

pub fn run(args: &[String]) -> i32 {
    let mut sortie = String::new();
    let mut ecran = "1920x1080".to_string();
    let mut douceur = 0.15f64;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--sortie" if i + 1 < args.len() => {
                sortie = args[i + 1].clone();
                i += 2;
            }
            "--ecran" if i + 1 < args.len() => {
                ecran = args[i + 1].clone();
                i += 2;
            }
            "--douceur" if i + 1 < args.len() => {
                douceur = args[i + 1].parse::<f64>().unwrap_or(0.15);
                i += 2;
            }
            _ => i += 1,
        }
    }
    if sortie.is_empty() {
        eprintln!("--sortie est requis");
        return 2;
    }
    let parts: Vec<&str> = ecran.split('x').collect();
    let (w, h) = if parts.len() == 2 {
        (
            parts[0].parse::<usize>().unwrap_or(0),
            parts[1].parse::<usize>().unwrap_or(0),
        )
    } else {
        (0, 0)
    };
    if w == 0 || h == 0 {
        eprintln!("--ecran attend LARGEURxHAUTEUR, par exemple 1920x1080");
        return 1;
    }

    let stdin = io::stdin();
    let mut brut = String::new();
    let _ = stdin.lock().read_line(&mut brut);
    if brut.trim().is_empty() {
        let _ = io::stdin().read_to_string(&mut brut);
    }
    if brut.trim().is_empty() {
        eprintln!("aucun trait sur l'entrée standard");
        return 1;
    }
    let Ok(Value::Array(traits)) = serde_json::from_str::<Value>(brut.trim()) else {
        eprintln!("traits illisibles");
        return 1;
    };

    let mut mask = vec![0u8; w * h];
    let mut rayons: Vec<f64> = Vec::new();
    let scale_max = w.max(h) as f64;
    let defauts = 40.0 * scale_max / 1920.0;

    for trait_val in &traits {
        let Some(points) = trait_val.get("points").and_then(|v| v.as_array()) else {
            continue;
        };
        if points.is_empty() {
            continue;
        }
        let pts: Vec<(f64, f64)> = points
            .iter()
            .filter_map(|p| {
                let arr = p.as_array()?;
                let x = arr.first()?.as_f64()? * w as f64;
                let y = arr.get(1)?.as_f64()? * h as f64;
                Some((x, y))
            })
            .collect();
        if pts.is_empty() {
            continue;
        }
        if trait_val.get("genre").and_then(|v| v.as_str()) == Some("contour") {
            fill_polygon(&mut mask, w, h, &pts);
            continue;
        }
        let taille = trait_val.get("taille").and_then(|v| v.as_f64()).unwrap_or(60.0);
        let r = (taille * scale_max / 1920.0 / 2.0).max(1.0);
        rayons.push(r);
        for &(x, y) in &pts {
            fill_disk(&mut mask, w, h, x, y, r);
        }
        for pair in pts.windows(2) {
            fill_capsule(&mut mask, w, h, pair[0], pair[1], r);
        }
    }

    if douceur > 0.0 && rayons.is_empty() {
        rayons.push(defauts / 2.0);
    }

    let alpha_u8: Vec<u8> = if douceur > 0.0 && !rayons.is_empty() {
        let mean_r = rayons.iter().sum::<f64>() / rayons.len() as f64;
        let sigma = (douceur * mean_r).max(2.0) as f32;
        let f: Vec<f32> = mask.iter().map(|&b| b as f32 / 255.0).collect();
        gaussian_blur_f32(&f, w, h, sigma)
            .into_iter()
            .map(|v| (v.clamp(0.0, 1.0) * 255.0).round() as u8)
            .collect()
    } else {
        mask
    };

    let mut rgba = RgbaImage::new(w as u32, h as u32);
    for y in 0..h {
        for x in 0..w {
            rgba.put_pixel(x as u32, y as u32, Rgba([255, 255, 255, alpha_u8[y * w + x]]));
        }
    }

    let out_path = expand_home(&sortie);
    if let Some(parent) = out_path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Err(e) = rgba.save(&out_path) {
        eprintln!("erreur sauvegarde masque: {e}");
        return 1;
    }
    println!(
        "{}",
        json!({ "ok": true, "masque": out_path.to_string_lossy(), "traits": traits.len() })
    );
    0
}
