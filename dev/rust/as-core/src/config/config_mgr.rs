use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd, write_json_atomic, write_private_json};
use crate::common::paths::{cache_dir, core_dir, home_dir};
use crate::config::config_hypr::{
    apply_shell_blur, get_binds_list, get_hostname, get_hypr_gaps, get_hypr_rounding,
    get_hypr_rounding_power, get_kb_layout, get_monitors_info, hypr_dir, hyprctl_silent,
    is_laptop_system, lua_ident, remove_keybind, set_kb_layout, set_keybind, set_monitor_mode,
    set_monitor_profile, set_primary_monitor, set_screen_rotation, sync_autostart_lua,
    sync_programs_lua, update_hypr_gaps, workspace_keys_for_layout,
};
use crate::config::lien_systeme;
use crate::daemon::system_service;
use crate::services::llm;
use regex::Regex;
use serde_json::{json, Map, Value};
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::PathBuf;
use std::process::Command;

const DEFAULT_ILOT_ORDER: &[&str] = &[
    "horloge", "workspaces", "systray", "nuit", "luminosite", "batterie", "minimise",
    "volume", "reseau", "notifications", "maj", "todo", "meteo",
    "presse-papiers", "usb", "systeme", "comptes",
];

const WIDGET_TYPES: &[&str] = &[
    "horloge", "date", "meteo", "combo", "musique", "visualiseur", "systeme",
    "reseau", "disques", "homelab", "hermes", "usb", "todo",
    "presse_papiers", "notes", "sticker",
    "deepseek", "ollama", "antigravity", "comptes",
];

const COLOR_KEYS: &[&str] = &[
    "bg", "fg", "accent", "accent_muted", "surface", "surface_variant", "error", "warn", "info", "success",
];

const MATUGEN_SCHEMES: &[&str] = &[
    "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive",
    "scheme-neutral", "scheme-monochrome", "scheme-fruit-salad",
    "scheme-content", "scheme-fidelity", "scheme-rainbow",
];

const LAUNCHER_POSITIONS: &[&str] = &[
    "bas-centre", "haut-centre", "bas-gauche", "bas-droit", "haut-gauche", "haut-droit",
];

fn style_path() -> PathBuf { core_dir().join("style_vars.json") }
fn secrets_path() -> PathBuf { core_dir().join("secrets.json") }
fn widgets_path() -> PathBuf { core_dir().join("widgets.json") }
fn app_vars_path() -> PathBuf { core_dir().join("app_vars.json") }
fn homelab_path() -> PathBuf { core_dir().join("homelab.json") }
fn todo_path() -> PathBuf { core_dir().join("todo.json") }
fn todo_focus_path() -> PathBuf { cache_dir().join("todo-focus.json") }
fn notif_targets_path() -> PathBuf { core_dir().join("notif_targets.json") }
fn autostart_path() -> PathBuf { core_dir().join("autostart.json") }

