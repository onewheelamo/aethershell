use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, write_json_atomic};
use crate::common::paths::{config_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

const CATEGORY_LABELS: &[(&str, &str)] = &[
    ("WebBrowser", "Navigateur"),
    ("Development", "Développement"),
    ("Graphics", "Graphisme"),
    ("AudioVideo", "Média"),
    ("Audio", "Audio"),
    ("Video", "Vidéo"),
    ("Office", "Bureautique"),
    ("Network", "Réseau"),
    ("System", "Système"),
    ("Settings", "Réglages"),
    ("Utility", "Utilitaire"),
    ("Game", "Jeu"),
    ("FileManager", "Fichiers"),
    ("TerminalEmulator", "Terminal"),
];

const BRUIT: &[&str] = &[
    "status", "icon", "indicator", "item", "app", "gtk", "qt", "desktop",
    "tray", "menu", "main", "the", "and",
];

fn app_dirs() -> Vec<PathBuf> {
    let h = home_dir();
    vec![
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/usr/local/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        h.join(".local/share/applications"),
        h.join(".local/share/flatpak/exports/share/applications"),
    ]
}

fn read_qt6ct_theme() -> String {
    let conf = config_dir().join("qt6ct/qt6ct.conf");
    if let Ok(txt) = fs::read_to_string(conf) {
        for line in txt.lines() {
            if let Some(v) = line.trim().strip_prefix("icon_theme=") {
                if !v.trim().is_empty() {
                    return v.trim().to_string();
                }
            }
        }
    }
    String::new()
}

fn build_icon_map() -> HashMap<String, String> {
    let active = read_qt6ct_theme();
    let mut themes = Vec::new();
    for t in [
        active.as_str(),
        "Papirus-Dark",
        "Papirus",
        "breeze-dark",
        "breeze",
        "Adwaita",
        "AdwaitaLegacy",
        "hicolor",
    ] {
        if !t.is_empty() && !themes.contains(&t) {
            themes.push(t);
        }
    }
    let h = home_dir();
    let roots = [
        h.join(".local/share/icons"),
        h.join(".local/share/flatpak/exports/share/icons"),
        PathBuf::from("/var/lib/flatpak/exports/share/icons"),
        PathBuf::from("/usr/share/icons"),
    ];
    let size_prio = [
        "scalable", "48x48", "64x64", "32x32", "48", "64", "32",
        "24x24", "24", "22x22", "22", "16x16", "16",
    ];
    let mut icons: HashMap<String, String> = HashMap::new();
    let mut best_score: HashMap<String, usize> = HashMap::new();

    for (t_idx, theme) in themes.iter().enumerate() {
        for root in &roots {
            let tdir = root.join(theme);
            if !tdir.is_dir() {
                continue;
            }
            for ent in WalkDir::new(&tdir).into_iter().flatten() {
                let p = ent.path();
                if !p.is_file() {
                    continue;
                }
                let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_ascii_lowercase();
                if !matches!(ext.as_str(), "svg" | "png" | "xpm") {
                    continue;
                }
                let Some(stem) = p.file_stem().and_then(|s| s.to_str()) else { continue };
                let p_str = p.to_string_lossy();
                let mut sc = t_idx * 100 + 20;
                if p_str.contains("/apps") {
                    sc = sc.saturating_sub(20);
                }
                let sz_sc = size_prio
                    .iter()
                    .position(|sz| p_str.contains(&format!("/{sz}/")))
                    .unwrap_or(30);
                sc += sz_sc;
                if ext == "svg" {
                    sc = sc.saturating_sub(2);
                }
                if best_score.get(stem).map(|&b| sc < b).unwrap_or(true) {
                    best_score.insert(stem.to_string(), sc);
                    icons.insert(stem.to_string(), p_str.to_string());
                }
            }
        }
    }

    if let Ok(entries) = fs::read_dir("/usr/share/pixmaps") {
        for ent in entries.flatten() {
            let p = ent.path();
            if !p.is_file() { continue; }
            let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_ascii_lowercase();
            if matches!(ext.as_str(), "svg" | "png" | "xpm") {
                if let Some(stem) = p.file_stem().and_then(|s| s.to_str()) {
                    icons.entry(stem.to_string()).or_insert_with(|| p.to_string_lossy().to_string());
                }
            }
        }
    }
    icons
}

fn resolve_icon(raw: &str, icon_map: &HashMap<String, String>) -> String {
    let ic = raw.trim();
    if ic.is_empty() {
        return String::new();
    }
    if ic.starts_with('/') && Path::new(ic).is_file() {
        return ic.to_string();
    }
    let stem = Path::new(ic)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(ic);
    icon_map
        .get(ic)
        .or_else(|| icon_map.get(stem))
        .cloned()
        .unwrap_or_else(|| ic.to_string())
}

fn parse_desktop(path: &Path) -> Option<HashMap<String, String>> {
    let txt = fs::read_to_string(path).ok()?;
    let mut fields = HashMap::new();
    let mut in_entry = false;
    for raw in txt.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            fields.entry(k.trim().to_string()).or_insert_with(|| v.trim().to_string());
        }
    }
    Some(fields)
}

