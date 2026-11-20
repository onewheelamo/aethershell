use crate::common::io::read_json_value;
use crate::common::lock::FileLock;
use crate::common::paths::{cache_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_ENTRIES: usize = 200;
const MAX_BODY: usize = 2000;
const MAX_SUMMARY: usize = 500;

fn history_file() -> PathBuf {
    cache_dir().join("quickshell").join("notifications-history.jsonl")
}

fn borne(s: &str, limit: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= limit {
        s.to_string()
    } else {
        let mut out: String = chars[..limit].iter().collect();
        out.push('…');
        out
    }
}

fn read_all() -> Vec<Value> {
    let Ok(txt) = fs::read_to_string(history_file()) else {
        return vec![];
    };
    let mut out = Vec::new();
    for line in txt.lines() {
        let t = line.trim();
        if t.is_empty() { continue; }
        if let Ok(Value::Object(m)) = serde_json::from_str::<Value>(t) {
            if m.get("id").map(|v| !v.is_null()).unwrap_or(false) {
                out.push(Value::Object(m));
            }
        }
    }
    out
}

fn write_all(entries: &[Value]) -> io::Result<()> {
    let p = history_file();
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut tmp = p.clone();
    tmp.set_extension(format!("tmp.{}", std::process::id()));
    {
        let mut f = OpenOptions::new().create(true).write(true).truncate(true).open(&tmp)?;
        for e in entries {
            if let Ok(line) = serde_json::to_string(e) {
                writeln!(f, "{line}")?;
            }
        }
        f.sync_all()?;
    }
    fs::rename(&tmp, &p)?;
    Ok(())
}

fn add_entry(mut entry: Map<String, Value>) -> String {
    let hf = history_file();
    let body = entry.get("body").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let summary = entry.get("summary").and_then(|v| v.as_str()).unwrap_or("").to_string();
    entry.insert("body".into(), json!(borne(&body, MAX_BODY)));
    entry.insert("summary".into(), json!(borne(&summary, MAX_SUMMARY)));

    let _lock = FileLock::acquire(&hf);
    let mut entries = read_all();
    let ids: HashSet<String> = entries
        .iter()
        .filter_map(|e| {
            e.get("id").map(|v| match v {
                Value::String(s) => s.clone(),
                other => other.to_string(),
            })
        })
        .collect();
    let mut ident = entry
        .get("id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if ident.is_empty() || ids.contains(&ident) {
        let base = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis().to_string())
            .unwrap_or_else(|_| "0".into());
        ident = base.clone();
        let mut n = 1;
        while ids.contains(&ident) {
            n += 1;
            ident = format!("{base}-{n}");
        }
        entry.insert("id".into(), json!(ident));
    }
    entries.push(Value::Object(entry));
    if entries.len() > MAX_ENTRIES {
        entries = entries.split_off(entries.len() - MAX_ENTRIES);
    }
    let _ = write_all(&entries);
    ident
}

pub fn run_history(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("list");
    let hf = history_file();
    match action {
        "add" => {
            let mut payload = String::new();
            let _ = io::stdin().read_to_string(&mut payload);
            let Ok(Value::Object(entry)) = serde_json::from_str::<Value>(payload.trim()) else {
                eprintln!("ajout refusé : JSON illisible");
                return 1;
            };
            let ident = add_entry(entry);
            println!("{ident}");
            0
        }
        "list" => {
            let mut entries = read_all();
            entries.reverse();
            if let Ok(s) = serde_json::to_string(&entries) {
                println!("{s}");
            }
            0
        }
        "count" => {
            println!("{}", read_all().len());
            0
        }
        "delete" if args.len() > 1 => {
            let target = &args[1];
            let _lock = FileLock::acquire(&hf);
            let entries = read_all();
            let before = entries.len();
            let kept: Vec<Value> = entries
                .into_iter()
                .filter(|e| {
                    let eid = e.get("id").map(|v| match v {
                        Value::String(s) => s.clone(),
                        other => other.to_string(),
                    }).unwrap_or_default();
                    &eid != target
                })
                .collect();
            let removed = before - kept.len();
            let _ = write_all(&kept);
            println!("{removed}");
            0
        }
        "clear" => {
            let _lock = FileLock::acquire(&hf);
            let _ = write_all(&[]);
            println!("ok");
            0
        }
        _ => 2,
    }
}

