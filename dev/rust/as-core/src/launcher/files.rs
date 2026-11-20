use crate::common::contrat::sortir;
use crate::common::paths::home_dir;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

pub fn lister(dossier: &str, extensions: Option<&[String]>) -> Value {
    let expanded = if dossier == "~" {
        home_dir()
    } else if let Some(rest) = dossier.strip_prefix("~/") {
        home_dir().join(rest)
    } else {
        PathBuf::from(dossier)
    };

    let mut base = if expanded.exists() {
        expanded
    } else if expanded.parent().map(|p| p.exists()).unwrap_or(false) {
        expanded.parent().unwrap().to_path_buf()
    } else {
        home_dir()
    };

    if !base.is_dir() {
        base = base.parent().map(|p| p.to_path_buf()).unwrap_or_else(home_dir);
    }

    let exts: Option<HashSet<String>> = extensions.and_then(|list| {
        let set: HashSet<String> = list
            .iter()
            .map(|e| e.trim().trim_start_matches('.').to_ascii_lowercase())
            .filter(|e| !e.is_empty())
            .collect();
        if set.is_empty() { None } else { Some(set) }
    });

    let Ok(entries) = fs::read_dir(&base) else {
        return json!({
            "chemin": base.to_string_lossy(),
            "erreur": "Impossible de lire le dossier",
            "entrees": [],
        });
    };

    let mut items: Vec<(String, PathBuf)> = entries
        .flatten()
        .filter_map(|e| {
            let nom = e.file_name().to_string_lossy().to_string();
            if nom.starts_with('.') {
                return None;
            }
            Some((nom, e.path()))
        })
        .collect();
    items.sort_by(|a, b| a.0.to_ascii_lowercase().cmp(&b.0.to_ascii_lowercase()));

    let mut dossiers = Vec::new();
    let mut fichiers = Vec::new();
    for (nom, p) in items {
        if p.is_dir() {
            dossiers.push(json!({
                "nom": nom,
                "chemin": p.to_string_lossy(),
                "est_dossier": true,
            }));
        } else if p.is_file() {
            let ok = match &exts {
                None => true,
                Some(set) => p
                    .extension()
                    .and_then(|s| s.to_str())
                    .map(|e| set.contains(&e.to_ascii_lowercase()))
                    .unwrap_or(false),
            };
            if ok {
                fichiers.push(json!({
                    "nom": nom,
                    "chemin": p.to_string_lossy(),
                    "est_dossier": false,
                }));
            }
        }
    }
    dossiers.extend(fichiers);
    json!({
        "chemin": base.to_string_lossy(),
        "erreur": "",
        "entrees": dossiers,
    })
}

pub fn run(args: &[String]) -> i32 {
    let Some(dossier) = args.first() else {
        eprintln!("usage : as-core lister-fichiers <chemin> [ext1 ext2 ...]");
        return 2;
    };
    let exts = if args.len() > 1 { Some(&args[1..]) } else { None };
    sortir(&lister(dossier, exts))
}
