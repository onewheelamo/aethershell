use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd, write_json_atomic};
use crate::common::lock::FileLock;
use crate::common::paths::{core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

fn dossiers() -> Vec<PathBuf> {
    vec![
        home_dir().join(".local/share/color-schemes"),
        PathBuf::from("/usr/share/color-schemes"),
    ]
}

fn style_file() -> PathBuf {
    core_dir().join("style_vars.json")
}

fn cache_file() -> PathBuf {
    core_dir().join("palette_cache.json")
}

fn slug(chemin: &Path) -> String {
    let stem = chemin
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("sans-nom")
        .to_ascii_lowercase();
    let mut out = String::new();
    let mut prev_dash = true;
    for ch in stem.chars() {
        let mapped = match ch {
            'à' | 'â' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' => 'i',
            'ô' | 'ö' => 'o',
            'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            c if c.is_ascii_alphanumeric() => c,
            _ => '-',
        };
        if mapped == '-' {
            if !prev_dash {
                out.push('-');
                prev_dash = true;
            }
        } else {
            out.push(mapped);
            prev_dash = false;
        }
    }
    let clean = out.trim_matches('-');
    if clean.is_empty() {
        "kde-sans-nom".to_string()
    } else {
        format!("kde-{clean}")
    }
}

fn normaliser_couleur(brut: &str) -> Option<String> {
    let val = brut.trim();
    if val.is_empty() {
        return None;
    }
    if let Some(cap) = Regex::new(r"^(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})$")
        .ok()
        .and_then(|re| re.captures(val))
    {
        let r = cap[1].parse::<u8>().unwrap_or(0);
        let g = cap[2].parse::<u8>().unwrap_or(0);
        let b = cap[3].parse::<u8>().unwrap_or(0);
        return Some(format!("#{r:02x}{g:02x}{b:02x}"));
    }
    if let Some(cap) = Regex::new(r"^#?([0-9a-fA-F]{8}|[0-9a-fA-F]{6})$")
        .ok()
        .and_then(|re| re.captures(val))
    {
        let hex = &cap[1];
        let six = if hex.len() == 8 { &hex[2..] } else { hex };
        return Some(format!("#{}", six.to_ascii_lowercase()));
    }
    None
}

fn parse_colors_ini(chemin: &Path) -> Option<Value> {
    let bytes = fs::read(chemin).ok()?;
    let content = String::from_utf8(bytes.clone())
        .unwrap_or_else(|_| bytes.iter().map(|&b| b as char).collect());

    let mut sections: HashMap<String, HashMap<String, String>> = HashMap::new();
    let mut cur_sec = String::new();
    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            cur_sec = line[1..line.len() - 1].to_string();
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            sections
                .entry(cur_sec.clone())
                .or_default()
                .insert(k.trim().to_string(), v.trim().to_string());
        }
    }

    if !sections.contains_key("Colors:Window") {
        return None;
    }
    let get = |sec: &str, opt: &str| -> Option<String> {
        sections
            .get(sec)
            .and_then(|m| m.get(opt))
            .and_then(|v| normaliser_couleur(v))
    };

    let fond = get("Colors:Window", "BackgroundNormal")?;
    let texte = get("Colors:Window", "ForegroundNormal")?;
    let accent = get("Colors:Selection", "BackgroundNormal").unwrap_or_else(|| texte.clone());
    let accent_muted = get("Colors:Window", "DecorationFocus").unwrap_or_else(|| accent.clone());
    let surface = get("Colors:View", "BackgroundNormal").unwrap_or_else(|| fond.clone());
    let surface_variant = get("Colors:Button", "BackgroundNormal").unwrap_or_else(|| surface.clone());
    let erreur = get("Colors:Window", "ForegroundNegative").unwrap_or_else(|| "#ffb4ab".into());
    let warn = get("Colors:Window", "ForegroundNeutral").unwrap_or_else(|| "#f6bb7d".into());
    let info = get("Colors:Selection", "BackgroundNormal").unwrap_or_else(|| "#f3bb9a".into());
    let success = get("Colors:Window", "ForegroundPositive").unwrap_or_else(|| "#a6e3a1".into());

    let nom = sections
        .get("General")
        .and_then(|m| m.get("Name"))
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            chemin
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Theme")
                .to_string()
        });

    Some(json!({
        "nom": nom,
        "palette": {
            "bg": fond,
            "fg": texte,
            "accent": accent,
            "accent_muted": accent_muted,
            "surface": surface,
            "surface_variant": surface_variant,
            "error": erreur,
            "warn": warn,
            "info": info,
            "success": success,
        },
        "fichier": chemin.to_string_lossy(),
    }))
}

