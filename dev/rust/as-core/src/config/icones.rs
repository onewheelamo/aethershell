use crate::common::contrat::sortir;
use crate::common::io::run_cmd;
use crate::common::paths::{config_dir, core_dir, home_dir};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

const APERCUS: &[&str] = &[
    "utilities-terminal",
    "firefox",
    "system-file-manager",
    "preferences-system",
    "folder",
    "vlc",
    "code",
];
const IGNORES: &[&str] = &["default", "hicolor", "locolor"];

fn user_icons_dir() -> PathBuf {
    home_dir().join(".local/share/icons")
}

fn sys_icons_dir() -> PathBuf {
    PathBuf::from("/usr/share/icons")
}

fn qt6ct_conf() -> PathBuf {
    config_dir().join("qt6ct/qt6ct.conf")
}

fn gtk3_ini() -> PathBuf {
    config_dir().join("gtk-3.0/settings.ini")
}

fn gtk4_ini() -> PathBuf {
    config_dir().join("gtk-4.0/settings.ini")
}

fn lire_theme_actif() -> String {
    if let Ok(txt) = fs::read_to_string(qt6ct_conf()) {
        for line in txt.lines() {
            if let Some(val) = line.trim().strip_prefix("icon_theme=") {
                if !val.trim().is_empty() {
                    return val.trim().to_string();
                }
            }
        }
    }
    if let Ok(txt) = fs::read_to_string(gtk3_ini()) {
        for line in txt.lines() {
            if let Some(val) = line.trim().strip_prefix("gtk-icon-theme-name=") {
                if !val.trim().is_empty() {
                    return val.trim().to_string();
                }
            }
        }
    }
    String::new()
}

fn parse_index_theme(index_path: &Path) -> Option<String> {
    let parent = index_path.parent()?;
    let mut nom = parent.file_name()?.to_string_lossy().to_string();
    let mut hidden = false;
    let mut has_dirs = false;
    let mut in_main = false;
    let txt = fs::read_to_string(index_path).ok()?;
    for raw in txt.lines() {
        let line = raw.trim();
        if line.starts_with('[') {
            in_main = line == "[Icon Theme]";
            continue;
        }
        if !in_main {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let (k, v) = (k.trim(), v.trim());
            if k == "Name" && !v.is_empty() {
                nom = v.to_string();
            } else if k == "Hidden" && v.eq_ignore_ascii_case("true") {
                hidden = true;
            } else if k == "Directories" && !v.is_empty() {
                has_dirs = true;
            }
        }
    }
    if hidden || !has_dirs {
        return None;
    }
    if parent.join("cursors").is_dir()
        && !["apps", "48x48", "scalable", "places", "actions", "status"]
            .iter()
            .any(|d| parent.join(d).is_dir())
    {
        return None;
    }
    Some(nom)
}

fn trouver_apercus(theme_dir: &Path) -> Vec<String> {
    let mut found: BTreeMap<usize, (u8, String)> = BTreeMap::new();
    for ent in WalkDir::new(theme_dir).max_depth(5).into_iter().flatten() {
        let p = ent.path();
        let ps = p.to_string_lossy();
        if ps.contains("/cursors") || ps.contains("/16") {
            continue;
        }
        if !p.is_file() {
            continue;
        }
        let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_ascii_lowercase();
        if ext != "svg" && ext != "png" {
            continue;
        }
        let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("");
        if let Some(idx) = APERCUS.iter().position(|&c| c == stem) {
            let prio = if ext == "svg" { 0 } else { 1 };
            let replace = found.get(&idx).map(|(ep, _)| prio < *ep).unwrap_or(true);
            if replace {
                found.insert(idx, (prio, ps.to_string()));
            }
        }
    }
    found.into_values().map(|(_, p)| p).take(4).collect()
}

pub fn lister_themes() -> Value {
    let actif = lire_theme_actif();
    let mut vus: BTreeMap<String, (bool, String, Value)> = BTreeMap::new();
    for (is_user, root) in [(true, user_icons_dir()), (false, sys_icons_dir())] {
        if !root.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&root) else { continue };
        for ent in entries.flatten() {
            let p = ent.path();
            if !p.is_dir() { continue; }
            let id = ent.file_name().to_string_lossy().to_string();
            if id.starts_with('.') || IGNORES.contains(&id.as_str()) || vus.contains_key(&id) {
                continue;
            }
            let idx = p.join("index.theme");
            if !idx.is_file() { continue; }
            let Some(nom) = parse_index_theme(&idx) else { continue };
            let apercu = trouver_apercus(&p);
            vus.insert(
                id.clone(),
                (
                    is_user,
                    nom.to_ascii_lowercase(),
                    json!({
                        "id": id,
                        "nom": nom,
                        "chemin": p.to_string_lossy(),
                        "utilisateur": is_user,
                        "apercu": apercu,
                    }),
                ),
            );
        }
    }
    let mut vals: Vec<(bool, bool, String, Value)> = vus
        .into_iter()
        .map(|(id, (is_user, nom_l, v))| (id != actif, !is_user, nom_l, v))
        .collect();
    vals.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)).then_with(|| a.2.cmp(&b.2)));
    let themes: Vec<Value> = vals.into_iter().map(|(_, _, _, v)| v).collect();
    json!({ "ok": true, "actif": actif, "themes": themes })
}

