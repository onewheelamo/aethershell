use crate::common::io::{read_json_value, run_cmd, write_json_atomic};
use crate::common::paths::{core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const SHELL_BLUR_BEGIN: &str = "-- BEGIN shell-blur";
pub const SHELL_BLUR_END: &str = "-- END shell-blur";

pub const SHELL_BLUR_NAMESPACES: &[&str] = &[
    "shell-bar",
    "shell-bar-bas",
    "shell-bar-cote-gauche",
    "shell-bar-cote-droite",
    "shell-ilot-coin-top-left",
    "shell-ilot-coin-top-right",
    "shell-ilot-coin-bottom-left",
    "shell-ilot-coin-bottom-right",
    "shell-osd",
    "shell-config",
    "shell-onboarding",
    "shell-spotlight",
    "shell-spotlight-rest",
    "shell-cheatsheet",
    "shell-whichkey",
    "shell-overview",
    "shell-tray-menu",
    "shell-shotbar",
    "shell-menu-session",
    "shell-menu-widget",
    "shell-selecteur",
    "shell-notif-history",
];

pub fn hypr_dir() -> PathBuf {
    let core = core_dir();
    let live_qs = home_dir().join(".config/quickshell");
    if core.starts_with(&live_qs) {
        home_dir().join(".config/hypr")
    } else {
        core.parent().unwrap_or(&core).join("hypr_modular")
    }
}

pub fn hyprctl_silent(args: &[&str]) {
    let _ = Command::new("hyprctl")
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

pub fn get_hostname() -> String {
    if let Ok(h) = fs::read_to_string("/etc/hostname") {
        let s = h.trim();
        if !s.is_empty() {
            return s.to_string();
        }
    }
    if let Some(o) = run_cmd("hostname", &[]) {
        let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
        if !s.is_empty() {
            return s;
        }
    }
    "unknown".to_string()
}

pub fn is_laptop_system() -> bool {
    if let Ok(rd) = fs::read_dir("/sys/class/power_supply") {
        for ent in rd.flatten() {
            if let Some(name) = ent.file_name().to_str() {
                if name.starts_with("BAT") {
                    return true;
                }
            }
        }
    }
    false
}

pub fn distro_fichier() -> &'static str {
    if let Ok(txt) = fs::read_to_string("/etc/os-release") {
        let low = txt.to_ascii_lowercase();
        if low.contains("fedora") {
            return "fedora";
        }
        if low.contains("debian") || low.contains("ubuntu") {
            return "debian";
        }
    }
    "arch"
}

pub fn workspace_keys_for_layout(kb: &str) -> Vec<&'static str> {
    match kb {
        "fr" => vec!["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "minus", "egrave", "underscore", "ccedilla", "agrave"],
        "be" => vec!["ampersand", "eacute", "quotedbl", "apostrophe", "parenleft", "section", "egrave", "exclam", "ccedilla", "agrave"],
        _ => vec!["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    }
}

pub fn lua_str(value: &str) -> String {
    let mut out = String::from("\"");
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

pub fn lua_ident(alias: &str) -> String {
    const KW: &[&str] = &[
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if",
        "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
    ];
    let s: String = alias
        .trim()
        .to_ascii_lowercase()
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' })
        .collect();
    if s.is_empty() || s.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) || KW.contains(&s.as_str()) {
        String::new()
    } else {
        s
    }
}

pub fn get_kb_layout() -> String {
    let inp = hypr_dir().join("input.lua");
    if let Ok(txt) = fs::read_to_string(&inp) {
        let re = Regex::new(r#"kb_layout\s*=\s*"([^"]+)""#).unwrap();
        if let Some(c) = re.captures(&txt) {
            return c[1].to_string();
        }
    }
    let style = read_json_value(&core_dir().join("style_vars.json"));
    style
        .get("kb_layout")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("fr")
        .to_string()
}

pub fn set_kb_layout(layout: &str, mark_first_run_done: bool) -> bool {
    let clean: String = layout
        .trim()
        .to_ascii_lowercase()
        .chars()
        .filter(|c| c.is_ascii_alphabetic() || *c == '_' || *c == '-')
        .collect();
    let clean_layout = if clean.is_empty() { "fr".to_string() } else { clean };
    let ws_keys = workspace_keys_for_layout(&clean_layout);

    let input_path = hypr_dir().join("input.lua");
    if let Ok(txt) = fs::read_to_string(&input_path) {
        let re = Regex::new(r#"(kb_layout\s*=\s*")[^"]+(")"#).unwrap();
        let new_txt = re.replace_all(&txt, format!("${{1}}{clean_layout}${{2}}"));
        let _ = fs::write(&input_path, new_txt.as_ref());
    }

    let binds_path = hypr_dir().join("binds.lua");
    if let Ok(mut btxt) = fs::read_to_string(&binds_path) {
        for (idx, new_key) in ws_keys.iter().enumerate() {
            let ws_num = idx + 1;
            let p1 = format!(
                r#"(hl\.bind\(\s*mainMod\s*\.\.\s*"[^"]*\+\s*)([^"+]+)("\s*,\s*hl\.dsp\.focus\(\{{\s*workspace\s*=\s*{ws_num}\s*\}}\s*\))"#
            );
            let p2 = format!(
                r#"(hl\.bind\(\s*mainMod\s*\.\.\s*"[^"]*\+\s*)([^"+]+)("\s*,\s*hl\.dsp\.window\.move\(\{{\s*workspace\s*=\s*{ws_num}\b[^}}]*\}}\s*\))"#
            );
            for pat in [p1, p2] {
                if let Ok(re) = Regex::new(&pat) {
                    btxt = re.replace_all(&btxt, format!("${{1}}{new_key}${{3}}")).to_string();
                }
            }
        }
        let _ = fs::write(&binds_path, btxt);
    }

    let style_path = core_dir().join("style_vars.json");
    let mut style = match read_json_value(&style_path) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    style.insert("kb_layout".into(), json!(clean_layout));
    if mark_first_run_done {
        style.insert("first_run_completed".into(), json!(true));
    }
    let _ = write_json_atomic(&style_path, &Value::Object(style), 0o644);

    let eval_arg = format!("hl.config({{ input = {{ kb_layout = \"{clean_layout}\" }} }})");
    hyprctl_silent(&["eval", &eval_arg]);
    hyprctl_silent(&["reload"]);
    true
}

pub fn get_hypr_gaps() -> Value {
    let mut gaps_in = 2i64;
    let mut gaps_out = 8i64;
    let mut border_size = 2i64;
    if let Ok(txt) = fs::read_to_string(hypr_dir().join("general.lua")) {
        for (k, slot) in [
            ("gaps_in", &mut gaps_in),
            ("gaps_out", &mut gaps_out),
            ("border_size", &mut border_size),
        ] {
            if let Ok(re) = Regex::new(&format!(r"{k}\s*=\s*(\d+)")) {
                if let Some(c) = re.captures(&txt) {
                    if let Ok(v) = c[1].parse::<i64>() {
                        *slot = v;
                    }
                }
            }
        }
    }
    json!({ "gaps_in": gaps_in, "gaps_out": gaps_out, "border_size": border_size })
}

pub fn get_hypr_rounding() -> i64 {
    if let Ok(txt) = fs::read_to_string(hypr_dir().join("general.lua")) {
        let re = Regex::new(r"\brounding\s*=\s*(\d+)").unwrap();
        if let Some(c) = re.captures(&txt) {
            if let Ok(v) = c[1].parse::<i64>() {
                return v;
            }
        }
    }
    read_json_value(&core_dir().join("style_vars.json"))
        .get("hypr_rounding")
        .and_then(|v| v.as_i64())
        .unwrap_or(2)
}

pub fn get_hypr_rounding_power() -> i64 {
    if let Ok(txt) = fs::read_to_string(hypr_dir().join("general.lua")) {
        let re = Regex::new(r"\brounding_power\s*=\s*([\d.]+)").unwrap();
        if let Some(c) = re.captures(&txt) {
            if let Ok(v) = c[1].parse::<f64>() {
                return (v.round() as i64).clamp(1, 2);
            }
        }
    }
    let v = read_json_value(&core_dir().join("style_vars.json"))
        .get("hypr_rounding_power")
        .and_then(|v| v.as_f64())
        .unwrap_or(2.0);
    (v.round() as i64).clamp(1, 2)
}

pub fn update_hypr_gaps(key: &str, val: &str) -> bool {
    if !matches!(key, "gaps_in" | "gaps_out" | "border_size") {
        return false;
    }
    let ival = (val.parse::<f64>().unwrap_or(0.0) as i64).clamp(0, 60);
    let gen_path = hypr_dir().join("general.lua");
    if let Ok(txt) = fs::read_to_string(&gen_path) {
        if let Ok(re) = Regex::new(&format!(r"({key}\s*=\s*)\d+")) {
            let new_txt = re.replace_all(&txt, format!("${{1}}{ival}"));
            let _ = fs::write(&gen_path, new_txt.as_ref());
        }
    }
    hyprctl_silent(&["eval", &format!("hl.config({{ general = {{ {key} = {ival} }} }})")]);
    true
}

pub fn apply_shell_blur(style: &Map<String, Value>, widgets: &[Value]) -> bool {
    let enabled = style
        .get("shell_blur_enabled")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let alpha = style
        .get("shell_blur_alpha")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.3)
        .clamp(0.0, 1.0);
    let popups = style
        .get("shell_blur_popups")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let mut all_ns: Vec<String> = SHELL_BLUR_NAMESPACES.iter().map(|s| s.to_string()).collect();
    for w in widgets {
        let blur = w.get("blur").and_then(|v| v.as_bool()).unwrap_or(true);
        if blur {
            if let Some(id) = w.get("id").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
                let ns = format!("shell-widget-{id}");
                if !all_ns.contains(&ns) {
                    all_ns.push(ns);
                }
            }
        }
    }
    let ns_list: Vec<String> = all_ns.iter().map(|s| format!("\"{s}\"")).collect();
    let block = [
        SHELL_BLUR_BEGIN.to_string(),
        "local shell_blur = {".to_string(),
        format!("    enabled = {},  -- flou derrière les surfaces du shell", enabled),
        format!("    alpha   = {:.2},   -- sous ce seuil d'opacité, pas de flou (ignore_alpha)", alpha),
        format!("    popups  = {},  -- flou derrière les popups ancrés (calendrier, wifi…)", popups),
        "}".to_string(),
        "if shell_blur.enabled then".to_string(),
        format!("    for _, ns in ipairs({{ {} }}) do", ns_list.join(", ")),
        "        hl.layer_rule({".to_string(),
        "            match        = { namespace = ns },".to_string(),
        "            blur         = true,".to_string(),
        "            blur_popups  = shell_blur.popups,".to_string(),
        "            ignore_alpha = shell_blur.alpha,".to_string(),
        "        })".to_string(),
        "    end".to_string(),
        "end".to_string(),
        SHELL_BLUR_END.to_string(),
    ]
    .join("\n");

    let gen_path = hypr_dir().join("general.lua");
    let Ok(txt) = fs::read_to_string(&gen_path) else {
        return false;
    };
    let pat = format!(r"(?s){}.*?{}", regex::escape(SHELL_BLUR_BEGIN), regex::escape(SHELL_BLUR_END));
    let Ok(re) = Regex::new(&pat) else {
        return false;
    };
    if !re.is_match(&txt) {
        return false;
    }
    let new_txt = re.replace(&txt, block.as_str()).to_string();
    if new_txt != txt {
        if fs::write(&gen_path, &new_txt).is_ok() {
            hyprctl_silent(&["reload"]);
        }
    }
    true
}

pub fn get_primary_monitor(hostname: &str) -> String {
    let style = read_json_value(&core_dir().join("style_vars.json"));
    if let Some(p) = style.get("primary_monitor").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
        return p.to_string();
    }
    let mut hw = hypr_dir().join(format!("hardware-{hostname}.lua"));
    if !hw.exists() {
        hw = hypr_dir().join(format!("hardware-{}.lua", distro_fichier()));
    }
    if let Ok(txt) = fs::read_to_string(&hw) {
        let re = Regex::new(r#"hl\.workspace_rule\(\{[^{}]*workspace\s*=\s*["']1["'][^{}]*monitor\s*=\s*["']([^"']+)["']"#).unwrap();
        if let Some(c) = re.captures(&txt) {
            return c[1].to_string();
        }
    }
    if is_laptop_system() { "eDP-1".to_string() } else { "HDMI-A-1".to_string() }
}

pub fn filter_clean_modes(avail: &[Value]) -> Vec<String> {
    let re = Regex::new(r"^(\d+)x(\d+)(?:@([\d.]+)(?:Hz)?)?$").unwrap();
    let mut seen = HashSet::new();
    let mut parsed: Vec<(u32, u32, u32)> = Vec::new();
    for m in avail {
        let Some(s) = m.as_str() else { continue };
        let Some(c) = re.captures(s) else { continue };
        let w = c[1].parse::<u32>().unwrap_or(0);
        let h = c[2].parse::<u32>().unwrap_or(0);
        if h < 720 {
            continue;
        }
        let hz = c.get(3).and_then(|g| g.as_str().parse::<f64>().ok()).unwrap_or(60.0).round() as u32;
        if seen.insert((w, h, hz)) {
            parsed.push((w, h, hz));
        }
    }
    parsed.sort_by(|a, b| b.cmp(a));
    let mut modes: Vec<String> = parsed.into_iter().map(|(w, h, hz)| format!("{w}x{h}@{hz}")).collect();
    if !modes.iter().any(|m| m == "preferred") {
        modes.insert(0, "preferred".to_string());
    }
    modes
}

pub fn get_monitors_info() -> Value {
    let host = get_hostname();
    let prim = get_primary_monitor(&host);
    let mut monitors = Vec::new();
    if let Some(o) = run_cmd("hyprctl", &["monitors", "-j"]) {
        if let Ok(Value::Array(raw)) = serde_json::from_slice::<Value>(&o.stdout) {
            for m in raw {
                let name = m.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let avail = m.get("availableModes").and_then(|v| v.as_array()).cloned().unwrap_or_default();
                monitors.push(json!({
                    "name": name,
                    "description": m.get("description").and_then(|v| v.as_str()).unwrap_or(""),
                    "width": m.get("width").and_then(|v| v.as_i64()).unwrap_or(1920),
                    "height": m.get("height").and_then(|v| v.as_i64()).unwrap_or(1080),
                    "refreshRate": m.get("refreshRate").and_then(|v| v.as_f64()).unwrap_or(60.0).round() as i64,
                    "x": m.get("x").and_then(|v| v.as_i64()).unwrap_or(0),
                    "y": m.get("y").and_then(|v| v.as_i64()).unwrap_or(0),
                    "scale": m.get("scale").and_then(|v| v.as_f64()).unwrap_or(1.0),
                    "transform": m.get("transform").and_then(|v| v.as_i64()).unwrap_or(0),
                    "availableModes": filter_clean_modes(&avail),
                    "is_primary": name == prim,
                }));
            }
        }
    }
    let tz = run_cmd("timedatectl", &["show", "-p", "Timezone", "--value"])
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "Europe/Paris".to_string());
    let ntp = run_cmd("timedatectl", &["show", "-p", "NTPSynchronized", "--value"])
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "yes")
        .unwrap_or(false);

    json!({
        "hostname": host,
        "is_laptop": is_laptop_system(),
        "monitors": monitors,
        "primary": prim,
        "timezone": tz,
        "ntp": ntp,
    })
}

pub fn set_primary_monitor(output_name: &str) -> bool {
    let valid = Regex::new(r"^[A-Za-z0-9._-]+$").unwrap();
    if !valid.is_match(output_name) {
        return false;
    }
    let style_path = core_dir().join("style_vars.json");
    let mut style = match read_json_value(&style_path) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    style.insert("primary_monitor".into(), json!(output_name));
    let _ = write_json_atomic(&style_path, &Value::Object(style), 0o644);

    let host = get_hostname();
    let mut hw = hypr_dir().join(format!("hardware-{host}.lua"));
    if !hw.exists() {
        hw = hypr_dir().join(format!("hardware-{}.lua", distro_fichier()));
    }
    let kanjis = [(1, "一"), (2, "二"), (3, "三"), (4, "四"), (5, "五")];
    let mut rules = vec![format!("-- Workspaces assignés à l'écran principal ({output_name})")];
    for (ws, kanji) in kanjis {
        let dflt = if ws == 1 { ", default = true" } else { "" };
        rules.push(format!(
            "hl.workspace_rule({{ workspace = \"{ws}\", monitor = \"{output_name}\"{dflt}, persistent = true, default_name = \"{kanji}\" }})"
        ));
    }
    let new_block = rules.join("\n");
    if let Ok(txt) = fs::read_to_string(&hw) {
        let rule_re = Regex::new(r"-- Workspaces assignés à l'écran principal[^\n]*\n(?:hl\.workspace_rule\([^\n]+\)\n?)+").unwrap();
        let out = if rule_re.is_match(&txt) {
            rule_re.replace(&txt, new_block.as_str()).to_string()
        } else {
            let indiv_re = Regex::new(r#"(?:hl\.workspace_rule\(\{[^{}]*workspace\s*=\s*["'][1-5]["'][^{}]*\}\)\n?)+"#).unwrap();
            if indiv_re.is_match(&txt) {
                indiv_re.replace(&txt, format!("{new_block}\n").as_str()).to_string()
            } else {
                format!("{}\n\n{new_block}\n", txt.trim_end())
            }
        };
        let _ = fs::write(&hw, out);
    }
    hyprctl_silent(&["reload"]);
    hyprctl_silent(&["eval", &format!("hl.dsp.focus({{ monitor = \"{output_name}\" }})")]);
    hyprctl_silent(&["eval", "hl.dsp.focus({ workspace = 1 })"]);
    true
}

pub fn set_monitor_profile(profile: &str) -> bool {
    let mut ext_mon = String::from("DP-1");
    if let Some(o) = run_cmd("hyprctl", &["monitors", "all", "-j"]) {
        if let Ok(Value::Array(arr)) = serde_json::from_slice::<Value>(&o.stdout) {
            for m in arr {
                if let Some(name) = m.get("name").and_then(|v| v.as_str()) {
                    if !name.is_empty() && !name.starts_with("eDP") {
                        ext_mon = name.to_string();
                        break;
                    }
                }
            }
        }
    }
    let (cmds, target_prim): (Vec<String>, &str) = match profile {
        "dual" => (
            vec![
                format!("hl.monitor({{ output = \"{ext_mon}\", disabled = false, mode = \"1920x1080@60\", position = \"0x0\", scale = 1, bitdepth = 10 }})"),
                "hl.monitor({ output = \"eDP-1\", disabled = false, mode = \"preferred\", position = \"1920x0\", scale = 1, transform = 0 })".into(),
                format!("hl.dsp.focus({{ monitor = \"{ext_mon}\" }})"),
                "hl.dsp.focus({ workspace = 1 })".into(),
            ],
            &ext_mon,
        ),
        "tv" => (
            vec![
                format!("hl.monitor({{ output = \"{ext_mon}\", disabled = false, mode = \"1920x1080@60\", position = \"0x0\", scale = 1, bitdepth = 10 }})"),
                "hl.monitor({ output = \"eDP-1\", disabled = true })".into(),
                format!("hl.dsp.focus({{ monitor = \"{ext_mon}\" }})"),
                "hl.dsp.focus({ workspace = 1 })".into(),
            ],
            &ext_mon,
        ),
        "laptop" => (
            vec![
                format!("hl.monitor({{ output = \"{ext_mon}\", disabled = true }})"),
                "hl.monitor({ output = \"eDP-1\", disabled = false, mode = \"preferred\", position = \"0x0\", scale = 1, transform = 0 })".into(),
                "hl.dsp.focus({ monitor = \"eDP-1\" })".into(),
                "hl.dsp.focus({ workspace = 1 })".into(),
            ],
            "eDP-1",
        ),
        _ => return false,
    };
    for c in cmds {
        hyprctl_silent(&["eval", &c]);
    }
    let style_path = core_dir().join("style_vars.json");
    let mut style = match read_json_value(&style_path) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    if style.get("primary_monitor").and_then(|v| v.as_str()) != Some(target_prim) {
        style.insert("primary_monitor".into(), json!(target_prim));
        let _ = write_json_atomic(&style_path, &Value::Object(style), 0o644);
    }
    true
}

pub fn set_monitor_mode(output_name: &str, mode_str: &str, scale_str: &str) -> bool {
    let valid_out = Regex::new(r"^[A-Za-z0-9._-]+$").unwrap();
    if !valid_out.is_match(output_name) {
        return false;
    }
    let scale = scale_str.parse::<f64>().unwrap_or(1.0).clamp(0.5, 4.0);
    let mut pos = "0x0".to_string();
    if let Some(o) = run_cmd("hyprctl", &["monitors", "-j"]) {
        if let Ok(Value::Array(arr)) = serde_json::from_slice::<Value>(&o.stdout) {
            for m in arr {
                if m.get("name").and_then(|v| v.as_str()) == Some(output_name) {
                    let x = m.get("x").and_then(|v| v.as_i64()).unwrap_or(0);
                    let y = m.get("y").and_then(|v| v.as_i64()).unwrap_or(0);
                    pos = format!("{x}x{y}");
                    break;
                }
            }
        }
    }
    hyprctl_silent(&[
        "eval",
        &format!("hl.monitor({{ output = \"{output_name}\", mode = \"{mode_str}\", position = \"{pos}\", scale = {scale} }})"),
    ]);

    let host = get_hostname();
    let mut hw = hypr_dir().join(format!("hardware-{host}.lua"));
    if !hw.exists() {
        hw = hypr_dir().join(format!("hardware-{}.lua", distro_fichier()));
    }
    if let Ok(txt) = fs::read_to_string(&hw) {
        let block_re = Regex::new(&format!(
            r#"hl\.monitor\(\{{[^{{}}]*?output\s*=\s*"{}"[^{{}}]*?\}}\)"#,
            regex::escape(output_name)
        ))
        .unwrap();
        let new_txt = block_re
            .replace_all(&txt, |caps: &regex::Captures| {
                let mut block = caps[0].to_string();
                let mode_re = Regex::new(r#"(\bmode\s*=\s*)"[^"]*""#).unwrap();
                block = mode_re
                    .replace(&block, format!("${{1}}\"{mode_str}\""))
                    .to_string();
                let scale_re = Regex::new(r"(\bscale\s*=\s*)[0-9.]+").unwrap();
                if scale_re.is_match(&block) {
                    block = scale_re
                        .replace(&block, format!("${{1}}{scale}"))
                        .to_string();
                } else if let Some(stripped) = block.strip_suffix("})") {
                    block = format!("{}, scale = {scale} }})", stripped.trim_end());
                }
                block
            })
            .to_string();
        let _ = fs::write(&hw, new_txt);
    }
    true
}

pub fn set_screen_rotation(transform_id: &str) -> bool {
    let t = (transform_id.parse::<i64>().unwrap_or(0)).rem_euclid(4);
    hyprctl_silent(&["eval", &format!("hl.monitor({{ output = \"eDP-1\", transform = {t} }})")]);
    true
}

fn parse_binds_file(path: &Path, default_category: &str) -> Vec<Value> {
    let Ok(txt) = fs::read_to_string(path) else {
        return Vec::new();
    };
    let mut binds = Vec::new();
    let mut category = default_category.to_string();
    let key_re = Regex::new(r#""\s*\+\s*([^"]+)""#).unwrap();
    let dsp_re = Regex::new(r"hl\.dsp\.([a-zA-Z0-9_.]+)\(").unwrap();
    let desc_re = Regex::new(r#"description\s*=\s*"([^"]*)""#).unwrap();
    let arg_re = Regex::new(r"hl\.dsp\.[a-zA-Z0-9_.]+\((.*)\)").unwrap();
    let ess_re = Regex::new(r"--\s*essentiel").unwrap();

    for line in txt.lines() {
        let stripped = line.trim();
        if let Some(rest) = stripped.strip_prefix("--:") {
            category = rest.trim().to_string();
            continue;
        }
        if stripped.starts_with("--") || !stripped.starts_with("hl.bind(") {
            continue;
        }
        let Some(kc) = key_re.captures(stripped) else {
            continue;
        };
        let key = kc[1].trim().to_string();
        if key.is_empty() {
            continue;
        }
        let dsp = dsp_re.captures(stripped).map(|c| c[1].to_string()).unwrap_or_default();
        let desc = desc_re.captures(stripped).map(|c| c[1].to_string()).unwrap_or_default();
        let mut target = arg_re
            .captures(stripped)
            .map(|c| c[1].trim().trim_matches('"').trim_matches('\'').to_string())
            .unwrap_or_default();
        if let Some((before, _)) = target.split_once(", {") {
            target = before.trim().to_string();
        }
        binds.push(json!({
            "mod": "SUPER",
            "key": key,
            "dispatcher": dsp,
            "target": target,
            "description": desc,
            "essentiel": ess_re.is_match(stripped),
            "category": category,
        }));
    }
    binds
}

pub fn get_binds_list() -> Vec<Value> {
    let hdir = hypr_dir();
    let mut binds = parse_binds_file(&hdir.join("binds.lua"), "");
    let udir = hdir.join("user");
    if let Ok(rd) = fs::read_dir(&udir) {
        let mut files: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("lua"))
            .collect();
        files.sort();
        for f in files {
            binds.extend(parse_binds_file(&f, "Personnel"));
        }
    }
    binds
}

pub fn set_keybind(key_combo: &str, command_or_var: &str) -> bool {
    let key_clean = key_combo.trim();
    let cmd_clean = command_or_var.trim();
    let valid_re = Regex::new(r"^[A-Za-z0-9_:+ -]{1,60}$").unwrap();
    if key_clean.is_empty() || cmd_clean.is_empty() || !valid_re.is_match(key_clean) {
        return false;
    }
    let mut known_vars: HashSet<String> = [
        "terminal",
        "music_player",
        "browser1",
        "browser2",
        "file_explorer",
        "editor",
    ]
    .into_iter()
    .map(|s| s.to_string())
    .collect();
    if let Value::Object(app_data) = read_json_value(&core_dir().join("app_vars.json")) {
        for k in app_data.keys() {
            let id = lua_ident(k);
            if !id.is_empty() {
                known_vars.insert(id);
            }
        }
    }
    let rhs = if known_vars.contains(cmd_clean) {
        format!("hl.dsp.exec_cmd({cmd_clean})")
    } else {
        format!("hl.dsp.exec_cmd({})", lua_str(cmd_clean))
    };
    let new_line = format!("hl.bind(mainMod .. \" + {key_clean}\", {rhs})");
    let lhs_prefix = format!("hl.bind(mainMod .. \" + {key_clean}\"");

    let path = hypr_dir().join("user/binds.lua");
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let mut lines: Vec<String> = if let Ok(txt) = fs::read_to_string(&path) {
        txt.lines().map(|l| l.to_string()).collect()
    } else {
        vec!["local mainMod = mainMod or \"SUPER\"".to_string()]
    };
    let mut updated = false;
    for l in &mut lines {
        if l.contains(&lhs_prefix) {
            *l = new_line.clone();
            updated = true;
            break;
        }
    }
    if !updated {
        lines.push(new_line);
    }
    if fs::write(&path, lines.join("\n") + "\n").is_ok() {
        hyprctl_silent(&["reload"]);
        true
    } else {
        false
    }
}

pub fn remove_keybind(key_combo: &str) -> bool {
    let key_clean = key_combo.trim();
    let valid_re = Regex::new(r"^[A-Za-z0-9_:+ -]{1,60}$").unwrap();
    if !valid_re.is_match(key_clean) {
        return false;
    }
    let path = hypr_dir().join("user/binds.lua");
    let Ok(txt) = fs::read_to_string(&path) else {
        return false;
    };
    let lhs_prefix = format!("hl.bind(mainMod .. \" + {key_clean}\"");
    let kept: Vec<&str> = txt.lines().filter(|l| !l.contains(&lhs_prefix)).collect();
    if fs::write(&path, kept.join("\n") + "\n").is_ok() {
        hyprctl_silent(&["reload"]);
        true
    } else {
        false
    }
}

pub fn sync_programs_lua(app_data: &Map<String, Value>) {
    let get_s = |k: &str, d: &str| {
        app_data
            .get(k)
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(d)
            .to_string()
    };
    let mapping = [
        ("terminal", get_s("Terminal", "kitty")),
        ("music_player", get_s("Music", "strawberry")),
        ("browser1", get_s("Browser", "firefox")),
        ("browser2", get_s("Browser2", "zen-browser")),
        ("file_explorer", get_s("Files", "thunar")),
        ("editor", get_s("Editor", "code")),
    ];
    let mut lines = vec![
        "-- ~/.config/hypr/programs.lua".to_string(),
        "-- Generated from core/app_vars.json by as-core".to_string(),
    ];
    let mut mapped_keys = HashSet::new();
    for (k, v) in &mapping {
        mapped_keys.insert(*k);
        lines.push(format!("{k} = {}", lua_str(v)));
    }
    for (alias, val) in app_data {
        let safe = lua_ident(alias);
        if !safe.is_empty() && !mapped_keys.contains(safe.as_str()) {
            if let Some(cmd) = val.as_str() {
                lines.push(format!("{safe} = {}", lua_str(cmd)));
            }
        }
    }
    let _ = fs::write(hypr_dir().join("programs.lua"), lines.join("\n") + "\n");
}

pub fn sync_autostart_lua(entries: &[Value]) -> bool {
    const CORE_NAMES: &[&str] = &[
        "Hermes (canal d'approbation)",
        "Quickshell (barre)",
        "Hypridle (inactivité)",
        "awww-daemon (wallpaper, si Noctalia absent)",
        "Agent Polkit",
        "Focus de l'invite polkit",
        "Presse-papiers (veilleurs cliphist)",
    ];
    let hdir = hypr_dir();
    let _ = fs::create_dir_all(&hdir);

    let mut core_lines = vec![
        "# Généré par as-core — ne pas éditer à la main.".to_string(),
        "# Source de vérité : core/autostart.json (socle shell).".to_string(),
    ];
    let mut user_entries = Vec::new();
    for e in entries {
        let name = e.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let cmd = e.get("cmd").and_then(|v| v.as_str()).unwrap_or("").trim();
        let enabled = e.get("enabled").and_then(|v| v.as_bool()).unwrap_or(true);
        if CORE_NAMES.contains(&name) {
            if !cmd.is_empty() {
                core_lines.push(if enabled { cmd.to_string() } else { format!("# {cmd}") });
            }
        } else {
            user_entries.push((cmd.to_string(), enabled));
        }
    }
    if fs::write(hdir.join("autostart_cmds.txt"), core_lines.join("\n") + "\n").is_err() {
        return false;
    }

    let user_dir = hdir.join("user");
    let _ = fs::create_dir_all(&user_dir);
    let user_path = user_dir.join("autostart.txt");
    let begin_tag = "# >>> panneau";
    let end_tag = "# <<< panneau";
    let mut preserved: Vec<String> = if let Ok(txt) = fs::read_to_string(&user_path) {
        let mut out = Vec::new();
        let mut in_block = false;
        for raw in txt.lines() {
            let s = raw.trim();
            if s == begin_tag { in_block = true; continue; }
            if s == end_tag { in_block = false; continue; }
            if !in_block { out.push(raw.to_string()); }
        }
        out
    } else {
        vec![
            "# ~/.config/hypr/user/autostart.txt".into(),
            "# Programmes personnels à lancer au démarrage de session Hyprland.".into(),
            "# Une commande par ligne (les lignes vides et commençant par # sont ignorées).".into(),
            "# Ce fichier n'est jamais écrasé ni régénéré par install.sh.".into(),
        ]
    };
    while preserved.last().map(|l| l.trim().is_empty()).unwrap_or(false) {
        preserved.pop();
    }
    if !preserved.is_empty() {
        preserved.push(String::new());
    }
    preserved.push(begin_tag.to_string());
    for (cmd, enabled) in user_entries {
        if !cmd.is_empty() {
            preserved.push(if enabled { cmd } else { format!("# {cmd}") });
        }
    }
    preserved.push(end_tag.to_string());
    let _ = fs::write(&user_path, preserved.join("\n") + "\n");
    true
}
