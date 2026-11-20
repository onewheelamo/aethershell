use crate::common::io::run_cmd;
use crate::common::paths::{cache_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const THEME_DIR: &str = "/usr/share/sddm/themes/sddm-astronaut-theme";
const THEMES_SYS: &str = "/usr/share/sddm/themes";
const SDDM_CONF: &str = "/etc/sddm.conf.d/10-sddm-theme.conf";
const HELPER: &str = "/usr/local/bin/greeter-palette";

fn qylock_cache() -> PathBuf {
    home_dir().join(".local/share/qylock-themes")
}

fn thumbs_dir() -> PathBuf {
    cache_dir().join("quickshell/greeter-thumbs")
}

fn label_for(ident: &str) -> String {
    match ident {
        "palette" => "Palette de la session".into(),
        "astronaut" => "Astronaut".into(),
        "black_hole" => "Trou noir".into(),
        "cyberpunk" => "Cyberpunk".into(),
        "hyprland_kath" => "Hyprland Kath".into(),
        "jake_the_dog" => "Jake the Dog".into(),
        "japanese_aesthetic" => "Esthétique japonaise".into(),
        "pixel_sakura" => "Pixel Sakura".into(),
        "pixel_sakura_static" => "Pixel Sakura (statique)".into(),
        "post-apocalyptic_hacker" => "Hacker post-apo".into(),
        "purple_leaves" => "Feuilles pourpres".into(),
        _ => {
            let s = ident.replace('_', " ");
            let mut chars = s.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            }
        }
    }
}