fn read_map(path: &PathBuf) -> Map<String, Value> {
    match read_json_value(path) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

fn is_true(s: &str) -> bool {
    matches!(s.trim().to_ascii_lowercase().as_str(), "true" | "1" | "yes" | "oui" | "on")
}

fn load_widgets_vec() -> Vec<Value> {
    let v = read_json_value(&widgets_path());
    v.get("widgets")
        .and_then(|x| x.as_array())
        .map(|arr| {
            arr.iter()
                .filter(|w| w.get("type").and_then(|t| t.as_str()).map(|s| !s.is_empty()).unwrap_or(false))
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

fn save_widgets_vec(items: &[Value]) {
    let _ = write_json_atomic(&widgets_path(), &json!({ "widgets": items }), 0o644);
    let style = read_map(&style_path());
    apply_shell_blur(&style, items);
}

fn widget_add(wtype: &str, workspace: i64, x: i64, y: i64) -> String {
    if !WIDGET_TYPES.contains(&wtype) {
        return String::new();
    }
    let mut items = load_widgets_vec();
    for w in &items {
        if w.get("type").and_then(|v| v.as_str()) == Some(wtype) {
            return w.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string();
        }
    }
    let mut wid = format!("{wtype}-{}", items.len() + 1);
    while items.iter().any(|w| w.get("id").and_then(|v| v.as_str()) == Some(wid.as_str())) {
        wid.push('x');
    }
    items.push(json!({
        "id": wid, "type": wtype, "workspace": workspace,
        "x": x, "y": y, "enabled": true,
        "opacity": 0.35, "blur": true, "border": true, "options": {},
    }));
    save_widgets_vec(&items);
    wid
}

fn widget_update<F: FnOnce(&mut Map<String, Value>)>(wid: &str, f: F) {
    let mut items = load_widgets_vec();
    for w in &mut items {
        if w.get("id").and_then(|v| v.as_str()) == Some(wid) {
            if let Some(m) = w.as_object_mut() {
                f(m);
                save_widgets_vec(&items);
                return;
            }
        }
    }
}

fn widget_set(wid: &str, key: &str, value: &str) {
    widget_update(wid, |w| match key {
        "x" | "y" | "workspace" => {
            let iv = value.parse::<f64>().unwrap_or(0.0) as i64;
            w.insert(key.into(), json!(iv));
            if key == "workspace" {
                w.insert("workspaces".into(), json!([iv]));
            }
        }
        "enabled" | "blur" | "border" => {
            w.insert(key.into(), json!(is_true(value)));
        }
        "opacity" => {
            let fv = ((value.parse::<f64>().unwrap_or(0.35).clamp(0.0, 1.0)) * 100.0).round() / 100.0;
            w.insert("opacity".into(), json!(fv));
        }
        "type" if WIDGET_TYPES.contains(&value) => {
            w.insert("type".into(), json!(value));
        }
        "id" => {
            w.insert("id".into(), json!(value));
        }
        "style" => {
            let s = if value.trim().eq_ignore_ascii_case("transparent") { "transparent" } else { "glass" };
            w.insert("style".into(), json!(s));
        }
        _ => {
            let parsed = if value.starts_with('[') || value.starts_with('{') {
                serde_json::from_str::<Value>(value).unwrap_or_else(|_| json!(value))
            } else {
                json!(value)
            };
            let mut opts = w.get("options").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            opts.insert(key.into(), parsed);
            w.insert("options".into(), Value::Object(opts));
        }
    });
}

fn widget_workspaces(wid: &str, spec: &str) {
    widget_update(wid, |w| {
        let mut nums: Vec<i64> = spec
            .replace(';', ",")
            .split(',')
            .filter_map(|p| p.trim().parse::<i64>().ok())
            .collect();
        if nums.is_empty() || nums.contains(&0) {
            w.insert("workspaces".into(), json!([0]));
            w.insert("workspace".into(), json!(0));
        } else {
            nums.sort();
            nums.dedup();
            w.insert("workspace".into(), json!(nums[0]));
            w.insert("workspaces".into(), json!(nums));
        }
    });
}

fn normalize_dir_var(raw: &str) -> Option<String> {
    let t = raw.trim();
    if t.is_empty() {
        return None;
    }
    let mut clean = if t == "~" {
        "$HOME/".to_string()
    } else if let Some(rest) = t.strip_prefix("~/") {
        format!("$HOME/{rest}")
    } else {
        t.to_string()
    };
    if !clean.ends_with('/') {
        clean.push('/');
    }
    Some(clean)
}

fn update_style_var(key: &str, value: &str) {
    if key == "wallpaper_dir" {
        if let Some(clean) = normalize_dir_var(value) {
            let mut data = read_map(&style_path());
            data.insert("wallpaper_dir".into(), json!(clean));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            for cfg_p in [
                core_dir().parent().unwrap_or(&core_dir()).join("hyprquickpaper/config.json"),
                home_dir().join(".config/quickshell/hyprquickpaper/config.json"),
            ] {
                if cfg_p.is_file() {
                    let mut cfg = read_map(&cfg_p);
                    cfg.insert("wallpaper_path".into(), json!(clean));
                    let _ = write_json_atomic(&cfg_p, &Value::Object(cfg), 0o644);
                }
            }
        }
        return;
    }
    if key == "screenshots_dir" {
        if let Some(clean) = normalize_dir_var(value) {
            let mut data = read_map(&style_path());
            data.insert("screenshots_dir".into(), json!(clean));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
        }
        return;
    }

    let mut data = read_map(&style_path());
    let mut blur_changed = false;
    let fval = value.replace(',', ".").parse::<f64>().unwrap_or(0.0);

    match key {
        "do_not_disturb" | "bar_border" | "bar_gaps_transparent" | "launch_history"
        | "blur_enabled" | "depth_wallpaper" | "wallpaper_slide" | "depth_mask"
        | "panel_accordion" | "widgets_locked" | "first_run_completed"
        | "ilot_projets_actif" | "ilot_coins_groupes" | "bar_bottom" | "bar_left"
        | "bar_right" | "show_config_button" | "maj_seulement_si_dispo" => {
            data.insert(key.into(), json!(is_true(value)));
        }
        "global_radius" | "selecteur_radius" => {
            data.insert(key.into(), json!((fval as i64).clamp(0, 30)));
        }
        "hypr_rounding" => {
            let iv = (fval as i64).clamp(0, 35);
            data.insert(key.into(), json!(iv));
            let gp = hypr_dir().join("general.lua");
            if let Ok(txt) = fs::read_to_string(&gp) {
                let re = Regex::new(r"(\brounding\s*=\s*)\d+").unwrap();
                let _ = fs::write(&gp, re.replace_all(&txt, format!("${{1}}{iv}")).as_ref());
            }
            hyprctl_silent(&["eval", &format!("hl.config({{ decoration = {{ rounding = {iv} }} }})")]);
        }
        "hypr_rounding_power" => {
            let iv = (fval.round() as i64).clamp(1, 2);
            data.insert(key.into(), json!(iv));
            let gp = hypr_dir().join("general.lua");
            if let Ok(txt) = fs::read_to_string(&gp) {
                let re = Regex::new(r"(\brounding_power\s*=\s*)[\d.]+").unwrap();
                let _ = fs::write(&gp, re.replace_all(&txt, format!("${{1}}{iv}")).as_ref());
            }
            hyprctl_silent(&["eval", &format!("hl.config({{ decoration = {{ rounding_power = {iv} }} }})")]);
        }
        "global_opacity" => { data.insert(key.into(), json!((fval.clamp(0.3, 1.0) * 100.0).round() / 100.0)); }
        "shell_opacity" | "cheatsheet_opacity" => { data.insert(key.into(), json!((fval.clamp(0.2, 1.0) * 100.0).round() / 100.0)); }
        "viz_fps" => { data.insert(key.into(), json!((fval as i64).clamp(10, 60))); }
        "viz_cols" => { data.insert(key.into(), json!((fval as i64).clamp(16, 256))); }
        "viz_sensibilite" => { data.insert(key.into(), json!((fval.clamp(0.05, 4.0) * 100.0).round() / 100.0)); }
        "viz_lissage" => { data.insert(key.into(), json!((fval.clamp(0.0, 0.99) * 100.0).round() / 100.0)); }
        "viz_epaisseur" => { data.insert(key.into(), json!((fval.clamp(0.5, 4.0) * 10.0).round() / 10.0)); }
        "viz_couleur" | "viz_couleur_island" if matches!(value, "accent" | "accentMuted" | "complement" | "fg" | "warn" | "success") => {
            data.insert(key.into(), json!(value));
        }
        "viz_style_classic" | "viz_style_island" if matches!(value, "onde" | "ruban" | "liquide" | "barres" | "miroir" | "pics" | "blocs" | "spectre") => {
            data.insert(key.into(), json!(value));
        }
        "bar_style" if matches!(value, "classic" | "island") => { data.insert(key.into(), json!(value)); }
        "bar_height" => { data.insert(key.into(), json!((fval as i64).clamp(14, 60))); }
        "panel_anim_duration" => { data.insert(key.into(), json!((fval as i64).clamp(80, 500))); }
        "bar_gaps_out_h" => { data.insert(key.into(), json!((fval as i64).clamp(0, 280))); }
        "bar_gaps_out_v" | "bar_gaps_out" => { data.insert(key.into(), json!((fval as i64).clamp(0, 32))); }
        "resize_step" => {
            data.insert(key.into(), json!((fval as i64).clamp(1, 200)));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            hyprctl_silent(&["reload"]);
            return;
        }
        "ilot_show_vpn" | "ilot_show_capture" | "ilot_show_live_activity" | "ilot_show_media"
        | "ilot_show_planka" | "ilot_show_workspaces" | "ilot_show_clock" => {
            let v = value.trim().to_ascii_lowercase();
            let norm = if matches!(v.as_str(), "off" | "compact" | "expanded" | "both") {
                v
            } else if is_true(&v) {
                "both".to_string()
            } else {
                "off".to_string()
            };
            data.insert(key.into(), json!(norm));
        }
        "maj_terminal_mode" => {
            let v = value.trim().to_ascii_lowercase();
            data.insert(key.into(), json!(if matches!(v.as_str(), "tiling" | "tile") { "tiling" } else { "float" }));
        }
        "matugen_scheme" if MATUGEN_SCHEMES.contains(&value) => { data.insert(key.into(), json!(value)); }
        "matugen_contrast" => { data.insert(key.into(), json!(fval.clamp(-1.0, 1.0))); }
        "blur_size" => { data.insert(key.into(), json!((fval as i64).clamp(1, 20))); }
        "blur_passes" => { data.insert(key.into(), json!((fval as i64).clamp(1, 8))); }
        "blur_vibrancy" => { data.insert(key.into(), json!(fval.clamp(0.0, 1.0))); }
        "depth_mask_seuil" => { data.insert(key.into(), json!((fval as i64).clamp(0, 100))); }
        "depth_mask_adouci" => { data.insert(key.into(), json!((fval as i64).clamp(0, 50))); }
        "shell_blur_alpha" => {
            data.insert(key.into(), json!((fval.clamp(0.0, 1.0) * 100.0).round() / 100.0));
            blur_changed = true;
        }
        "shell_blur_enabled" | "shell_blur_popups" => {
            data.insert(key.into(), json!(is_true(value)));
            blur_changed = true;
        }
        "lock_bg_mode" if matches!(value, "solid" | "image") => { data.insert(key.into(), json!(value)); }
        "lock_bg_color" => {
            let t = value.trim();
            if t.is_empty() {
                data.insert(key.into(), json!(""));
            } else {
                let hex = if t.starts_with('#') { t.to_string() } else { format!("#{t}") };
                if Regex::new(r"^#[0-9a-fA-F]{6}$").unwrap().is_match(&hex) {
                    data.insert(key.into(), json!(hex.to_ascii_lowercase()));
                }
            }
        }
        "lock_bg_image" => { data.insert(key.into(), json!(value.trim())); }
        "user_location_ville" | "user_location_tz" => {
            let s: String = value.trim().chars().take(80).collect();
            data.insert(key.into(), json!(s));
        }
        "user_location_lat" => { data.insert(key.into(), json!((fval.clamp(-90.0, 90.0) * 10000.0).round() / 10000.0)); }
        "user_location_lon" => { data.insert(key.into(), json!((fval.clamp(-180.0, 180.0) * 10000.0).round() / 10000.0)); }
        "launcher_position" if LAUNCHER_POSITIONS.contains(&value) => { data.insert(key.into(), json!(value)); }
        "active_theme" => {
            if data.get("palette").and_then(|v| v.as_object()).map(|p| p.contains_key(value)).unwrap_or(false) {
                data.insert("active_theme".into(), json!(value));
            }
        }
        k if COLOR_KEYS.contains(&k) => {
            let active = data.get("active_theme").and_then(|v| v.as_str()).unwrap_or("dynamic").to_string();
            let t = value.trim();
            let hex = if t.starts_with('#') { t.to_string() } else { format!("#{t}") };
            if Regex::new(r"^#[0-9a-fA-F]{6}$").unwrap().is_match(&hex) {
                let mut pal = data.get("palette").and_then(|v| v.as_object()).cloned().unwrap_or_default();
                let mut theme_obj = pal.get(&active).and_then(|v| v.as_object()).cloned().unwrap_or_default();
                theme_obj.insert(k.into(), json!(hex.to_ascii_lowercase()));
                pal.insert(active, Value::Object(theme_obj));
                data.insert("palette".into(), Value::Object(pal));
            }
        }
        _ => {}
    }

    let _ = write_json_atomic(&style_path(), &Value::Object(data.clone()), 0o644);
    if blur_changed {
        apply_shell_blur(&data, &load_widgets_vec());
    }
    let rofi_script = core_dir().join("generate_rofi_theme.sh");
    if rofi_script.is_file() {
        let _ = Command::new("bash").arg(rofi_script).status();
    }
}

fn resume_secrets() -> Value {
    let secrets = read_map(&secrets_path());
    let mut out = Map::new();
    for (sec, val) in secrets {
        if let Some(obj) = val.as_object() {
            for (nom, cle) in obj {
                if let Some(s) = cle.as_str().map(|x| x.trim()).filter(|x| !x.is_empty()) {
                    let tail: String = s.chars().rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
                    out.insert(format!("{sec}.{nom}"), json!({ "present": true, "tail": tail }));
                }
            }
        }
    }
    Value::Object(out)
}

fn lire_homelab() -> Value {
    let d = read_map(&homelab_path());
    let pve = d.get("proxmox").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let secrets = read_map(&secrets_path());
    let sec = secrets.get("proxmox").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let secret = sec.get("token_secret").and_then(|v| v.as_str()).unwrap_or("");
    let tail: String = secret.chars().rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
    json!({
        "proxmox_url": pve.get("url").and_then(|v| v.as_str()).unwrap_or(""),
        "proxmox_token_id": pve.get("token_id").or_else(|| sec.get("token_id")).and_then(|v| v.as_str()).unwrap_or(""),
        "proxmox_verifier_tls": pve.get("verifier_tls").and_then(|v| v.as_bool()).unwrap_or(false),
        "jeton_present": !secret.is_empty(),
        "jeton_tail": tail,
        "hotes": d.get("hotes").cloned().unwrap_or_else(|| json!([])),
    })
}

fn lire_todo() -> Vec<Value> {
    let raw = read_json_value(&todo_path());
    let arr = raw.get("fichiers").and_then(|v| v.as_array()).or_else(|| raw.as_array()).cloned().unwrap_or_default();
    let mut out = Vec::new();
    for e in arr {
        let (ch, nom) = if let Some(s) = e.as_str() {
            (s.trim().to_string(), String::new())
        } else {
            (
                e.get("chemin").and_then(|v| v.as_str()).unwrap_or("").trim().to_string(),
                e.get("nom").and_then(|v| v.as_str()).unwrap_or("").to_string(),
            )
        };
        if ch.is_empty() {
            continue;
        }
        let base = std::path::Path::new(&ch).file_name().and_then(|s| s.to_str()).unwrap_or("").to_string();
        out.push(json!({ "chemin": ch, "nom": if nom.is_empty() { base } else { nom } }));
    }
    out
}

fn lire_todo_focus(fichiers: &[Value]) -> String {
    let memo = read_json_value(&todo_focus_path())
        .get("fichier")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let noms: Vec<String> = fichiers
        .iter()
        .filter_map(|e| e.get("nom").and_then(|v| v.as_str()).map(|s| s.to_string()))
        .collect();
    if noms.contains(&memo) {
        memo
    } else {
        noms.first().cloned().unwrap_or_default()
    }
}

fn lire_todo_surveillance() -> bool {
    read_json_value(&todo_path())
        .get("surveillance")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn get_idle_suspend_timeout(style: &Map<String, Value>) -> i64 {
    if let Some(v) = style.get("idle_suspend_timeout").and_then(|v| v.as_i64()) {
        return v;
    }
    let re = Regex::new(r"listener\s*\{\s*timeout\s*=\s*(\d+)\s*[^}]*systemctl\s+suspend").unwrap();
    for c in [home_dir().join(".config/hypr/hypridle.conf"), hypr_dir().join("hypridle.conf")] {
        if let Ok(txt) = fs::read_to_string(&c) {
            if let Some(cap) = re.captures(&txt) {
                if let Ok(v) = cap[1].parse::<i64>() {
                    return v;
                }
            }
        }
    }
    3600
}

fn set_idle_suspend_timeout(seconds: &str) {
    let val = seconds.parse::<i64>().unwrap_or(3600);
    let mut style = read_map(&style_path());
    style.insert("idle_suspend_timeout".into(), json!(val));
    let _ = write_json_atomic(&style_path(), &Value::Object(style), 0o644);

    let re_disable = Regex::new(r"listener\s*\{\s*timeout\s*=\s*\d+\s*[^}]*systemctl\s+suspend[^}]*\}").unwrap();
    let active_re = Regex::new(r"(listener\s*\{\s*timeout\s*=\s*)\d+(\s*[^}]*systemctl\s+suspend[^}]*\})").unwrap();
    let comm_re = Regex::new(r"#\s*listener\s*\{\s*\n(?:#\s*[^\n]*\n)*?#\s*\}").unwrap();
    let dev_root = core_dir().parent().unwrap_or(&core_dir()).to_path_buf();
    for c in [
        home_dir().join(".config/hypr/hypridle.conf"),
        dev_root.join("hypr_modular/hypridle.conf"),
        hypr_dir().join("hypridle.conf"),
    ] {
        if let Ok(txt) = fs::read_to_string(&c) {
            let new_txt = if val == 0 {
                re_disable
                    .replace_all(&txt, |caps: &regex::Captures| {
                        caps[0].lines().map(|l| format!("# {l}")).collect::<Vec<_>>().join("\n")
                    })
                    .to_string()
            } else if active_re.is_match(&txt) {
                active_re.replace_all(&txt, format!("${{1}}{val}${{2}}")).to_string()
            } else {
                let repl = format!("listener {{\n    timeout = {val}\n    on-timeout = systemctl suspend          # Met le système en veille\n}}");
                if comm_re.is_match(&txt) {
                    comm_re.replace(&txt, repl.as_str()).to_string()
                } else {
                    format!("{}\n\n# 2. MISE EN VEILLE DU SYSTÈME\n{repl}\n", txt.trim_end())
                }
            };
            let _ = fs::write(&c, new_txt);
        }
    }
    let _ = Command::new("systemctl").args(["--user", "restart", "hypridle"]).status();
}

fn load_notif_targets() -> Map<String, Value> {
    let mut data = read_map(&notif_targets_path());
    data.entry("apps").or_insert_with(|| json!({}));
    data.entry("types").or_insert_with(|| json!({ "video": "Video", "image": "Images", "folder": "Files", "text": "Editor" }));
    data.entry("url").or_insert_with(|| json!("Browser"));
    data.entry("terminal_alias").or_insert_with(|| json!("Terminal"));
    data
}

fn get_autostart() -> Vec<Value> {
    if let Value::Array(arr) = read_json_value(&autostart_path()) {
        return arr;
    }
    vec![
        json!({"name": "Quickshell (barre)", "cmd": "sh -c '/usr/bin/pgrep -x quickshell >/dev/null || exec quickshell -n' &", "enabled": true}),
        json!({"name": "Hypridle (inactivité)", "cmd": "systemctl --user start hypridle", "enabled": true}),
        json!({"name": "awww-daemon (wallpaper, si Noctalia absent)", "cmd": "sh -c '/usr/bin/pgrep -x awww-daemon >/dev/null || exec awww-daemon' &", "enabled": true}),
        json!({"name": "Agent Polkit", "cmd": "sh -c '$HOME/.config/quickshell/core/agent_polkit.sh' &", "enabled": true}),
        json!({"name": "Presse-papiers (veilleurs cliphist)", "cmd": "sh -c '$HOME/.config/quickshell/core/cliphist_watch.sh' &", "enabled": true}),
    ]
}

fn get_wallpaper_dir(style: &Map<String, Value>) -> String {
    if let Some(w) = style.get("wallpaper_dir").and_then(|v| v.as_str()).map(|s| s.trim()).filter(|s| !s.is_empty()) {
        return w.to_string();
    }
    for cfg in [
        home_dir().join(".config/quickshell/hyprquickpaper/config.json"),
        core_dir().parent().unwrap_or(&core_dir()).join("hyprquickpaper/config.json"),
    ] {
        if let Some(wp) = read_json_value(&cfg).get("wallpaper_path").and_then(|v| v.as_str()).map(|s| s.trim()).filter(|s| !s.is_empty()) {
            return wp.to_string();
        }
    }
    "$HOME/Images/wallpapers/".to_string()
}

pub fn get_full_config_state() -> Value {
    let style = read_map(&style_path());
    let kb = get_kb_layout();
    let get_b = |k: &str, d: bool| style.get(k).and_then(|v| v.as_bool()).unwrap_or(d);
    let get_i = |k: &str, d: i64| style.get(k).and_then(|v| v.as_i64()).unwrap_or(d);
    let get_f = |k: &str, d: f64| style.get(k).and_then(|v| v.as_f64()).unwrap_or(d);
    let get_s = |k: &str, d: &str| style.get(k).and_then(|v| v.as_str()).unwrap_or(d).to_string();
    let gaps_out = get_i("bar_gaps_out", 8);
    let todo_fichiers = lire_todo();
    let todo_focus = lire_todo_focus(&todo_fichiers);
    let todo_surv = lire_todo_surveillance();

    json!({
        "hostname": get_hostname(),
        "is_laptop": is_laptop_system(),
        "kb_layout": kb,
        "workspace_keys": workspace_keys_for_layout(&kb),
        "first_run_completed": get_b("first_run_completed", false),
        "ilot_projets_actif": get_b("ilot_projets_actif", true),
        "show_config_button": get_b("show_config_button", true),
        "bar_height": get_i("bar_height", 40),
        "bar_gaps_out": gaps_out,
        "bar_gaps_out_h": get_i("bar_gaps_out_h", gaps_out),
        "bar_gaps_out_v": get_i("bar_gaps_out_v", gaps_out),
        "launcher_position": get_s("launcher_position", "bas-centre"),
        "widgets": load_widgets_vec(),
        "global_radius": get_i("global_radius", 2),
        "global_opacity": get_f("global_opacity", 0.7),
        "shell_opacity": get_f("shell_opacity", 0.7),
        "cheatsheet_opacity": get_f("cheatsheet_opacity", 0.88),
        "bar_style": get_s("bar_style", "classic"),
        "panel_anim_duration": get_i("panel_anim_duration", 240),
        "bar_border": get_b("bar_border", true),
        "bar_gaps_transparent": get_b("bar_gaps_transparent", false),
        "viz_fps": get_i("viz_fps", 30),
        "viz_cols": get_i("viz_cols", 96),
        "viz_sensibilite": get_f("viz_sensibilite", 1.0),
        "viz_lissage": get_f("viz_lissage", 0.2),
        "viz_epaisseur": get_f("viz_epaisseur", 1.4),
        "viz_couleur": get_s("viz_couleur", "accent"),
        "viz_couleur_island": get_s("viz_couleur_island", "complement"),
        "viz_style_classic": get_s("viz_style_classic", "onde"),
        "viz_style_island": get_s("viz_style_island", "barres"),
        "hypr_rounding": get_hypr_rounding(),
        "hypr_rounding_power": get_hypr_rounding_power(),
        "api_keys": resume_secrets(),
        "llm_providers": llm::charger_providers_list(),
        "wallpaper_dir": get_wallpaper_dir(&style),
        "screenshots_dir": style.get("screenshots_dir").and_then(|v| v.as_str()).filter(|s| !s.is_empty()).unwrap_or("$HOME/Images/Screenshots/"),
        "lock_bg_mode": get_s("lock_bg_mode", "solid"),
        "lock_bg_color": get_s("lock_bg_color", ""),
        "lock_bg_image": get_s("lock_bg_image", ""),
        "matugen_scheme": get_s("matugen_scheme", "scheme-tonal-spot"),
        "matugen_contrast": get_f("matugen_contrast", 0.0),
        "blur_enabled": get_b("blur_enabled", true),
        "blur_size": get_i("blur_size", 3),
        "blur_passes": get_i("blur_passes", 3),
        "blur_vibrancy": get_f("blur_vibrancy", 0.1696),
        "shell_blur_enabled": get_b("shell_blur_enabled", true),
        "shell_blur_alpha": get_f("shell_blur_alpha", 0.3),
        "shell_blur_popups": get_b("shell_blur_popups", true),
        "depth_wallpaper": get_b("depth_wallpaper", false),
        "wallpaper_slide": get_b("wallpaper_slide", false),
        "ilot_coins_groupes": get_b("ilot_coins_groupes", false),
        "panel_accordion": get_b("panel_accordion", true),
        "user_location_ville": get_s("user_location_ville", ""),
        "user_location_lat": style.get("user_location_lat").cloned().unwrap_or(Value::Null),
        "user_location_lon": style.get("user_location_lon").cloned().unwrap_or(Value::Null),
        "user_location_tz": get_s("user_location_tz", ""),
        "depth_mask": get_b("depth_mask", false),
        "depth_mask_seuil": get_i("depth_mask_seuil", 30),
        "depth_mask_adouci": get_i("depth_mask_adouci", 8),
        "launch_history": get_b("launch_history", false),
        "resize_step": get_i("resize_step", 15),
        "panel_sections": style.get("panel_sections").cloned().unwrap_or_else(|| json!({})),
        "gaps": get_hypr_gaps(),
        "display": get_monitors_info(),
        "binds": get_binds_list(),
        "apps": read_map(&app_vars_path()),
        "notif_targets": Value::Object(load_notif_targets()),
        "autostart": get_autostart(),
        "homelab": lire_homelab(),
        "todo": { "fichiers": todo_fichiers, "focus": todo_focus, "surveillance": todo_surv },
        "night": {
            "mode": get_b("night_mode", false),
            "temperature": get_i("night_temp", 4000),
            "from": get_s("night_from", ""),
            "to": get_s("night_to", ""),
        },
        "do_not_disturb": get_b("do_not_disturb", false),
        "idle_suspend_timeout": get_idle_suspend_timeout(&style),
    })
}

fn get_diag_info(log_source: &str) -> Value {
    let mut services = Vec::new();
    for unit in ["quickshell.service", "hermes-approbations.service", "polkit-agent.service"] {
        let state = run_cmd("systemctl", &["--user", "is-active", unit])
            .map(|o| {
                let s = String::from_utf8_lossy(&o.stdout);
                let s = if s.trim().is_empty() { String::from_utf8_lossy(&o.stderr) } else { s };
                s.lines().next().unwrap_or("unknown").trim().to_string()
            })
            .unwrap_or_else(|| "unknown".to_string());
        services.push(json!({ "name": unit, "state": state, "active": state == "active" }));
    }
    let logs: Vec<String> = if log_source == "notifications" {
        let lp = cache_dir().join("notifications.log");
        if let Ok(txt) = fs::read_to_string(&lp) {
            let all: Vec<String> = txt.lines().map(|l| l.to_string()).collect();
            all.into_iter().rev().take(30).collect::<Vec<_>>().into_iter().rev().collect()
        } else {
            vec!["Aucun journal de notifications pour l'instant.".to_string()]
        }
    } else {
        let mut l = run_cmd("journalctl", &["--user", "-u", "quickshell.service", "-n", "30", "--no-pager", "-o", "short"])
            .map(|o| String::from_utf8_lossy(&o.stdout).lines().filter(|s| !s.trim().is_empty()).map(|s| s.to_string()).collect::<Vec<_>>())
            .unwrap_or_default();
        if l.is_empty() {
            l.push("Aucune entrée récente pour quickshell.service.".to_string());
        }
        l
    };

    let bdir = home_dir().join(".config/backups_env");
    let mut backups = Vec::new();
    if let Ok(rd) = fs::read_dir(&bdir) {
        let mut entries: Vec<(String, u64)> = rd
            .flatten()
            .filter_map(|e| {
                let name = e.file_name().to_str()?.to_string();
                if name.starts_with("backup_") && name.ends_with(".tar.gz") {
                    let sz = e.metadata().ok()?.size();
                    Some((name, (sz / 1024).max(1)))
                } else {
                    None
                }
            })
            .collect();
        entries.sort_by(|a, b| b.0.cmp(&a.0));
        for (name, kb) in entries.into_iter().take(10) {
            backups.push(json!({ "name": name, "size_kb": kb }));
        }
    }
    json!({ "ok": true, "services": services, "logs": logs, "backups": backups, "log_source": log_source })
}

fn planka_test() -> Value {
    let secrets = read_map(&secrets_path());
    let Some(planka) = secrets.get("planka").and_then(|v| v.as_object()) else {
        return json!({ "ok": false, "message": "URL ou jeton API manquant dans core/secrets.json" });
    };
    let mut url = planka.get("url").and_then(|v| v.as_str()).unwrap_or("").trim().trim_end_matches('/').to_string();
    let api_key = planka.get("api_key").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    if url.is_empty() || api_key.is_empty() {
        return json!({ "ok": false, "message": "Renseigner l'URL et le jeton API d'abord" });
    }
    if !url.starts_with("http://") && !url.starts_with("https://") {
        url = format!("https://{url}");
    }
    match ureq::get(&format!("{url}/api/users/me"))
        .set("X-Api-Key", &api_key)
        .set("Accept", "application/json")
        .timeout(std::time::Duration::from_secs(6))
        .call()
    {
        Ok(resp) => {
            let body: Value = resp.into_json().unwrap_or(Value::Null);
            let nom = body
                .get("item")
                .and_then(|it| it.get("username").or_else(|| it.get("name")).or_else(|| it.get("email")))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            let msg = if nom.is_empty() { "Connexion réussie (HTTP 200)".to_string() } else { format!("Connecté ({nom})") };
            json!({ "ok": true, "message": msg })
        }
        Err(ureq::Error::Status(code, _)) => json!({ "ok": false, "message": format!("Refusé (HTTP {code})") }),
        Err(e) => json!({ "ok": false, "message": format!("Injoignable ({e})") }),
    }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("state");
    match action {
        "state" => sortir(&get_full_config_state()),
        "kb_layout" if args.len() >= 2 => {
            set_kb_layout(&args[1], true);
            sortir(&get_full_config_state())
        }
        "kb_layout_only" if args.len() >= 2 => {
            if set_kb_layout(&args[1], false) { 0 } else { 1 }
        }
        "todo_add" if args.len() >= 3 => {
            let chemin = args[2].trim();
            let reel = if let Some(r) = chemin.strip_prefix("~/") { home_dir().join(r) } else { PathBuf::from(chemin) };
            if !chemin.is_empty() && reel.is_file() {
                let libelle = if args[1].trim().is_empty() {
                    reel.file_name().and_then(|s| s.to_str()).unwrap_or("").to_string()
                } else {
                    args[1].trim().to_string()
                };
                let mut liste = lire_todo();
                let mut found = false;
                for e in &mut liste {
                    if e.get("chemin").and_then(|v| v.as_str()) == Some(chemin)
                        || e.get("nom").and_then(|v| v.as_str()) == Some(&libelle)
                    {
                        if let Some(m) = e.as_object_mut() {
                            m.insert("chemin".into(), json!(chemin));
                            m.insert("nom".into(), json!(libelle));
                        }
                        found = true;
                        break;
                    }
                }
                if !found {
                    liste.push(json!({ "chemin": chemin, "nom": libelle }));
                }
                let surv = lire_todo_surveillance();
                let _ = write_json_atomic(&todo_path(), &json!({ "surveillance": surv, "fichiers": liste }), 0o644);
            }
            sortir(&get_full_config_state())
        }
        "todo_del" if args.len() >= 2 => {
            let liste: Vec<Value> = lire_todo()
                .into_iter()
                .filter(|e| e.get("nom").and_then(|v| v.as_str()) != Some(args[1].as_str()))
                .collect();
            let surv = lire_todo_surveillance();
            let _ = write_json_atomic(&todo_path(), &json!({ "surveillance": surv, "fichiers": liste }), 0o644);
            sortir(&get_full_config_state())
        }
        "todo_focus" if args.len() >= 2 => {
            let _ = write_json_atomic(&todo_focus_path(), &json!({ "fichier": args[1] }), 0o644);
            sortir(&get_full_config_state())
        }
        "todo_surveillance" => {
            let cur = lire_todo_surveillance();
            let next = if args.len() >= 2 { is_true(&args[1]) } else { !cur };
            let _ = write_json_atomic(&todo_path(), &json!({ "surveillance": next, "fichiers": lire_todo() }), 0o644);
            sortir(&get_full_config_state())
        }
        "todo_list" => {
            let f = lire_todo();
            let foc = lire_todo_focus(&f);
            sortir(&json!({ "fichiers": f, "focus": foc, "surveillance": lire_todo_surveillance() }))
        }
        "idle_timeout" if args.len() >= 2 => {
            set_idle_suspend_timeout(&args[1]);
            sortir(&get_full_config_state())
        }
        "homelab_set" if args.len() >= 3 => {
            let mut d = read_map(&homelab_path());
            let mut pve = d.get("proxmox").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            pve.entry("verifier_tls").or_insert(json!(false));
            match args[1].as_str() {
                "proxmox_url" => { pve.insert("url".into(), json!(args[2].trim())); }
                "proxmox_token_id" => { pve.insert("token_id".into(), json!(args[2].trim())); }
                "proxmox_verifier_tls" => { pve.insert("verifier_tls".into(), json!(is_true(&args[2]))); }
                _ => {}
            }
            d.insert("proxmox".into(), Value::Object(pve));
            let _ = write_json_atomic(&homelab_path(), &Value::Object(d), 0o644);
            sortir(&get_full_config_state())
        }
        "api_key_set_file" if args.len() >= 2 => {
            let tmp_path = PathBuf::from(&args[1]);
            let payload = read_json_value(&tmp_path);
            let _ = fs::remove_file(&tmp_path);
            let sec = payload.get("section").and_then(|v| v.as_str()).unwrap_or("").trim();
            let nom = payload.get("nom").and_then(|v| v.as_str()).unwrap_or("api_key").trim();
            let val = payload.get("valeur").and_then(|v| v.as_str()).unwrap_or("").trim();
            if sec.is_empty() || val.is_empty() {
                return sortir(&json!({ "ok": false, "erreur": "section ou valeur vide" }));
            }
            let mut secrets = read_map(&secrets_path());
            let mut sec_obj = secrets.get(sec).and_then(|v| v.as_object()).cloned().unwrap_or_default();
            sec_obj.insert(nom.into(), json!(val));
            secrets.insert(sec.into(), Value::Object(sec_obj));
            let ok = write_private_json(&secrets_path(), &Value::Object(secrets)).is_ok();
            let tail: String = val.chars().rev().take(4).collect::<Vec<_>>().into_iter().rev().collect();
            sortir(&json!({ "ok": ok, "section": sec, "nom": nom, "tail": if ok { tail } else { String::new() } }))
        }
        "planka_test" => sortir(&planka_test()),
        "complete_first_run" => {
            let mut data = read_map(&style_path());
            data.insert("first_run_completed".into(), json!(true));
            if !data.contains_key("kb_layout") {
                data.insert("kb_layout".into(), json!(get_kb_layout()));
            }
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "panel_section" if args.len() >= 3 => {
            let mut data = read_map(&style_path());
            let mut secs = data.get("panel_sections").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            secs.insert(args[1].clone(), json!(is_true(&args[2])));
            data.insert("panel_sections".into(), Value::Object(secs));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "widget_list" => sortir(&get_full_config_state()),
        "widget_add" if args.len() >= 2 => {
            let ws = args.get(2).and_then(|s| s.parse::<i64>().ok()).unwrap_or(1);
            let wx = args.get(3).and_then(|s| s.parse::<i64>().ok()).unwrap_or(120);
            let wy = args.get(4).and_then(|s| s.parse::<i64>().ok()).unwrap_or(160);
            widget_add(&args[1], ws, wx, wy);
            sortir(&get_full_config_state())
        }
        "widget_set" if args.len() >= 4 => {
            widget_set(&args[1], &args[2], &args[3]);
            sortir(&get_full_config_state())
        }
        "widget_workspaces" if args.len() >= 3 => {
            widget_workspaces(&args[1], &args[2]);
            sortir(&get_full_config_state())
        }
        "widget_move" if args.len() >= 4 => {
            let wx = args[2].parse::<f64>().unwrap_or(0.0) as i64;
            let wy = args[3].parse::<f64>().unwrap_or(0.0) as i64;
            widget_update(&args[1], |w| {
                w.insert("x".into(), json!(wx));
                w.insert("y".into(), json!(wy));
            });
            sortir(&get_full_config_state())
        }
        "widget_remove" if args.len() >= 2 => {
            let items: Vec<Value> = load_widgets_vec()
                .into_iter()
                .filter(|w| w.get("id").and_then(|v| v.as_str()) != Some(args[1].as_str()))
                .collect();
            save_widgets_vec(&items);
            sortir(&get_full_config_state())
        }
        "style" if args.len() >= 3 => {
            update_style_var(&args[1], &args[2]);
            sortir(&get_full_config_state())
        }
        "notif_quiet" if args.len() >= 3 => {
            let mut data = read_map(&style_path());
            let mut apps: Vec<String> = data
                .get("quiet_notif_apps")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
                .unwrap_or_default();
            let name = args[2..].join(" ").trim().to_string();
            let quiet = args[1] == "true";
            if !name.is_empty() {
                if quiet && !apps.contains(&name) {
                    apps.push(name);
                } else if !quiet {
                    apps.retain(|x| x != &name);
                }
                data.insert("quiet_notif_apps".into(), json!(apps));
                let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            }
            sortir(&json!({ "ok": true, "quiet_notif_apps": apps }))
        }
        "gaps" if args.len() >= 3 => {
            update_hypr_gaps(&args[1], &args[2]);
            sortir(&get_full_config_state())
        }
        "monitor_primary" if args.len() >= 2 => {
            set_primary_monitor(&args[1]);
            sortir(&get_full_config_state())
        }
        "monitor_profile" if args.len() >= 2 => {
            set_monitor_profile(&args[1]);
            sortir(&get_full_config_state())
        }
        "monitor_mode" if args.len() >= 3 => {
            let scale = args.get(3).map(|s| s.as_str()).unwrap_or("1");
            set_monitor_mode(&args[1], &args[2], scale);
            sortir(&get_full_config_state())
        }
        "rotate" if args.len() >= 2 => {
            set_screen_rotation(&args[1]);
            sortir(&get_full_config_state())
        }
        "binds" => sortir(&json!({ "ok": true, "binds": get_binds_list() })),
        "bind_set" if args.len() >= 3 => {
            set_keybind(&args[1], &args[2..].join(" "));
            sortir(&get_full_config_state())
        }
        "bind_del" if args.len() >= 2 => {
            remove_keybind(&args[1]);
            sortir(&get_full_config_state())
        }
        "sync_generated" => {
            sync_programs_lua(&read_map(&app_vars_path()));
            sync_autostart_lua(&get_autostart());
            sortir(&json!({ "ok": true }))
        }
        "app_set" if args.len() >= 3 => {
            let alias = args[1].trim();
            let cmd = args[2..].join(" ").trim().to_string();
            if !lua_ident(alias).is_empty() && !cmd.is_empty() {
                let mut data = read_map(&app_vars_path());
                data.insert(alias.into(), json!(cmd));
                let _ = write_json_atomic(&app_vars_path(), &Value::Object(data.clone()), 0o644);
                sync_programs_lua(&data);
                let _ = lien_systeme::run(&["--appliquer".to_string()]);
            }
            sortir(&get_full_config_state())
        }
        "app_var" if args.len() >= 3 => {
            let alias = args[1].trim();
            let cmd = args[2..].join(" ").trim().to_string();
            if lua_ident(alias).is_empty() || cmd.is_empty() {
                return 1;
            }
            let mut data = read_map(&app_vars_path());
            data.insert(alias.into(), json!(cmd));
            let _ = write_json_atomic(&app_vars_path(), &Value::Object(data.clone()), 0o644);
            sync_programs_lua(&data);
            0
        }
        "app_del" if args.len() >= 2 => {
            let mut data = read_map(&app_vars_path());
            if data.remove(&args[1]).is_some() {
                let _ = write_json_atomic(&app_vars_path(), &Value::Object(data.clone()), 0o644);
                sync_programs_lua(&data);
            }
            sortir(&get_full_config_state())
        }
        "notif_app_set" if args.len() >= 3 => {
            let key = args[1].trim();
            let cmd = args[2..].join(" ").trim().to_string();
            if key.is_empty() || cmd.is_empty() {
                return sortir(&json!({ "ok": false }));
            }
            let mut data = load_notif_targets();
            let mut apps = data.get("apps").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            let term = apps.get(key).and_then(|v| v.get("terminal")).and_then(|v| v.as_bool()).unwrap_or(false);
            let mut entry = Map::new();
            entry.insert("run".into(), json!(cmd));
            if term {
                entry.insert("terminal".into(), json!(true));
            }
            apps.insert(key.into(), Value::Object(entry));
            data.insert("apps".into(), Value::Object(apps));
            let ok = write_json_atomic(&notif_targets_path(), &Value::Object(data), 0o644).is_ok();
            sortir(&json!({ "ok": ok }))
        }
        "notif_app_del" if args.len() >= 2 => {
            let mut data = load_notif_targets();
            let mut apps = data.get("apps").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            let ok = apps.remove(&args[1]).is_some();
            if ok {
                data.insert("apps".into(), Value::Object(apps));
                let _ = write_json_atomic(&notif_targets_path(), &Value::Object(data), 0o644);
            }
            sortir(&json!({ "ok": ok }))
        }
        "notif_type_set" if args.len() >= 3 => {
            let (nat, al) = (args[1].trim(), args[2].trim());
            if nat.is_empty() || al.is_empty() {
                return sortir(&json!({ "ok": false }));
            }
            let mut data = load_notif_targets();
            let mut types = data.get("types").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            types.insert(nat.into(), json!(al));
            data.insert("types".into(), Value::Object(types));
            let ok = write_json_atomic(&notif_targets_path(), &Value::Object(data), 0o644).is_ok();
            sortir(&json!({ "ok": ok }))
        }
        "notif_url_set" if args.len() >= 2 => {
            let al = args[1].trim();
            if al.is_empty() {
                return sortir(&json!({ "ok": false }));
            }
            let mut data = load_notif_targets();
            data.insert("url".into(), json!(al));
            let ok = write_json_atomic(&notif_targets_path(), &Value::Object(data), 0o644).is_ok();
            sortir(&json!({ "ok": ok }))
        }
        "autostart_set" if args.len() >= 3 => {
            let mut entries = get_autostart();
            let en = args[2] == "true";
            let mut changed = false;
            for e in &mut entries {
                if e.get("name").and_then(|v| v.as_str()) == Some(args[1].as_str()) {
                    if let Some(m) = e.as_object_mut() {
                        m.insert("enabled".into(), json!(en));
                        changed = true;
                    }
                }
            }
            if changed {
                let _ = write_json_atomic(&autostart_path(), &Value::Array(entries.clone()), 0o644);
                sync_autostart_lua(&entries);
            }
            sortir(&get_full_config_state())
        }
        "autostart_add" if args.len() >= 3 => {
            let name = args[1].trim();
            let cmd = args[2..].join(" ").trim().to_string();
            let mut entries = get_autostart();
            if !name.is_empty() && !cmd.is_empty() && !entries.iter().any(|e| e.get("name").and_then(|v| v.as_str()) == Some(name)) {
                entries.push(json!({ "name": name, "cmd": cmd, "enabled": true }));
                let _ = write_json_atomic(&autostart_path(), &Value::Array(entries.clone()), 0o644);
                sync_autostart_lua(&entries);
            }
            sortir(&get_full_config_state())
        }
        "autostart_del" if args.len() >= 2 => {
            let entries = get_autostart();
            let kept: Vec<Value> = entries
                .iter()
                .filter(|e| e.get("name").and_then(|v| v.as_str()) != Some(args[1].as_str()))
                .cloned()
                .collect();
            if kept.len() != entries.len() {
                let _ = write_json_atomic(&autostart_path(), &Value::Array(kept.clone()), 0o644);
                sync_autostart_lua(&kept);
            }
            sortir(&get_full_config_state())
        }
        "battery" if args.len() >= 2 => {
            let _ = system_service::run(&["limit".to_string(), args[1].clone()]);
            sortir(&get_full_config_state())
        }
        "ilot_applet_mode" if args.len() >= 3 => {
            let aid = args[1].trim();
            let raw_m = args[2].trim().to_ascii_lowercase();
            let mode = if matches!(raw_m.as_str(), "off" | "compact" | "expanded" | "both") { raw_m.as_str() } else { "off" };
            let mut data = read_map(&style_path());
            let mut modes = data.get("ilot_applets_mode").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            modes.insert(aid.into(), json!(mode));
            data.insert("ilot_applets_mode".into(), Value::Object(modes));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "ilot_applet_move" if args.len() >= 3 => {
            let aid = args[1].trim().to_string();
            let dir = args[2].trim().to_ascii_lowercase();
            let mut data = read_map(&style_path());
            let mut order: Vec<String> = data
                .get("ilot_applets_order")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
                .unwrap_or_default();
            if order.is_empty() {
                order = DEFAULT_ILOT_ORDER.iter().map(|s| s.to_string()).collect();
            } else {
                for &d in DEFAULT_ILOT_ORDER {
                    if !order.iter().any(|x| x == d) {
                        order.push(d.to_string());
                    }
                }
            }
            if !aid.is_empty() && !order.contains(&aid) {
                order.push(aid.clone());
            }
            if let Some(idx) = order.iter().position(|x| x == &aid) {
                let corners = data.get("ilot_applets_corner").and_then(|v| v.as_object()).cloned().unwrap_or_default();
                let target_c = corners.get(&aid).and_then(|v| v.as_str()).unwrap_or("");
                let modes = data.get("ilot_applets_mode").and_then(|v| v.as_object()).cloned().unwrap_or_default();
                let def_exp = ["systray", "minimise", "luminosite", "batterie"];
                let actif = |x: &str| {
                    modes.get(x).and_then(|v| v.as_str()).unwrap_or(if def_exp.contains(&x) { "expanded" } else { "off" }) != "off"
                };
                let pas: isize = if matches!(dir.as_str(), "left" | "gauche" | "up" | "monter") { -1 } else { 1 };
                let mut nxt = idx as isize + pas;
                let mut found = None;
                while nxt >= 0 && (nxt as usize) < order.len() {
                    let cand = &order[nxt as usize];
                    if corners.get(cand).and_then(|v| v.as_str()).unwrap_or("") == target_c && actif(cand) {
                        found = Some(nxt as usize);
                        break;
                    }
                    nxt += pas;
                }
                if let Some(j) = found {
                    order.swap(idx, j);
                } else {
                    let n2 = idx as isize + pas;
                    if n2 >= 0 && (n2 as usize) < order.len() {
                        order.swap(idx, n2 as usize);
                    }
                }
            }
            data.insert("ilot_applets_order".into(), json!(order));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "ilot_applet_corner" if args.len() >= 3 => {
            let aid = args[1].trim().to_string();
            let raw_c = args[2].trim().to_ascii_lowercase();
            let corner = match raw_c.as_str() {
                "top-left" | "top-right" | "bottom-left" | "bottom-right" => raw_c,
                _ => String::new(),
            };
            let mut data = read_map(&style_path());
            let mut corners = data.get("ilot_applets_corner").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            if corner.is_empty() {
                corners.remove(&aid);
            } else {
                corners.insert(aid.clone(), json!(corner));
                let mut modes = data.get("ilot_applets_mode").and_then(|v| v.as_object()).cloned().unwrap_or_default();
                let def_exp = ["systray", "minimise", "luminosite", "batterie"];
                let cur = modes.get(&aid).and_then(|v| v.as_str()).unwrap_or(if def_exp.contains(&aid.as_str()) { "expanded" } else { "off" });
                if cur == "off" {
                    modes.insert(aid, json!("both"));
                    data.insert("ilot_applets_mode".into(), Value::Object(modes));
                }
            }
            data.insert("ilot_applets_corner".into(), Value::Object(corners));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "ilot_applet_move_to" if args.len() >= 3 => {
            let aid = args[1].trim().to_string();
            let raw_c = args[2].trim().to_ascii_lowercase();
            let corner = match raw_c.as_str() {
                "top-left" | "top-right" | "bottom-left" | "bottom-right" => raw_c,
                _ => String::new(),
            };
            let idx_target = args.get(3).and_then(|s| s.parse::<isize>().ok());
            let mut data = read_map(&style_path());
            let mut order: Vec<String> = data
                .get("ilot_applets_order")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect())
                .unwrap_or_default();
            if order.is_empty() {
                order = DEFAULT_ILOT_ORDER.iter().map(|s| s.to_string()).collect();
            } else {
                for &d in DEFAULT_ILOT_ORDER {
                    if !order.iter().any(|x| x == d) {
                        order.push(d.to_string());
                    }
                }
            }
            if !aid.is_empty() && !order.contains(&aid) {
                order.push(aid.clone());
            }
            let mut corners = data.get("ilot_applets_corner").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            if corner.is_empty() { corners.remove(&aid); } else { corners.insert(aid.clone(), json!(corner)); }
            let mut modes = data.get("ilot_applets_mode").and_then(|v| v.as_object()).cloned().unwrap_or_default();
            let def_exp = ["systray", "minimise", "luminosite", "batterie"];
            let cur_mode = modes.get(&aid).and_then(|v| v.as_str()).unwrap_or(if def_exp.contains(&aid.as_str()) { "expanded" } else { "off" });
            if cur_mode == "off" {
                modes.insert(aid.clone(), json!("both"));
            }
            if let Some(pos_cur) = order.iter().position(|x| x == &aid) {
                order.remove(pos_cur);
                let groupe_positions: Vec<usize> = order
                    .iter()
                    .enumerate()
                    .filter(|(_, x)| corners.get(x.as_str()).and_then(|v| v.as_str()).unwrap_or("") == corner)
                    .map(|(i, _)| i)
                    .collect();
                let insert_pos = match idx_target {
                    None => groupe_positions.last().map(|&p| p + 1).unwrap_or(order.len()),
                    Some(idx) if (idx as usize) >= groupe_positions.len() => groupe_positions.last().map(|&p| p + 1).unwrap_or(order.len()),
                    Some(idx) if idx <= 0 => groupe_positions.first().copied().unwrap_or(0),
                    Some(idx) => groupe_positions[idx as usize],
                };
                order.insert(insert_pos, aid);
            }
            data.insert("ilot_applets_order".into(), json!(order));
            data.insert("ilot_applets_corner".into(), Value::Object(corners));
            data.insert("ilot_applets_mode".into(), Value::Object(modes));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "ilot_applets_reset" => {
            let mut data = read_map(&style_path());
            data.remove("ilot_applets_order");
            data.remove("ilot_applets_corner");
            data.remove("ilot_applets_mode");
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            sortir(&get_full_config_state())
        }
        "diag_info" => {
            let src = args.get(1).map(|s| s.as_str()).unwrap_or("quickshell");
            sortir(&get_diag_info(src))
        }
        "diag_restore" if args.len() >= 2 => {
            let fname = std::path::Path::new(&args[1])
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .trim();
            if !(fname.starts_with("backup_") && fname.ends_with(".tar.gz")) {
                return sortir(&json!({ "ok": false, "message": "Nom d'archive invalide" }));
            }
            let fpath = home_dir().join(".config/backups_env").join(fname);
            if !fpath.is_file() {
                return sortir(&json!({ "ok": false, "message": format!("Archive introuvable : {fname}") }));
            }
            let target = home_dir().join(".config");
            match Command::new("tar")
                .args(["-xzf", &fpath.to_string_lossy(), "-C", &target.to_string_lossy()])
                .output()
            {
                Ok(o) if o.status.success() => sortir(&json!({ "ok": true, "message": format!("Restauré : {fname}") })),
                Ok(o) => sortir(&json!({ "ok": false, "message": String::from_utf8_lossy(&o.stderr).trim() })),
                Err(e) => sortir(&json!({ "ok": false, "message": e.to_string() })),
            }
        }
        _ => sortir(&get_full_config_state()),
    }
}
