use crate::common::io::read_json_value;
use crate::common::paths::home_dir;
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn notes_path() -> PathBuf {
    home_dir().join(".cache/quickshell/quick_notes.json")
}

pub fn run_quick_notes(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("get");
    let path = notes_path();
    if action == "save" {
        let payload = env::var("QS_NOTES_JSON").unwrap_or_else(|_| "[]".to_string());
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        return if fs::write(&path, payload).is_ok() { 0 } else { 1 };
    }
    let val = read_json_value(&path);
    let arr = match val {
        Value::Array(a) if !a.is_empty() => Value::Array(a),
        _ => json!([{ "id": 1, "text": "" }]),
    };
    println!("{}", arr);
    0
}

pub fn run_wallpaper_list() -> i32 {
    let raw = env::var("QS_WP_DIR").unwrap_or_default();
    let trimmed = raw.trim();
    let dir = if trimmed.is_empty() {
        home_dir().join("Images/wallpapers")
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home_dir().join(rest)
    } else if trimmed == "~" {
        home_dir()
    } else {
        PathBuf::from(trimmed)
    };
    let exts = ["png", "jpg", "jpeg", "webp", "avif"];
    let mut entries: Vec<(String, String)> = Vec::new();
    if let Ok(rd) = fs::read_dir(&dir) {
        for ent in rd.flatten() {
            let p = ent.path();
            if !p.is_file() {
                continue;
            }
            let ext = p
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| s.to_ascii_lowercase())
                .unwrap_or_default();
            if !exts.contains(&ext.as_str()) {
                continue;
            }
            let name = p
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            entries.push((p.to_string_lossy().to_string(), name));
        }
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let out: Vec<Value> = entries
        .into_iter()
        .map(|(p, n)| json!({ "path": p, "name": n }))
        .collect();
    println!("{}", Value::Array(out));
    0
}

pub fn run_wl_copy(args: &[String]) -> i32 {
    let text = args.first().map(|s| s.as_str()).unwrap_or("");
    let Ok(mut child) = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return 1;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(text.as_bytes());
    }
    child.wait().map(|s| if s.success() { 0 } else { 1 }).unwrap_or(1)
}