fn qylock_label(ident: &str) -> String {
    let s = ident.replace(['-', '_'], " ");
    let t = s.trim();
    let mut chars = t.chars();
    match chars.next() {
        None => String::new(),
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

fn fail(msg: &str, code: i32) -> i32 {
    println!("{}", json!({ "ok": false, "error": msg }));
    code
}

fn current_theme() -> String {
    if let Ok(txt) = fs::read_to_string(SDDM_CONF) {
        for line in txt.lines() {
            if let Some(rest) = line.strip_prefix("Current=") {
                return rest.trim().to_string();
            }
        }
    }
    "sddm-astronaut-theme".to_string()
}

fn active_id() -> String {
    let meta = Path::new(THEME_DIR).join("metadata.desktop");
    if let Ok(txt) = fs::read_to_string(meta) {
        for line in txt.lines() {
            if let Some(rest) = line.strip_prefix("ConfigFile=") {
                return Path::new(rest.trim())
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .to_string();
            }
        }
    }
    String::new()
}

fn qylock_installed() -> BTreeMap<String, PathBuf> {
    let mut out = BTreeMap::new();
    let sys = Path::new(THEMES_SYS);
    if let Ok(rd) = fs::read_dir(sys) {
        for ent in rd.flatten() {
            let d = ent.path();
            if !d.is_dir() || d == Path::new(THEME_DIR) || !d.join("Main.qml").exists() {
                continue;
            }
            let meta = d.join("metadata.desktop");
            if let Ok(txt) = fs::read_to_string(meta) {
                if txt.contains("Author=Darkkal44") {
                    if let Some(name) = d.file_name().and_then(|s| s.to_str()) {
                        out.insert(name.to_string(), d);
                    }
                }
            }
        }
    }
    out
}

fn qylock_cached() -> BTreeMap<String, (PathBuf, bool)> {
    let mut out = BTreeMap::new();
    let qc = qylock_cache();
    if let Ok(rd) = fs::read_dir(&qc) {
        let mut roots: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
        roots.sort();
        for root in roots {
            let root_name = root
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            let mut cands = Vec::new();
            if root.join("metadata.desktop").exists() {
                cands.push(root.clone());
            }
            if let Ok(sub_rd) = fs::read_dir(&root) {
                let mut subs: Vec<PathBuf> = sub_rd
                    .flatten()
                    .map(|e| e.path())
                    .filter(|p| p.is_dir() && p.join("metadata.desktop").exists())
                    .collect();
                subs.sort();
                cands.extend(subs);
            }
            for src in cands {
                let name = if src == root {
                    root_name.clone()
                } else {
                    let sub_name = src.file_name().and_then(|s| s.to_str()).unwrap_or("");
                    format!("{}-{}", root_name, sub_name)
                };
                let installed = Path::new(THEMES_SYS).join(&name).exists();
                out.insert(name, (src, installed));
            }
        }
    }
    out
}

fn presets() -> Vec<Value> {
    let cur = current_theme();
    let act = active_id();
    let td = thumbs_dir();
    let mut out = Vec::new();

    if let Ok(rd) = fs::read_dir(Path::new(THEME_DIR).join("Themes")) {
        let mut confs: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("conf"))
            .collect();
        confs.sort();
        for conf in confs {
            let ident = conf
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            let thumb = td.join(format!("{}.png", ident));
            out.push(json!({
                "id": ident,
                "name": label_for(&ident),
                "thumb": if thumb.exists() { thumb.to_string_lossy().to_string() } else { String::new() },
                "active": cur == "sddm-astronaut-theme" && ident == act,
                "kind": "astronaut",
                "installed": true,
            }));
        }
    }

    let mut merged: BTreeMap<String, (PathBuf, bool)> = qylock_cached();
    for (ident, d) in qylock_installed() {
        merged.entry(ident).or_insert((d, true));
    }
    for (ident, (_, installed)) in merged {
        let thumb = td.join(format!("{}.png", ident));
        let name = if installed {
            qylock_label(&ident)
        } else {
            format!("{} (à installer)", qylock_label(&ident))
        };
        out.push(json!({
            "id": ident,
            "name": name,
            "thumb": if thumb.exists() { thumb.to_string_lossy().to_string() } else { String::new() },
            "active": installed && ident == cur,
            "kind": "qylock",
            "installed": installed,
        }));
    }

    out.sort_by(|a, b| {
        let aid = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let bid = b.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let ak = a.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        let bk = b.get("kind").and_then(|v| v.as_str()).unwrap_or("");
        let an = a
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        let bn = b
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_ascii_lowercase();
        (aid != "palette", ak != "astronaut", an)
            .cmp(&(bid != "palette", bk != "astronaut", bn))
    });
    out
}

const PREVIEW_ESCAPE: &str = r##"
    // Aperçu du panneau : ne fait pas partie du thème installé.
    Rectangle {
        id: previewHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: previewHintLabel.implicitWidth + 28
        height: previewHintLabel.implicitHeight + 14
        radius: 8
        color: "#e6050b12"
        border.width: 1
        border.color: "#40f0f5ff"

        Text {
            id: previewHintLabel
            anchors.centerIn: parent
            text: "Aperçu — la connexion est désactivée · Échap pour fermer"
            color: "#f0f5ff"
            font.pixelSize: 13
        }
    }
"##;

fn inject_preview_escape(theme_dir: &Path) -> bool {
    let main = theme_dir.join("Main.qml");
    let Ok(text) = fs::read_to_string(&main) else {
        return false;
    };
    let end = text.trim_end();
    if !end.ends_with('}') {
        return false;
    }
    let patched = format!("{}{}}}\n", &end[..end.len() - 1], PREVIEW_ESCAPE);
    if patched.matches('{').count() != patched.matches('}').count() {
        return false;
    }
    fs::write(&main, patched).is_ok()
}

fn get_sddm_dir() -> PathBuf {
    if let Some(parent) = core_dir().parent() {
        let cand = parent.join("sddm");
        if cand.is_dir() && cand.join("install.sh").exists() {
            return cand;
        }
    }
    let cand2 = home_dir().join("dev/quickshell_todo/dev/sddm");
    if cand2.is_dir() && cand2.join("install.sh").exists() {
        return cand2;
    }
    home_dir().join(".config/quickshell/sddm")
}

fn preview(ident: &str) -> i32 {
    let conf = Path::new(THEME_DIR)
        .join("Themes")
        .join(format!("{}.conf", ident));
    let qylock = qylock_cached();
    let installed = qylock_installed();
    let src = installed
        .get(ident)
        .cloned()
        .or_else(|| qylock.get(ident).map(|(p, _)| p.clone()));
    if src.is_none() && !conf.exists() {
        return fail(&format!("configuration inconnue : {}", ident), 1);
    }

    let tmp = PathBuf::from(format!("/var/tmp/greeter-preview-{}", std::process::id()));
    let _ = fs::create_dir_all(&tmp);
    let tmp_str = tmp.to_string_lossy().to_string();

    if let Some(s) = src {
        let src_dot = format!("{}/.", s.display());
        let _ = run_cmd("cp", &["-a", "--reflink=auto", &src_dot, &tmp_str]);
    } else {
        let theme_dot = format!("{}/.", THEME_DIR);
        let _ = run_cmd("cp", &["-a", "--reflink=auto", &theme_dot, &tmp_str]);
        let meta = tmp.join("metadata.desktop");
        if let Ok(txt) = fs::read_to_string(&meta) {
            let lines: Vec<String> = txt
                .lines()
                .map(|l| {
                    if l.starts_with("ConfigFile=") {
                        format!("ConfigFile=Themes/{}.conf", ident)
                    } else {
                        l.to_string()
                    }
                })
                .collect();
            let _ = fs::write(&meta, lines.join("\n") + "\n");
        }
    }
    inject_preview_escape(&tmp);

    let wrapper = core_dir().join("greeter_preview.sh");
    let _ = Command::new("sh")
        .args([wrapper.to_string_lossy().as_ref(), "start", &tmp_str, "45"])
        .env("QT_QPA_PLATFORM", "wayland")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    println!("{}", json!({ "ok": true, "preview": ident }));
    0
}

fn helper(args: &[&str]) -> (bool, String) {
    let mut full = vec![HELPER];
    full.extend_from_slice(args);
    match run_cmd("pkexec", &full) {
        Some(o) => {
            let out = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            )
            .trim()
            .to_string();
            (o.status.success(), out)
        }
        None => (false, "pkexec introuvable".to_string()),
    }
}

