use crate::common::io::{read_json_value, run_cmd};
use crate::common::paths::{core_dir, home_dir};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const DIRS: &[(&str, &str)] = &[
    ("Images", "PICTURES"),
    ("Vidéos", "VIDEOS"),
    ("Documents", "DOCUMENTS"),
    ("Musique", "MUSIC"),
];

const WIDGET_TYPES: &[(&str, &str)] = &[
    ("horloge", "Horloge"),
    ("date", "Date"),
    ("meteo", "Météo"),
    ("combo", "Aperçu du jour"),
    ("musique", "Musique"),
    ("visualiseur", "Visualiseur audio"),
    ("systeme", "Système"),
    ("reseau", "Réseau"),
    ("disques", "Disques"),
    ("homelab", "Homelab"),
    ("hermes", "Hermes"),
    ("usb", "Périphériques"),
    ("todo", "Tâches"),
    ("presse_papiers", "Presse-papiers"),
    ("notes", "Notes rapides"),
    ("sticker", "Sticker / Image"),
    ("deepseek", "DeepSeek"),
    ("ollama", "Ollama Cloud"),
    ("antigravity", "Antigravity"),
    ("comptes", "Quotas IA"),
];

const WRAPPERS: &[&str] = &[
    "env",
    "sh",
    "bash",
    "flatpak",
    "wine",
    "gamemoderun",
    "primusrun",
    "systemd-run",
    "dbus-run-session",
    "setsid",
    "nohup",
];