pub fn run_index(args: &[String]) -> i32 {
    let quiet = args.iter().any(|a| a == "--quiet");
    let icon_map = build_icon_map();
    let drop_marks = Regex::new(r"\s*%[fFuUdDnNickvm]").unwrap();
    let drop_flatpak = Regex::new(r"(?:^|\s)@@u?\s+@@(?:\s|$)").unwrap();
    let mut seen: BTreeMap<String, (String, Value)> = BTreeMap::new();

    for dir in app_dirs() {
        if !dir.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&dir) else { continue };
        let mut paths: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("desktop"))
            .collect();
        paths.sort();

        for p in paths {
            let Some(fields) = parse_desktop(&p) else { continue };
            if fields.get("NoDisplay").map(|s| s.eq_ignore_ascii_case("true")).unwrap_or(false) {
                continue;
            }
            if fields.get("Hidden").map(|s| s.eq_ignore_ascii_case("true")).unwrap_or(false) {
                continue;
            }
            if fields.get("Type").map(|s| s.as_str()).unwrap_or("Application") != "Application" {
                continue;
            }
            let name = fields
                .get("Name[fr]")
                .or_else(|| fields.get("Name[fr_FR]"))
                .or_else(|| fields.get("Name"))
                .cloned()
                .unwrap_or_default();
            let Some(exec_raw) = fields.get("Exec") else { continue };
            if name.is_empty() || exec_raw.is_empty() {
                continue;
            }
            let key = name.to_ascii_lowercase();
            if seen.contains_key(&key) {
                continue;
            }
            let exec_clean = drop_flatpak
                .replace_all(&drop_marks.replace_all(exec_raw, ""), " ")
                .trim()
                .to_string();
            let comment = fields
                .get("Comment[fr]")
                .or_else(|| fields.get("Comment"))
                .cloned()
                .unwrap_or_default();
            let cats = fields.get("Categories").map(|s| s.as_str()).unwrap_or("");
            let cat_label = CATEGORY_LABELS
                .iter()
                .find(|(needle, _)| cats.contains(needle))
                .map(|(_, lbl)| *lbl)
                .unwrap_or("");
            let desktop = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
            let icon = resolve_icon(fields.get("Icon").map(|s| s.as_str()).unwrap_or(""), &icon_map);

            seen.insert(
                key.clone(),
                (
                    key,
                    json!({
                        "name": name,
                        "exec": exec_clean,
                        "icon": icon,
                        "comment": comment,
                        "category": cat_label,
                        "desktop": desktop,
                    }),
                ),
            );
        }
    }

    let apps: Vec<Value> = seen.into_values().map(|(_, v)| v).collect();
    let target = core_dir().join("app_index.json");
    let _ = write_json_atomic(&target, &apps, 0o644);
    if !quiet {
        println!("app_index: {} applications -> {}", apps.len(), target.display());
    }
    0
}