fn apply(ident: &str) -> i32 {
    if ident != "sddm-astronaut-theme"
        && Path::new(THEMES_SYS)
            .join(ident)
            .join("metadata.desktop")
            .exists()
    {
        let (ok, out) = helper(&["apply", ident]);
        if !ok {
            return fail(
                &format!("sélection refusée : {}", out.chars().take(200).collect::<String>()),
                1,
            );
        }
        println!("{}", json!({ "ok": true, "applied": ident, "message": out }));
        return 0;
    }
    if qylock_cached().contains_key(ident) {
        return fail(
            &format!("thème récupéré mais pas installé : bash dev/sddm/install.sh --qylock {}", ident),
            1,
        );
    }
    if !Path::new(THEME_DIR)
        .join("Themes")
        .join(format!("{}.conf", ident))
        .exists()
    {
        return fail(&format!("configuration inconnue : {}", ident), 1);
    }
    if ident == "palette" {
        let sddm = get_sddm_dir();
        let gen_py = sddm.join("generate.py");
        if let Some(o) = run_cmd("python3", &[&gen_py.to_string_lossy()]) {
            if !o.status.success() {
                let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
                return fail(
                    &format!("génération impossible : {}", err.chars().take(200).collect::<String>()),
                    1,
                );
            }
        }
        let pal_conf = sddm.join("out/Themes/palette.conf");
        let wp = sddm.join("out/Backgrounds/wallpaper.png");
        let (ok, out) = helper(&[
            "set-palette",
            &pal_conf.to_string_lossy(),
            &wp.to_string_lossy(),
        ]);
        if !ok {
            return fail(
                &format!(
                    "installation de la palette refusée : {}",
                    out.chars().take(200).collect::<String>()
                ),
                1,
            );
        }
    }
    let (ok, out) = helper(&["apply", ident]);
    if !ok {
        return fail(
            &format!("sélection refusée : {}", out.chars().take(200).collect::<String>()),
            1,
        );
    }
    println!("{}", json!({ "ok": true, "applied": ident, "message": out }));
    0
}