fn desktop_dirs() -> Vec<PathBuf> {
    let h = home_dir();
    vec![
        PathBuf::from("/usr/share/applications"),
        h.join(".local/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        h.join(".local/share/flatpak/exports/share/applications"),
    ]
}

fn xdg_dir(nom: &str) -> String {
    if let Some(o) = run_cmd("xdg-user-dir", &[nom]) {
        let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
        if !s.is_empty() {
            return s;
        }
    }
    home_dir().to_string_lossy().to_string()
}

fn split_shell_words(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    let mut esc = false;
    for c in s.chars() {
        if esc {
            cur.push(c);
            esc = false;
            continue;
        }
        if c == '\\' && quote != Some('\'') {
            esc = true;
            continue;
        }
        if let Some(q) = quote {
            if c == q {
                quote = None;
            } else {
                cur.push(c);
            }
            continue;
        }
        if c == '"' || c == '\'' {
            quote = Some(c);
            continue;
        }
        if c.is_whitespace() {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
        } else {
            cur.push(c);
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn is_executable(p: &Path) -> bool {
    fs::metadata(p)
        .map(|m| m.is_file() && (m.permissions().mode() & 0o111) != 0)
        .unwrap_or(false)
}

fn binaire_present(commande: &str) -> bool {
    let cmd = commande.trim();
    if cmd.is_empty() {
        return false;
    }
    let parts = split_shell_words(cmd);
    let Some(cible) = parts.first() else {
        return false;
    };
    if cible.starts_with('/') {
        return is_executable(Path::new(cible));
    }
    if let Ok(path_var) = env::var("PATH") {
        for dir in env::split_paths(&path_var) {
            if is_executable(&dir.join(cible)) {
                return true;
            }
        }
    }
    false
}

fn parse_desktop(chemin: &Path) -> Option<HashMap<String, String>> {
    let text = fs::read_to_string(chemin).ok()?;
    let mut champs: HashMap<String, String> = HashMap::new();
    for ligne in text.lines() {
        if ligne.starts_with('[') {
            if !champs.is_empty() {
                break;
            }
            continue;
        }
        let trimmed = ligne.trim_start();
        if trimmed.starts_with('#') || !ligne.contains('=') {
            continue;
        }
        if let Some((cle, val)) = ligne.split_once('=') {
            champs
                .entry(cle.trim().to_string())
                .or_insert_with(|| val.trim().to_string());
        }
    }
    if champs.get("Type").map(|s| s.as_str()).unwrap_or("Application") != "Application" {
        return None;
    }
    if champs
        .get("NoDisplay")
        .map(|s| s.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
        || champs
            .get("Hidden")
            .map(|s| s.eq_ignore_ascii_case("true"))
            .unwrap_or(false)
    {
        return None;
    }
    if champs.get("Name").map(|s| s.is_empty()).unwrap_or(true)
        || champs.get("Exec").map(|s| s.is_empty()).unwrap_or(true)
    {
        return None;
    }
    Some(champs)
}

fn exec_simple(exec_brut: &str) -> String {
    for part in split_shell_words(exec_brut) {
        if part.is_empty() || part.starts_with('-') || part.contains('=') {
            continue;
        }
        let base = Path::new(&part)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("");
        if WRAPPERS.contains(&base) {
            continue;
        }
        return part;
    }
    String::new()
}

fn candidats(categories_voulues: &[&str]) -> Vec<Value> {
    let mut trouves = Vec::new();
    let mut vus = HashSet::new();
    for base in desktop_dirs() {
        let Ok(rd) = fs::read_dir(&base) else {
            continue;
        };
        let mut files: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("desktop"))
            .collect();
        files.sort();
        for chemin in files {
            let Some(champs) = parse_desktop(&chemin) else {
                continue;
            };
            let cats: HashSet<&str> = champs
                .get("Categories")
                .map(|s| s.split(';').map(|c| c.trim()).filter(|c| !c.is_empty()).collect())
                .unwrap_or_default();
            if !categories_voulues.iter().any(|c| cats.contains(c)) {
                continue;
            }
            let Some(exec_raw) = champs.get("Exec") else {
                continue;
            };
            let commande = exec_simple(exec_raw);
            if commande.is_empty() || vus.contains(&commande) || !binaire_present(&commande) {
                continue;
            }
            vus.insert(commande.clone());
            let nom = champs.get("Name").cloned().unwrap_or_default();
            trouves.push(json!({ "nom": nom, "commande": commande }));
        }
    }
    trouves
}

fn kb_layout_from_input_lua() -> String {
    let p = home_dir().join(".config/hypr/input.lua");
    if let Ok(txt) = fs::read_to_string(&p) {
        for line in txt.lines() {
            if let Some(rest) = line.split("kb_layout").nth(1) {
                if let Some(q1) = rest.find('"') {
                    if let Some(q2) = rest[q1 + 1..].find('"') {
                        let val = rest[q1 + 1..q1 + 1 + q2].trim();
                        if !val.is_empty() {
                            return val.to_string();
                        }
                    }
                }
            }
        }
    }
    "fr".to_string()
}

fn run_state() -> i32 {
    let core = core_dir();
    let apps = read_json_value(&core.join("app_vars.json"));
    let style = read_json_value(&core.join("style_vars.json"));
    let widgets_val = read_json_value(&core.join("widgets.json"));

    let dossiers: Vec<Value> = DIRS
        .iter()
        .map(|(nom, cle)| {
            let chemin = xdg_dir(cle);
            let existe = Path::new(&chemin).is_dir();
            json!({ "nom": nom, "xdg": cle, "chemin": chemin, "existe": existe })
        })
        .collect();

    let roles: &[(&str, &[&str], Option<&str>)] = &[
        ("Terminal", &["TerminalEmulator"], None),
        ("Browser", &["WebBrowser"], None),
        ("Files", &["FileManager"], Some("Utility")),
        ("Video", &["Video"], Some("Player")),
        ("Images", &["Viewer"], Some("Graphics")),
        ("Editor", &["TextEditor", "Development"], None),
        ("Music", &["Audio"], None),
    ];

    let mut programmes = Vec::new();
    for (alias, groupes, repli) in roles {
        let commande = apps
            .get(*alias)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let mut liste = Vec::new();
        for g in *groupes {
            liste = candidats(&[*g]);
            if !liste.is_empty() {
                break;
            }
        }
        if liste.is_empty() {
            if let Some(r) = repli {
                liste = candidats(&[*r]);
            }
        }
        liste.truncate(6);
        programmes.push(json!({
            "alias": alias,
            "commande": commande,
            "present": binaire_present(&commande),
            "candidats": liste,
        }));
    }

    let poses: HashSet<String> = widgets_val
        .get("widgets")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|w| w.get("type").and_then(|t| t.as_str()).map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    let widgets: Vec<Value> = WIDGET_TYPES
        .iter()
        .map(|(t, label)| json!({ "type": t, "label": label, "pose": poses.contains(*t) }))
        .collect();

    let barre = if style.get("bar_left").and_then(|v| v.as_bool()) == Some(true) {
        "cote-gauche"
    } else if style.get("bar_right").and_then(|v| v.as_bool()) == Some(true) {
        "cote-droite"
    } else if style.get("bar_bottom").and_then(|v| v.as_bool()) == Some(true) {
        "bas"
    } else {
        "haut"
    };
    let bar_style = style
        .get("bar_style")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("classic");

    println!(
        "{}",
        json!({
            "kb_layout": kb_layout_from_input_lua(),
            "dossiers": dossiers,
            "programmes": programmes,
            "widgets": widgets,
            "barre": barre,
            "bar_style": bar_style,
        })
    );
    0
}

fn exec_self(subcmd: &str, args: &[&str]) -> Result<(), String> {
    let exe = env::current_exe().map_err(|e| e.to_string())?;
    let mut cmd = Command::new(exe);
    cmd.arg(subcmd);
    cmd.args(args);
    let out = cmd.output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        Err(if err.is_empty() {
            format!("code {}", out.status.code().unwrap_or(1))
        } else {
            err
        })
    }
}

fn appliquer_dossier(cle: &str, chemin_raw: &str) -> Result<String, String> {
    let trimmed = chemin_raw.trim();
    let chemin = if let Some(rest) = trimmed.strip_prefix("~/") {
        home_dir().join(rest).to_string_lossy().to_string()
    } else if trimmed == "~" {
        home_dir().to_string_lossy().to_string()
    } else {
        trimmed.to_string()
    };
    if !chemin.starts_with('/') || chemin == "/" {
        return Err("chemin invalide".to_string());
    }
    fs::create_dir_all(&chemin).map_err(|e| e.to_string())?;
    if !Path::new(&chemin).is_dir() {
        return Err("dossier non créé".to_string());
    }
    let out = Command::new("xdg-user-dirs-update")
        .args(["--set", cle, &chemin])
        .output()
        .map_err(|e| e.to_string())?;
    if !out.status.success() {
        let msg = String::from_utf8_lossy(&out.stderr);
        let msg = if msg.trim().is_empty() {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        } else {
            msg.trim().to_string()
        };
        return Err(if msg.is_empty() {
            "échec xdg-user-dirs-update".to_string()
        } else {
            msg.chars().take(120).collect()
        });
    }
    Ok(chemin)
}

fn lire_choix(args: &[String]) -> Result<Value, String> {
    if let Some(chemin) = args.first() {
        let txt = fs::read_to_string(chemin).map_err(|e| e.to_string())?;
        let _ = fs::remove_file(chemin);
        serde_json::from_str(&txt).map_err(|e| e.to_string())
    } else {
        let mut buf = String::new();
        io::stdin()
            .read_to_string(&mut buf)
            .map_err(|e| e.to_string())?;
        serde_json::from_str(&buf).map_err(|e| e.to_string())
    }
}

fn run_apply(args: &[String]) -> i32 {
    let choix = match lire_choix(args) {
        Ok(v) => v,
        Err(e) => {
            println!("{}", json!({ "erreurs": [format!("choix illisibles : {e}")] }));
            return 1;
        }
    };

    let mut erreurs: Vec<String> = Vec::new();
    let mut clavier: Option<String> = None;
    let mut dossiers_out: Vec<Value> = Vec::new();
    let mut programmes_out: Vec<Value> = Vec::new();
    let mut widgets_out: Vec<Value> = Vec::new();
    let mut applets_out: Vec<Value> = Vec::new();
    let mut barre_out: Option<String> = None;
    let mut bar_style_out: Option<String> = None;
    let mut bouton_reglages = false;

    if let Some(layout) = choix.get("kb_layout").and_then(|v| v.as_str()).map(|s| s.trim()).filter(|s| !s.is_empty()) {
        match exec_self("config", &["kb_layout_only", layout]) {
            Ok(()) => clavier = Some(layout.to_string()),
            Err(e) => erreurs.push(format!("clavier : {e}")),
        }
    }

    if let Some(dmap) = choix.get("dossiers").and_then(|v| v.as_object()) {
        for (cle, val) in dmap {
            let ch = val.as_str().unwrap_or("");
            match appliquer_dossier(cle, ch) {
                Ok(detail) => dossiers_out.push(json!({ "xdg": cle, "chemin": detail, "ok": true })),
                Err(detail) => {
                    dossiers_out.push(json!({ "xdg": cle, "chemin": detail, "ok": false }));
                    erreurs.push(format!("dossier {cle} : {detail}"));
                }
            }
        }
    }

    if let Some(pmap) = choix.get("programmes").and_then(|v| v.as_object()) {
        for (alias, val) in pmap {
            let cmd = val.as_str().unwrap_or("").trim();
            if cmd.is_empty() {
                continue;
            }
            match exec_self("config", &["app_var", alias, cmd]) {
                Ok(()) => programmes_out.push(json!({ "alias": alias, "commande": cmd, "ok": true })),
                Err(e) => {
                    programmes_out.push(json!({ "alias": alias, "commande": format!("{cmd} ({e})"), "ok": false }));
                    erreurs.push(format!("programme {alias} : refusé"));
                }
            }
        }
    }

    match exec_self("config", &["style", "show_config_button", "true"]) {
        Ok(()) => bouton_reglages = true,
        Err(e) => erreurs.push(format!("bouton réglages : {e}")),
    }

    if let Some(barre) = choix.get("barre").and_then(|v| v.as_str()).map(|s| s.trim()) {
        if matches!(barre, "haut" | "bas" | "cote-gauche" | "cote-droite") {
            let mut ok = true;
            for (cle, actif) in [
                ("bar_bottom", barre == "bas"),
                ("bar_left", barre == "cote-gauche"),
                ("bar_right", barre == "cote-droite"),
            ] {
                if let Err(e) = exec_self("config", &["style", cle, if actif { "true" } else { "false" }]) {
                    erreurs.push(format!("barre : {e}"));
                    ok = false;
                    break;
                }
            }
            if ok {
                let placement: &[(&str, &[&str])] = &[
                    ("debut", &["workspaces"]),
                    ("milieu", &["horloge"]),
                    ("fin", &["systray", "reseau", "volume", "luminosite", "batterie", "alimentation"]),
                ];
                for (zone, applets) in placement {
                    for (n, applet) in applets.iter().enumerate() {
                        let ile = format!("{barre}:{zone}");
                        let ord = ((n + 1) * 10).to_string();
                        let _ = exec_self("bar-applets", &["activer", applet, &ile]);
                        let _ = exec_self("bar-applets", &["ordonner", applet, &ord]);
                        applets_out.push(json!({ "applet": applet, "ile": ile, "ordre": (n + 1) * 10 }));
                    }
                }
                barre_out = Some(barre.to_string());
            }
        }
    }

    if let Some(bs) = choix.get("bar_style").and_then(|v| v.as_str()).map(|s| s.trim()) {
        if matches!(bs, "classic" | "island") {
            match exec_self("config", &["style", "bar_style", bs]) {
                Ok(()) => bar_style_out = Some(bs.to_string()),
                Err(e) => erreurs.push(format!("style barre : {e}")),
            }
        }
    }

    let widgets_val = read_json_value(&core_dir().join("widgets.json"));
    let mut poses: HashMap<String, String> = HashMap::new();
    if let Some(arr) = widgets_val.get("widgets").and_then(|v| v.as_array()) {
        for w in arr {
            if let (Some(t), Some(id)) = (w.get("type").and_then(|v| v.as_str()), w.get("id").and_then(|v| v.as_str())) {
                poses.entry(t.to_string()).or_insert_with(|| id.to_string());
            }
        }
    }
    let valid_types: HashSet<&str> = WIDGET_TYPES.iter().map(|(t, _)| *t).collect();
    if let Some(arr) = choix.get("widgets_ajouter").and_then(|v| v.as_array()) {
        for v in arr {
            if let Some(nature) = v.as_str() {
                if valid_types.contains(nature) && !poses.contains_key(nature) {
                    match exec_self("config", &["widget_add", nature, "1", "120", "160"]) {
                        Ok(()) => widgets_out.push(json!({ "type": nature, "action": "ajouté" })),
                        Err(e) => erreurs.push(format!("widget {nature} : {e}")),
                    }
                }
            }
        }
    }
    if let Some(arr) = choix.get("widgets_retirer").and_then(|v| v.as_array()) {
        for v in arr {
            if let Some(nature) = v.as_str() {
                if let Some(wid) = poses.get(nature) {
                    match exec_self("config", &["widget_remove", wid]) {
                        Ok(()) => widgets_out.push(json!({ "type": nature, "action": "retiré" })),
                        Err(e) => erreurs.push(format!("widget {nature} : {e}")),
                    }
                }
            }
        }
    }

    if erreurs.is_empty() {
        let _ = exec_self("config", &["complete_first_run"]);
    }

    let mut rapport = Map::new();
    rapport.insert("clavier".into(), json!(clavier));
    rapport.insert("dossiers".into(), Value::Array(dossiers_out));
    rapport.insert("programmes".into(), Value::Array(programmes_out));
    rapport.insert("widgets".into(), Value::Array(widgets_out));
    rapport.insert("applets".into(), Value::Array(applets_out));
    rapport.insert("barre".into(), json!(barre_out));
    if let Some(bs) = bar_style_out {
        rapport.insert("bar_style".into(), json!(bs));
    }
    rapport.insert("bouton_reglages".into(), json!(bouton_reglages));
    rapport.insert("erreurs".into(), json!(erreurs));
    let ok = erreurs.is_empty();
    println!("{}", Value::Object(rapport));
    if ok { 0 } else { 3 }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("state");
    if action == "apply" {
        run_apply(&args[1..])
    } else if action == "state" {
        run_state()
    } else {
        run_state()
    }
}