const HINTS_OUVERTURE: &[&str] = &["x-aethershell-open", "x-amo-open"]; // neutralite:ok — ancien nom de hint conservé pour compatibilité
const VIDEO_EXTS: &[&str] = &["mp4", "mkv", "webm", "mov", "m4v", "avi", "m2ts", "mpg", "mpeg"];
const IMAGE_EXTS: &[&str] = &["png", "jpg", "jpeg", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff"];
const TEXT_EXTS: &[&str] = &[
    "txt", "md", "log", "json", "yaml", "yml", "toml", "conf", "ini", "sh", "py", "qml", "lua",
    "desktop", "csv", "org",
];
const TRAILING_CHARS: &[char] = &['.', ',', ';', ':', '!', '?', '…', '»'];

fn format_local_now() -> String {
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        format!(
            "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    }
}

fn url_unquote(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                if let Ok(b) = u8::from_str_radix(hex, 16) {
                    out.push(b);
                    i += 3;
                    continue;
                }
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn shlex_split(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    let mut in_single = false;
    let mut in_double = false;
    let mut escape = false;
    let mut has_token = false;

    for ch in s.chars() {
        if escape {
            cur.push(ch);
            escape = false;
            has_token = true;
            continue;
        }
        if in_single {
            if ch == '\'' {
                in_single = false;
            } else {
                cur.push(ch);
            }
            has_token = true;
            continue;
        }
        if in_double {
            if ch == '\\' {
                escape = true;
            } else if ch == '"' {
                in_double = false;
            } else {
                cur.push(ch);
            }
            has_token = true;
            continue;
        }
        match ch {
            '\\' => {
                escape = true;
                has_token = true;
            }
            '\'' => {
                in_single = true;
                has_token = true;
            }
            '"' => {
                in_double = true;
                has_token = true;
            }
            c if c.is_whitespace() => {
                if has_token {
                    out.push(std::mem::take(&mut cur));
                    has_token = false;
                }
            }
            c => {
                cur.push(c);
                has_token = true;
            }
        }
    }
    if has_token {
        out.push(cur);
    }
    out
}

fn shlex_quote(s: &str) -> String {
    if !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"@%+=:,./-_".contains(&b))
    {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

fn expand_tilde(path: &str) -> String {
    if path == "~" {
        return home_dir().to_string_lossy().to_string();
    }
    if let Some(rest) = path.strip_prefix("~/") {
        return home_dir().join(rest).to_string_lossy().to_string();
    }
    path.to_string()
}

fn path_kind(path: &str) -> &'static str {
    let p = expand_tilde(path);
    if Path::new(&p).is_dir() {
        return "folder";
    }
    let ext = Path::new(&p)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if VIDEO_EXTS.contains(&ext.as_str()) {
        return "video";
    }
    if IMAGE_EXTS.contains(&ext.as_str()) {
        return "image";
    }
    if TEXT_EXTS.contains(&ext.as_str()) {
        return "text";
    }
    if ext.is_empty() {
        return "folder";
    }
    ""
}

fn candidates(text: &str) -> Vec<String> {
    let file_uri_re = Regex::new(r#"file://[^\s"'<>«»]+"#).unwrap();
    let path_re = Regex::new(r#"(?:^|[\s(\[«"'])((?:~|/)[^\s"'<>()\[\]«»]+)"#).unwrap();
    let mut out = Vec::new();
    for m in file_uri_re.find_iter(text) {
        let raw = m.as_str();
        let no_scheme = raw.strip_prefix("file://").unwrap_or(raw);
        let no_q = no_scheme.split('?').next().unwrap_or(no_scheme);
        let no_f = no_q.split('#').next().unwrap_or(no_q);
        out.push(url_unquote(no_f));
    }
    for cap in path_re.captures_iter(text) {
        if let Some(m) = cap.get(1) {
            out.push(m.as_str().trim_end_matches(TRAILING_CHARS).to_string());
        }
    }
    out
}

fn alias_command(alias_cmd: &str, target: &str) -> Vec<String> {
    if target.is_empty() {
        return shlex_split(alias_cmd);
    }
    vec![
        "sh".to_string(),
        "-c".to_string(),
        format!("{} \"$1\"", alias_cmd),
        "_".to_string(),
        target.to_string(),
    ]
}

fn terminal_command(term: &str, run: &str) -> Vec<String> {
    let mut parts = if term.is_empty() {
        vec!["ghostty".to_string()]
    } else {
        shlex_split(term)
    };
    if parts.is_empty() {
        parts.push("ghostty".to_string());
    }
    let binary = Path::new(&parts[0])
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    if binary == "kitty" {
        parts.extend(shlex_split(run));
    } else {
        parts.push("-e".to_string());
        parts.extend(shlex_split(run));
    }
    parts
}

fn sans_ext(valeur: &str) -> String {
    let v = valeur.trim().to_ascii_lowercase();
    v.strip_suffix(".desktop").unwrap_or(&v).to_string()
}

fn desktop_entry_for<'a>(index: &'a [Value], desktop: &str, app_name: &str) -> Option<&'a Value> {
    let wanted = sans_ext(desktop);
    if !wanted.is_empty() {
        for entry in index {
            let d = sans_ext(entry.get("desktop").and_then(|v| v.as_str()).unwrap_or(""));
            if d == wanted {
                return Some(entry);
            }
        }
        for entry in index {
            let cand = sans_ext(entry.get("desktop").and_then(|v| v.as_str()).unwrap_or(""));
            if !cand.is_empty() && (cand.starts_with(&wanted) || wanted.starts_with(&cand)) {
                return Some(entry);
            }
        }
    }
    if !app_name.is_empty() {
        let wanted_name = sans_ext(app_name);
        for entry in index {
            let n = sans_ext(entry.get("name").and_then(|v| v.as_str()).unwrap_or(""));
            if n == wanted_name {
                return Some(entry);
            }
        }
        let app_low = app_name.to_ascii_lowercase();
        for entry in index {
            let nom = sans_ext(entry.get("name").and_then(|v| v.as_str()).unwrap_or(""));
            if !nom.is_empty() && (nom.contains(&app_low) || app_low.contains(&nom)) {
                return Some(entry);
            }
        }
    }
    None
}

fn focus_motifs(entry: Option<&Value>, desktop: &str, app_name: &str) -> Vec<String> {
    let mut motifs = Vec::new();
    if let Some(e) = entry {
        let exec = e.get("exec").and_then(|v| v.as_str()).unwrap_or("");
        if let Some(first) = exec.split_whitespace().next() {
            if let Some(base) = Path::new(first).file_name().and_then(|s| s.to_str()) {
                motifs.push(base.to_string());
            }
        }
        motifs.push(sans_ext(e.get("desktop").and_then(|v| v.as_str()).unwrap_or("")));
        motifs.push(sans_ext(e.get("name").and_then(|v| v.as_str()).unwrap_or("")));
    }
    motifs.push(sans_ext(desktop));
    motifs.push(sans_ext(app_name));

    let mut vus = HashSet::new();
    let mut out = Vec::new();
    for m in motifs {
        let t = m.trim().to_string();
        if t.chars().count() < 3 || vus.contains(&t) {
            continue;
        }
        vus.insert(t.clone());
        out.push(t);
        if out.len() >= 4 {
            break;
        }
    }
    out
}

fn resolve_target(req: &Value) -> Map<String, Value> {
    let targets = read_json_value(&core_dir().join("notif_targets.json"));
    let apps = read_json_value(&core_dir().join("app_vars.json"));
    let index_val = read_json_value(&core_dir().join("app_index.json"));
    let index = index_val.as_array().map(|a| a.as_slice()).unwrap_or(&[]);

    let summary = req.get("summary").and_then(|v| v.as_str()).unwrap_or("");
    let body = req.get("body").and_then(|v| v.as_str()).unwrap_or("");
    let app_name = req.get("appName").and_then(|v| v.as_str()).unwrap_or("");
    let desktop = req.get("desktopEntry").and_then(|v| v.as_str()).unwrap_or("");
    let hints = req.get("hints").and_then(|v| v.as_object());
    let actions = req.get("actions").and_then(|v| v.as_array());

    let program = |name: &str| -> String {
        apps.get(name)
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string()
    };

    let open_with_alias = |alias: &str, target: &str, rule: &str, kind: &str| -> Map<String, Value> {
        let cmd = program(alias);
        let mut m = Map::new();
        if cmd.is_empty() {
            m.insert("rule".into(), json!(format!("{}-repli", rule)));
            m.insert("kind".into(), json!(kind));
            m.insert("alias".into(), json!(alias));
            m.insert("cmd".into(), json!(alias_command("xdg-open", target)));
            m.insert(
                "display".into(),
                json!(if target.is_empty() {
                    "xdg-open".to_string()
                } else {
                    format!("xdg-open {}", shlex_quote(target))
                }),
            );
            m.insert("label".into(), json!(target));
            m.insert("missingAlias".into(), json!(alias));
        } else {
            m.insert("rule".into(), json!(rule));
            m.insert("kind".into(), json!(kind));
            m.insert("alias".into(), json!(alias));
            m.insert("cmd".into(), json!(alias_command(&cmd, target)));
            m.insert(
                "display".into(),
                json!(if target.is_empty() {
                    cmd
                } else {
                    format!("{} {}", cmd, shlex_quote(target))
                }),
            );
            m.insert("label".into(), json!(target));
        }
        m
    };

    // 1. hint explicite
    if let Some(hmap) = hints {
        for (key, value) in hmap {
            let low = key.to_ascii_lowercase();
            if HINTS_OUVERTURE.iter().any(|h| low.ends_with(h)) {
                if let Some(v) = value.as_str() {
                    if !v.is_empty() {
                        let raw = v.strip_prefix("file://").unwrap_or(v);
                        let path = url_unquote(raw);
                        let kind = path_kind(&path);
                        let alias = targets
                            .get("types")
                            .and_then(|t| t.get(kind))
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        let mut res = open_with_alias(alias, &path, "hint", "file");
                        let lbl = Path::new(&path)
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("")
                            .to_string();
                        res.insert("label".into(), json!(lbl));
                        return res;
                    }
                }
            }
        }
    }

    // 2. table par application
    for key in [app_name, desktop] {
        if key.is_empty() {
            continue;
        }
        if let Some(rule) = targets.get("apps").and_then(|a| a.get(key)) {
            if let Some(s) = rule.as_str() {
                let mut m = Map::new();
                m.insert("rule".into(), json!("table"));
                m.insert("kind".into(), json!("app"));
                m.insert("cmd".into(), json!(shlex_split(s)));
                m.insert("display".into(), json!(s));
                m.insert("label".into(), json!(key));
                return m;
            }
            if let Some(obj) = rule.as_object() {
                if let Some(run_s) = obj.get("run").and_then(|v| v.as_str()) {
                    if !run_s.is_empty() {
                        let cmd = if obj.get("terminal").and_then(|v| v.as_bool()).unwrap_or(false) {
                            let term_alias = targets
                                .get("terminal_alias")
                                .and_then(|v| v.as_str())
                                .unwrap_or("Terminal");
                            terminal_command(&program(term_alias), run_s)
                        } else {
                            shlex_split(run_s)
                        };
                        let display = obj
                            .get("label")
                            .and_then(|v| v.as_str())
                            .filter(|s| !s.is_empty())
                            .map(|s| s.to_string())
                            .unwrap_or_else(|| cmd.join(" "));
                        let mut m = Map::new();
                        m.insert("rule".into(), json!("table"));
                        m.insert("kind".into(), json!("app"));
                        m.insert("cmd".into(), json!(cmd));
                        m.insert("display".into(), json!(display));
                        m.insert("label".into(), json!(key));
                        return m;
                    }
                }
                if let Some(open_s) = obj.get("open").and_then(|v| v.as_str()) {
                    if !open_s.is_empty() {
                        return open_with_alias(open_s, "", "table", "app");
                    }
                }
            }
        }
    }

    // 3. action par défaut
    if let Some(acts) = actions {
        for action in acts {
            let ident = action
                .get("identifier")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if matches!(ident.to_ascii_lowercase().as_str(), "default" | "0") {
                let text = action
                    .get("text")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("Ouvrir");
                let mut m = Map::new();
                m.insert("rule".into(), json!("action"));
                m.insert("kind".into(), json!("action"));
                m.insert("actionId".into(), json!(ident));
                m.insert("cmd".into(), json!([]));
                m.insert("display".into(), json!(text));
                m.insert("label".into(), json!(text));
                return m;
            }
        }
    }

    // 4. chemin puis URL cités dans le texte
    let text = format!("{}\n{}", summary, body);
    let mut found: Vec<String> = candidates(&text).into_iter().filter(|p| !p.is_empty()).collect();
    found.sort_by_key(|p| if Path::new(&expand_tilde(p)).exists() { 0 } else { 1 });
    for path in found {
        let kind = path_kind(&path);
        if kind.is_empty() || !Path::new(&expand_tilde(&path)).exists() {
            continue;
        }
        let alias = targets
            .get("types")
            .and_then(|t| t.get(kind))
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let mut res = open_with_alias(alias, &path, "chemin", kind);
        let lbl = Path::new(path.trim_end_matches('/'))
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or(&path)
            .to_string();
        res.insert("label".into(), json!(lbl));
        return res;
    }

    let url_re = Regex::new(r#"https?://[^\s"'<>«»]+"#).unwrap();
    if let Some(m) = url_re.find(&text) {
        let alias = targets.get("url").and_then(|v| v.as_str()).unwrap_or("");
        return open_with_alias(alias, m.as_str(), "url", "url");
    }

    // 5. application émettrice
    if let Some(entry) = desktop_entry_for(index, desktop, app_name) {
        let exec = entry.get("exec").and_then(|v| v.as_str()).unwrap_or("");
        let name = entry
            .get("name")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(app_name);
        let mut m = Map::new();
        m.insert("rule".into(), json!("app"));
        m.insert("kind".into(), json!("app"));
        m.insert("focus".into(), json!(focus_motifs(Some(entry), desktop, app_name)));
        m.insert("cmd".into(), json!(shlex_split(exec)));
        m.insert("display".into(), json!(exec));
        m.insert("label".into(), json!(name));
        return m;
    }

    if !app_name.is_empty() || !desktop.is_empty() {
        let mut m = Map::new();
        m.insert("rule".into(), json!("focus"));
        m.insert("kind".into(), json!("focus"));
        m.insert("cmd".into(), json!([]));
        m.insert("focus".into(), json!(focus_motifs(None, desktop, app_name)));
        m.insert(
            "display".into(),
            json!(if !desktop.is_empty() { desktop } else { app_name }),
        );
        m.insert(
            "label".into(),
            json!(if !app_name.is_empty() { app_name } else { desktop }),
        );
        return m;
    }

    Map::new()
}

fn log_line(req: &Value, res: &Map<String, Value>) {
    let cache_log = cache_dir().join("quickshell").join("notifications.log");
    if let Some(parent) = cache_log.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(meta) = fs::metadata(&cache_log) {
        if meta.len() > 200_000 {
            if let Ok(txt) = fs::read_to_string(&cache_log) {
                let lines: Vec<&str> = txt.lines().collect();
                let start = lines.len().saturating_sub(400);
                let _ = fs::write(&cache_log, lines[start..].join("\n") + "\n");
            }
        }
    }

    let ws_re = Regex::new(r"\s+").unwrap();
    let clean = |val: &str, limit: usize| -> String {
        let collapsed = ws_re.replace_all(val, " ");
        let trimmed = collapsed.trim();
        let chars: Vec<char> = trimmed.chars().collect();
        if chars.len() > limit {
            let mut s: String = chars[..limit].iter().collect();
            s.push('…');
            s
        } else {
            trimmed.to_string()
        }
    };

    let app_s = clean(req.get("appName").and_then(|v| v.as_str()).unwrap_or(""), 90);
    let desk_s = clean(req.get("desktopEntry").and_then(|v| v.as_str()).unwrap_or(""), 90);
    let regle_s = res.get("rule").and_then(|v| v.as_str()).unwrap_or("aucune");
    let cible_s = clean(res.get("display").and_then(|v| v.as_str()).unwrap_or(""), 120);
    let resume_s = clean(req.get("summary").and_then(|v| v.as_str()).unwrap_or(""), 70);
    let actions_len = req
        .get("actions")
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);

    let mut fields = vec![
        format!("app={}", if app_s.is_empty() { "-" } else { &app_s }),
        format!("desktop={}", if desk_s.is_empty() { "-" } else { &desk_s }),
        format!("regle={}", regle_s),
        format!("cible={}", if cible_s.is_empty() { "-" } else { &cible_s }),
        format!("resume={}", serde_json::to_string(&resume_s).unwrap_or_default()),
        format!("actions={}", actions_len),
    ];
    if let Some(ma) = res.get("missingAlias").and_then(|v| v.as_str()) {
        if !ma.is_empty() {
            fields.push(format!("alias_manquant={}", ma));
        }
    }
    if res.is_empty() {
        let mut keys: Vec<&str> = req
            .get("hints")
            .and_then(|v| v.as_object())
            .map(|m| m.keys().map(|k| k.as_str()).collect())
            .unwrap_or_default();
        keys.sort();
        fields.push(format!("hints={}", clean(&keys.join(","), 120)));
    }
    if let Ok(mut fh) = OpenOptions::new().create(true).append(true).open(&cache_log) {
        let _ = writeln!(fh, "{} | {}", format_local_now(), fields.join(" "));
    }
}

fn remember(req: &Value, res: &Map<String, Value>) {
    let ts_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let mut entry = Map::new();
    entry.insert("ts".into(), json!(format_local_now()));
    entry.insert("ts_ms".into(), json!(ts_ms));
    entry.insert(
        "app".into(),
        json!(req.get("appName").and_then(|v| v.as_str()).unwrap_or("")),
    );
    entry.insert(
        "desktop".into(),
        json!(req.get("desktopEntry").and_then(|v| v.as_str()).unwrap_or("")),
    );
    entry.insert(
        "summary".into(),
        json!(req.get("summary").and_then(|v| v.as_str()).unwrap_or("")),
    );
    entry.insert(
        "body".into(),
        json!(req.get("body").and_then(|v| v.as_str()).unwrap_or("")),
    );
    entry.insert(
        "actions".into(),
        req.get("actions").cloned().unwrap_or_else(|| json!([])),
    );
    entry.insert("target".into(), Value::Object(res.clone()));
    add_entry(entry);
}

fn answer(req: &Value, record_history: bool) -> Value {
    let res = resolve_target(req);
    log_line(req, &res);
    if record_history {
        remember(req, &res);
    }
    let mut out = res;
    if let Some(id) = req.get("id") {
        out.insert("id".into(), id.clone());
    }
    Value::Object(out)
}

pub fn run_target(args: &[String]) -> i32 {
    let serve = args.iter().any(|a| a == "--serve");
    if serve {
        let stdin = io::stdin();
        let stdout = io::stdout();
        let mut out = stdout.lock();
        for line in stdin.lock().lines().flatten() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let Ok(req) = serde_json::from_str::<Value>(trimmed) else {
                continue;
            };
            let ans = answer(&req, true);
            if let Ok(s) = serde_json::to_string(&ans) {
                let _ = writeln!(out, "{s}");
                let _ = out.flush();
            }
        }
        return 0;
    }

    let mut payload = String::new();
    let _ = io::stdin().read_to_string(&mut payload);
    let req = if payload.trim().is_empty() {
        json!({})
    } else {
        serde_json::from_str::<Value>(&payload).unwrap_or_else(|_| json!({}))
    };
    let ans = answer(&req, false);
    if let Ok(s) = serde_json::to_string(&ans) {
        println!("{s}");
    }
    0
}