fn sources(ids: &[String]) -> i32 {
    let mut rows: Vec<(String, String, &'static str)> = Vec::new();
    if let Ok(rd) = fs::read_dir(Path::new(THEME_DIR).join("Themes")) {
        let mut confs: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("conf"))
            .collect();
        confs.sort();
        for c in confs {
            if let Some(stem) = c.file_stem().and_then(|s| s.to_str()) {
                rows.push((stem.to_string(), THEME_DIR.to_string(), "astronaut"));
            }
        }
    }
    let mut merged: BTreeMap<String, String> = BTreeMap::new();
    for (ident, (src, _)) in qylock_cached() {
        merged.insert(ident, src.to_string_lossy().to_string());
    }
    for (ident, d) in qylock_installed() {
        merged
            .entry(ident)
            .or_insert_with(|| d.to_string_lossy().to_string());
    }
    for (ident, p) in merged {
        rows.push((ident, p, "qylock"));
    }
    for (ident, path, kind) in rows {
        if ids.is_empty() || ids.iter().any(|x| x == &ident) {
            println!("{}\t{}\t{}", ident, path, kind);
        }
    }
    0
}

fn thumbnails(ids: &[String]) -> i32 {
    let script = get_sddm_dir().join("thumbnails.sh");
    if !script.exists() {
        return fail("thumbnails.sh absent", 1);
    }
    let script_s = script.to_string_lossy().to_string();
    let mut cmd_args = vec![script_s.as_str()];
    let refs: Vec<&str> = ids.iter().map(|s| s.as_str()).collect();
    cmd_args.extend(refs);
    match run_cmd("bash", &cmd_args) {
        Some(o) => {
            let msg = format!(
                "{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            )
            .trim()
            .to_string();
            let tail: String = msg
                .chars()
                .rev()
                .take(400)
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            println!("{}", json!({ "ok": o.status.success(), "ids": ids, "message": tail }));
            0
        }
        None => fail("échec thumbnails.sh", 1),
    }
}

fn qylock_pkg_name(ident: &str) -> String {
    let qc = qylock_cache();
    if qc.join(ident).is_dir() {
        return ident.to_string();
    }
    if let Ok(rd) = fs::read_dir(&qc) {
        for ent in rd.flatten() {
            let root = ent.path();
            if !root.is_dir() {
                continue;
            }
            let rname = root.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if let Ok(sub_rd) = fs::read_dir(&root) {
                for sub in sub_rd.flatten() {
                    let sp = sub.path();
                    if sp.is_dir() {
                        let sname = sp.file_name().and_then(|s| s.to_str()).unwrap_or("");
                        if format!("{}-{}", rname, sname) == ident {
                            return rname.to_string();
                        }
                    }
                }
            }
        }
        if let Some(base) = ident.split('-').next() {
            if qc.join(base).is_dir() {
                return base.to_string();
            }
        }
    }
    ident.to_string()
}

fn install_qylock(ident: &str) -> i32 {
    let pkg = qylock_pkg_name(ident);
    let src = qylock_cache().join(&pkg);
    if !src.is_dir() {
        return fail(&format!("thème non trouvé dans le cache local : {}", pkg), 1);
    }
    let sddm_dir = get_sddm_dir();
    let install_sh = sddm_dir.join("install.sh");
    if !install_sh.exists() {
        return fail(&format!("script install.sh introuvable dans {}", sddm_dir.display()), 1);
    }
    match run_cmd("bash", &[&install_sh.to_string_lossy(), "--qylock", &pkg]) {
        Some(o) if o.status.success() => {
            let so = String::from_utf8_lossy(&o.stdout).trim().to_string();
            let tail: String = so
                .chars()
                .rev()
                .take(300)
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            println!(
                "{}",
                json!({ "ok": true, "installed": ident, "pkg": pkg, "message": tail })
            );
            0
        }
        Some(o) => {
            let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
            let out = String::from_utf8_lossy(&o.stdout).trim().to_string();
            let msg = if !err.is_empty() {
                err
            } else if !out.is_empty() {
                out
            } else {
                "échec de l'installation".to_string()
            };
            fail(
                &format!(
                    "installation refusée ou échouée : {}",
                    msg.chars().take(300).collect::<String>()
                ),
                1,
            )
        }
        None => fail("bash introuvable", 1),
    }
}

fn shlex_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

fn uninstall_themes(ids: &[String]) -> i32 {
    let re = Regex::new(r"^[A-Za-z0-9._-]+$").unwrap();
    let mauvais: Vec<&str> = ids
        .iter()
        .map(|s| s.as_str())
        .filter(|s| !re.is_match(s))
        .collect();
    if !mauvais.is_empty() {
        return fail(
            &format!(
                "nom(s) de thème refusé(s) : {}",
                mauvais.into_iter().take(8).collect::<Vec<_>>().join(", ")
            ),
            1,
        );
    }
    let cur = current_theme();
    let installed = qylock_installed();
    let to_remove: Vec<String> = ids
        .iter()
        .filter(|id| {
            !id.is_empty()
                && id.as_str() != "sddm-astronaut-theme"
                && id.as_str() != cur
                && installed.contains_key(id.as_str())
        })
        .cloned()
        .collect();
    if to_remove.is_empty() {
        return fail(
            "aucun thème valide à désinstaller (le thème actif et astronaut ne peuvent pas être supprimés)",
            1,
        );
    }

    let mut hargs = vec!["uninstall"];
    let refs: Vec<&str> = to_remove.iter().map(|s| s.as_str()).collect();
    hargs.extend(refs);
    let (ok, out) = helper(&hargs);
    if ok {
        println!(
            "{}",
            json!({ "ok": true, "uninstalled": to_remove, "message": out })
        );
        return 0;
    }

    let sddm_dir = get_sddm_dir();
    let helper_src = sddm_dir.join("greeter-palette");
    let mut script_lines = vec!["#!/bin/bash".to_string(), "set -euo pipefail".to_string()];
    if helper_src.exists() {
        script_lines.push(format!(
            "install -Dm755 {} /usr/local/bin/greeter-palette",
            shlex_quote(&helper_src.to_string_lossy())
        ));
    }
    for ident in &to_remove {
        let t = Path::new(THEMES_SYS).join(ident);
        script_lines.push(format!("rm -rf {}", shlex_quote(&t.to_string_lossy())));
    }
    let tmp_script = env::temp_dir().join(format!("sddm-uninstall-{}.sh", std::process::id()));
    if fs::write(&tmp_script, script_lines.join("\n") + "\n").is_err() {
        return fail("impossible d'écrire le script temporaire", 1);
    }
    let _ = fs::set_permissions(&tmp_script, fs::Permissions::from_mode(0o755));
    let res = run_cmd("pkexec", &["bash", &tmp_script.to_string_lossy()]);
    let _ = fs::remove_file(&tmp_script);

    match res {
        Some(o) if o.status.success() => {
            println!(
                "{}",
                json!({
                    "ok": true,
                    "uninstalled": to_remove,
                    "message": format!("{} thème(s) désinstallé(s)", to_remove.len()),
                })
            );
            0
        }
        Some(o) => {
            let err = String::from_utf8_lossy(&o.stderr).trim().to_string();
            let out = String::from_utf8_lossy(&o.stdout).trim().to_string();
            let msg = if !err.is_empty() {
                err
            } else if !out.is_empty() {
                out
            } else {
                "opération annulée".to_string()
            };
            fail(
                &format!(
                    "désinstallation annulée ou échouée : {}",
                    msg.chars().take(200).collect::<String>()
                ),
                1,
            )
        }
        None => fail("pkexec introuvable", 1),
    }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    match action {
        "list" => {
            let cur = current_theme();
            let active = if cur == "sddm-astronaut-theme" {
                active_id()
            } else {
                cur.clone()
            };
            println!(
                "{}",
                json!({
                    "ok": true,
                    "theme": THEME_DIR,
                    "active": active,
                    "current": cur,
                    "thumb_dir": thumbs_dir().to_string_lossy(),
                    "helper": Path::new(HELPER).exists(),
                    "presets": presets(),
                })
            );
            0
        }
        "preview" if args.len() > 1 => preview(&args[1]),
        "apply" if args.len() > 1 => apply(&args[1]),
        "install" if args.len() > 1 => install_qylock(&args[1]),
        "uninstall" if args.len() > 1 => uninstall_themes(&args[1..]),
        "refresh" => apply("palette"),
        "thumbnails" => thumbnails(&args[1..]),
        "sources" => sources(&args[1..]),
        _ => fail(&format!("action inconnue : {}", action), 1),
    }
}