pub fn jetons(texte: &str) -> HashSet<String> {
    let re = Regex::new(r"[^a-z0-9]+").unwrap();
    let low = texte.to_ascii_lowercase();
    let clean = re.replace_all(&low, " ");
    clean
        .split_whitespace()
        .filter(|j| j.len() > 1 && !BRUIT.contains(j))
        .map(|s| s.to_string())
        .collect()
}

fn compresse(texte: &str) -> String {
    texte
        .to_ascii_lowercase()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect()
}

pub fn couvre(recherche: &HashSet<String>, candidat: &HashSet<String>) -> bool {
    if recherche.is_empty() || candidat.is_empty() {
        return false;
    }
    recherche.iter().all(|j| {
        candidat.iter().any(|c| {
            j == c || (j.len().min(c.len()) >= 3 && (j.contains(c.as_str()) || c.contains(j.as_str())))
        })
    })
}

fn appariement(recherche: &HashSet<String>, candidat: &HashSet<String>) -> Option<usize> {
    if !couvre(recherche, candidat) {
        return None;
    }
    if recherche == candidat {
        return Some(0);
    }
    let mut verbatim = true;
    let mut contenu = false;
    for j in recherche {
        if !candidat.contains(j) {
            verbatim = false;
            if !candidat
                .iter()
                .any(|c| j.len().min(c.len()) >= 4 && (j.contains(c.as_str()) || c.contains(j.as_str())))
            {
                return None;
            }
            contenu = true;
        }
    }
    if verbatim {
        Some(1)
    } else if contenu {
        Some(2)
    } else {
        None
    }
}

fn decrire_classe<'a>(classe: &str, index: &'a [Value]) -> Value {
    let distinctifs: HashSet<String> = jetons(classe).into_iter().filter(|j| j.len() >= 3).collect();
    let mut matched: Option<&'a Value> = None;

    if !distinctifs.is_empty() {
        let mut cands: Vec<(usize, usize, usize, &Value)> = Vec::new();
        for e in index {
            let desk = e.get("desktop").and_then(|v| v.as_str()).unwrap_or("");
            let stem = jetons(desk.strip_suffix(".desktop").unwrap_or(desk));
            if let Some(niv) = appariement(&distinctifs, &stem) {
                let extra = stem.difference(&distinctifs).count();
                cands.push((niv, extra, stem.len(), e));
            }
        }
        cands.sort_by_key(|t| (t.0, t.1, t.2));
        if let Some(first) = cands.first() {
            matched = Some(first.3);
        }
    }

    if matched.is_none() {
        let colle = compresse(classe);
        if colle.len() >= 4 {
            let mut best_len = 0usize;
            for e in index {
                let stem = compresse(e.get("desktop").and_then(|v| v.as_str()).unwrap_or(""));
                let (court, long) = if stem.len() <= colle.len() {
                    (&stem, &colle)
                } else {
                    (&colle, &stem)
                };
                if court.len() >= 4 && long.contains(court.as_str()) && court.len() > best_len {
                    best_len = court.len();
                    matched = Some(e);
                }
            }
        }
    }

    match matched {
        Some(e) => json!({
            "icone": e.get("icon").and_then(|v| v.as_str()).unwrap_or(""),
            "nom": e.get("name").and_then(|v| v.as_str()).unwrap_or(""),
            "desktop": e.get("desktop").and_then(|v| v.as_str()).unwrap_or(""),
        }),
        None => json!({ "icone": "", "nom": "", "desktop": "" }),
    }
}

pub fn run_classes(args: &[String]) -> i32 {
    let mut classes: Vec<String> = Vec::new();
    for a in args {
        if let Some(raw) = a.strip_prefix("--classes=") {
            classes = raw
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        }
    }
    if classes.is_empty() {
        return 2;
    }
    let idx_val = read_json_value(&core_dir().join("app_index.json"));
    let index = idx_val.as_array().map(|a| a.as_slice()).unwrap_or(&[]);
    let mut out = Map::new();
    for c in classes {
        out.insert(c.clone(), decrire_classe(&c, index));
    }
    sortir(&Value::Object(out))
}