pub fn detecter() -> BTreeMap<String, Value> {
    let mut trouves = BTreeMap::new();
    for dossier in dossiers() {
        if !dossier.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&dossier) else { continue };
        let mut paths: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("colors"))
            .collect();
        paths.sort();
        for p in paths {
            let cle = slug(&p);
            if trouves.contains_key(&cle) {
                continue;
            }
            if let Some(ent) = parse_colors_ini(&p) {
                trouves.insert(cle, ent);
            }
        }
    }
    trouves
}

fn empreinte(detectes: &BTreeMap<String, Value>) -> String {
    // Empreinte déterministe FNV-1a 64-bit hex sur (cle, mtime_ns, size)
    let mut h: u64 = 0xcbf29ce484222325;
    for (cle, val) in detectes {
        let fp = val.get("fichier").and_then(|v| v.as_str()).unwrap_or("");
        let line = match fs::metadata(fp) {
            Ok(m) => format!("{cle}|{}|{}\n", m.mtime_nsec(), m.size()),
            Err(_) => format!("{cle}|absent\n"),
        };
        for b in line.as_bytes() {
            h ^= *b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    }
    format!("{h:016x}")
}

pub fn synchroniser(silencieux: bool) -> Value {
    let sp = style_file();
    let _lock = FileLock::acquire(&sp);
    let detectes = detecter();
    let sig = empreinte(&detectes);

    let cp = cache_file();
    let cache = read_json_value(&cp);
    let old_sig = cache.get("signature").and_then(|v| v.as_str()).unwrap_or("");
    let anciens: HashSet<String> = cache
        .get("themes")
        .and_then(|v| v.as_object())
        .map(|m| m.keys().cloned().collect())
        .unwrap_or_default();

    if old_sig != sig {
        let mut themes_obj = Map::new();
        for (k, v) in &detectes {
            themes_obj.insert(k.clone(), v.clone());
        }
        let d_strs: Vec<String> = dossiers()
            .into_iter()
            .map(|d| d.to_string_lossy().to_string())
            .collect();
        let _ = write_json_atomic(
            &cp,
            &json!({
                "version": 1,
                "signature": sig,
                "dossiers": d_strs,
                "themes": themes_obj,
            }),
            0o644,
        );
    }

    let mut donnees = match read_json_value(&sp) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    let actif = donnees
        .get("active_theme")
        .and_then(|v| v.as_str())
        .unwrap_or("dynamic")
        .to_string();
    let mut modifie = false;

    if let Some(Value::Object(pal)) = donnees.get_mut("palette") {
        let to_del: Vec<String> = pal
            .keys()
            .filter(|k| k.starts_with("kde-") && k.as_str() != actif)
            .cloned()
            .collect();
        for k in to_del {
            pal.remove(&k);
            modifie = true;
        }
    }
    if let Some(Value::Object(noms)) = donnees.get_mut("palette_noms") {
        let to_del: Vec<String> = noms
            .keys()
            .filter(|k| k.starts_with("kde-") && !detectes.contains_key(k.as_str()) && k.as_str() != actif)
            .cloned()
            .collect();
        for k in to_del {
            noms.remove(&k);
            modifie = true;
        }
    }
    if modifie {
        let _ = write_json_atomic(&sp, &Value::Object(donnees), 0o644);
    }

    let ajoutes: Vec<Value> = detectes
        .iter()
        .filter(|(c, _)| !anciens.contains(c.as_str()))
        .map(|(c, e)| json!({ "cle": c, "nom": e.get("nom") }))
        .collect();
    let res = json!({ "ok": true, "ajoutes": ajoutes, "themes": detectes.len() });
    if !silencieux {
        sortir(&res);
    }
    res
}

pub fn activer(cle: &str, silencieux: bool) -> i32 {
    let sp = style_file();
    let _lock = FileLock::acquire(&sp);
    let mut donnees = match read_json_value(&sp) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    let mut modifie = false;

    let has_in_pal = donnees
        .get("palette")
        .and_then(|v| v.as_object())
        .map(|m| m.contains_key(cle))
        .unwrap_or(false);

    if !has_in_pal {
        let cache = read_json_value(&cache_file());
        let entree = cache
            .get("themes")
            .and_then(|v| v.get(cle))
            .cloned()
            .or_else(|| detecter().get(cle).cloned());
        let Some(ent) = entree else {
            eprintln!("thème inconnu : {cle}");
            return 1;
        };
        let pal = donnees
            .entry("palette")
            .or_insert_with(|| Value::Object(Map::new()));
        if let Value::Object(ref mut pm) = pal {
            if let Some(p) = ent.get("palette") {
                pm.insert(cle.into(), p.clone());
            }
        }
        let nom = ent
            .get("nom")
            .and_then(|v| v.as_str())
            .unwrap_or(cle)
            .replace('.', " ")
            .trim()
            .to_string();
        let noms = donnees
            .entry("palette_noms")
            .or_insert_with(|| Value::Object(Map::new()));
        if let Value::Object(ref mut nm) = noms {
            nm.insert(cle.into(), json!(nom));
        }
        modifie = true;
    }

    if let Some(Value::Object(pal)) = donnees.get_mut("palette") {
        let to_del: Vec<String> = pal
            .keys()
            .filter(|k| k.starts_with("kde-") && k.as_str() != cle)
            .cloned()
            .collect();
        for k in to_del {
            pal.remove(&k);
            modifie = true;
        }
    }
    if donnees.get("active_theme").and_then(|v| v.as_str()) != Some(cle) {
        donnees.insert("active_theme".into(), json!(cle));
        modifie = true;
    }
    if modifie {
        let _ = write_json_atomic(&sp, &Value::Object(donnees), 0o644);
    }

    let rofi_gen = core_dir().join("generate_rofi_theme.sh");
    if rofi_gen.is_file() {
        let _ = run_cmd("bash", &[&rofi_gen.to_string_lossy()]);
    }
    if !silencieux {
        sortir(&json!({ "ok": true, "actif": cle }));
    }
    0
}

pub fn run_scan(args: &[String]) -> i32 {
    if args.iter().any(|a| a == "--list") {
        for (cle, ent) in detecter() {
            let nom = ent.get("nom").and_then(|v| v.as_str()).unwrap_or("");
            println!("{cle}\t{nom}");
        }
        return 0;
    }
    if args.iter().any(|a| a == "--json") {
        let det = detecter();
        if let Ok(s) = serde_json::to_string_pretty(&det) {
            println!("{s}");
        }
        return 0;
    }
    if args.iter().any(|a| a == "--signature") {
        println!("{}", empreinte(&detecter()));
        return 0;
    }
    if let Some(pos) = args.iter().position(|a| a == "--import") {
        if let Some(slug_arg) = args.get(pos + 1) {
            return activer(slug_arg, false);
        }
        return 2;
    }
    if args.iter().any(|a| a == "--sync") {
        synchroniser(false);
        return 0;
    }
    0
}

pub fn run_manager(args: &[String]) -> i32 {
    let Some(name) = args.first() else { return 2; };
    activer(name, false)
}

pub fn run_installer(args: &[String]) -> i32 {
    let Some(raw) = args.first() else { return 2; };
    let src = PathBuf::from(raw);
    if !src.is_file() {
        sortir(&json!({ "ok": false, "error": format!("Fichier introuvable : {}", src.display()) }));
        return 1;
    }
    let dest_dir = home_dir().join(".local/share/color-schemes");
    let _ = fs::create_dir_all(&dest_dir);
    let mut installed = Vec::new();
    let lower = src
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    if lower.ends_with(".colors") {
        if let Some(fname) = src.file_name() {
            let dst = dest_dir.join(fname);
            if fs::copy(&src, &dst).is_ok() {
                installed.push(slug(&dst));
            }
        }
    } else {
        let tmp = std::env::temp_dir().join(format!("as-theme-inst-{}", std::process::id()));
        let _ = fs::create_dir_all(&tmp);
        let ok = if lower.ends_with(".zip") {
            run_cmd("unzip", &["-q", &src.to_string_lossy(), "-d", &tmp.to_string_lossy()])
                .map(|o| o.status.success())
                .unwrap_or(false)
        } else {
            run_cmd("tar", &["-xf", &src.to_string_lossy(), "-C", &tmp.to_string_lossy()])
                .map(|o| o.status.success())
                .unwrap_or(false)
        };
        if ok {
            for ent in walkdir::WalkDir::new(&tmp).into_iter().flatten() {
                let p = ent.path();
                if p.is_file() && p.extension().and_then(|s| s.to_str()) == Some("colors") {
                    if let Some(fname) = p.file_name() {
                        let dst = dest_dir.join(fname);
                        if fs::copy(p, &dst).is_ok() {
                            installed.push(slug(&dst));
                        }
                    }
                }
            }
        }
        let _ = fs::remove_dir_all(&tmp);
    }

    if installed.is_empty() {
        sortir(&json!({ "ok": false, "error": "Aucun fichier .colors trouvé" }));
        return 1;
    }
    synchroniser(true);
    if let Some(first) = installed.first() {
        let _ = activer(first, true);
    }
    sortir(&json!({ "ok": true, "installed": installed }))
}