fn maj_ini_key(path: &Path, section: &str, key: &str, value: &str) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut lines: Vec<String> = Vec::new();
    let mut in_sec = false;
    let mut found = false;
    if let Ok(txt) = fs::read_to_string(path) {
        for raw in txt.lines() {
            let s = raw.trim();
            if s.starts_with('[') {
                if in_sec && !found {
                    lines.push(format!("{key}={value}"));
                    found = true;
                }
                in_sec = s == section;
            } else if in_sec && s.starts_with(&format!("{key}=")) {
                lines.push(format!("{key}={value}"));
                found = true;
                continue;
            }
            lines.push(raw.to_string());
        }
    }
    if !found {
        if !in_sec {
            lines.push(section.to_string());
        }
        lines.push(format!("{key}={value}"));
    }
    let _ = fs::write(path, lines.join("\n") + "\n");
}

fn appliquer_theme(theme: &str) -> Value {
    let t = theme.trim();
    if t.is_empty() {
        return json!({ "ok": false, "error": "nom de thème vide" });
    }
    maj_ini_key(&qt6ct_conf(), "[Appearance]", "icon_theme", t);
    maj_ini_key(&gtk3_ini(), "[Settings]", "gtk-icon-theme-name", t);
    maj_ini_key(&gtk4_ini(), "[Settings]", "gtk-icon-theme-name", t);
    let _ = run_cmd("gsettings", &["set", "org.gnome.desktop.interface", "icon-theme", t]);
    let app_idx_py = core_dir().join("app_index.py");
    if app_idx_py.is_file() {
        let _ = run_cmd("python3", &[&app_idx_py.to_string_lossy(), "--quiet"]);
    }
    let mut res = lister_themes();
    if let Value::Object(ref mut m) = res {
        m.insert("message".into(), json!(format!("Thème « {t} » appliqué")));
    }
    res
}

fn installer_pack(archive: &str) -> Value {
    let arch_path = PathBuf::from(archive.trim());
    if !arch_path.is_file() {
        return json!({ "ok": false, "error": format!("Archive introuvable : {}", arch_path.display()) });
    }
    let udir = user_icons_dir();
    let _ = fs::create_dir_all(&udir);
    let tmp = udir.join(format!(".tmp_icon_pack_{}", std::process::id()));
    let _ = fs::create_dir_all(&tmp);
    let lower = arch_path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    let extracted = if lower.ends_with(".zip") {
        run_cmd("unzip", &["-q", &arch_path.to_string_lossy(), "-d", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    } else if lower.ends_with(".tar.zst") {
        run_cmd("tar", &["--zstd", "-xf", &arch_path.to_string_lossy(), "-C", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    } else {
        run_cmd("tar", &["-xf", &arch_path.to_string_lossy(), "-C", &tmp.to_string_lossy()])
            .map(|o| o.status.success())
            .unwrap_or(false)
    };

    let mut installed = Vec::new();
    if extracted {
        let mut candidates: Vec<PathBuf> = Vec::new();
        for ent in WalkDir::new(&tmp).into_iter().flatten() {
            let p = ent.path();
            if p.is_file() && p.file_name().and_then(|s| s.to_str()) == Some("index.theme") {
                if let Some(parent) = p.parent() {
                    if !candidates.iter().any(|c| parent.starts_with(c)) && parse_index_theme(p).is_some() {
                        candidates.push(parent.to_path_buf());
                    }
                }
            }
        }
        for src in candidates {
            if let Some(name) = src.file_name() {
                let dst = udir.join(name);
                if dst.exists() {
                    let _ = fs::remove_dir_all(&dst);
                }
                if fs::rename(&src, &dst).is_ok() {
                    installed.push(name.to_string_lossy().to_string());
                }
            }
        }
    }
    let _ = fs::remove_dir_all(&tmp);
    if installed.is_empty() {
        return json!({ "ok": false, "error": "Aucun thème d'icônes valide (index.theme) trouvé dans l'archive." });
    }
    let mut res = lister_themes();
    if let Value::Object(ref mut m) = res {
        m.insert("message".into(), json!(format!("Installé : {}", installed.join(", "))));
        m.insert("installed".into(), json!(installed));
    }
    res
}

fn supprimer_theme(theme: &str) -> Value {
    let t = theme.trim();
    let udir = user_icons_dir();
    let cible = udir.join(t);
    if t.is_empty() || cible.parent() != Some(udir.as_path()) || !cible.is_dir() {
        return json!({ "ok": false, "error": "Seuls les thèmes installés dans ~/.local/share/icons peuvent être supprimés." });
    }
    let _ = fs::remove_dir_all(&cible);
    let mut res = lister_themes();
    if let Value::Object(ref mut m) = res {
        m.insert("message".into(), json!(format!("Thème « {t} » supprimé")));
    }
    res
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    let res = match action {
        "list" => lister_themes(),
        "apply" if args.len() > 1 => appliquer_theme(&args[1]),
        "install" if args.len() > 1 => installer_pack(&args[1]),
        "remove" if args.len() > 1 => supprimer_theme(&args[1]),
        _ => json!({ "ok": false, "error": "Action inconnue" }),
    };
    sortir(&res)
}
