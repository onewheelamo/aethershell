use crate::common::contrat::sortir;
use crate::common::io::{read_json, run_cmd, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{home_dir, runtime_dir};
use glob::glob;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn proc_boot_time_secs() -> f64 {
    let Ok(txt) = fs::read_to_string("/proc/stat") else { return 0.0; };
    for line in txt.lines() {
        if let Some(rest) = line.strip_prefix("btime ") {
            if let Ok(b) = rest.trim().parse::<f64>() {
                return b;
            }
        }
    }
    0.0
}

fn proc_elapsed_secs(pid: i32) -> i64 {
    let Ok(st) = fs::read_to_string(format!("/proc/{pid}/stat")) else { return 0; };
    let Some((_, right)) = st.rsplit_once(')') else { return 0; };
    let cols: Vec<&str> = right.split_whitespace().collect();
    if cols.len() <= 19 {
        return 0;
    }
    let start_ticks = cols[19].parse::<f64>().unwrap_or(0.0);
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
    let btime = proc_boot_time_secs();
    if btime <= 0.0 {
        return 0;
    }
    let start_epoch = btime + (start_ticks / ticks);
    (now_secs() - start_epoch).max(0.0).round() as i64
}

fn probe_wf_recorder() -> Value {
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let s = ent.file_name().to_string_lossy().to_string();
            let Ok(pid) = s.parse::<i32>() else { continue };
            if let Ok(comm) = fs::read_to_string(ent.path().join("comm")) {
                if comm.trim() == "wf-recorder" {
                    return json!({
                        "active": true,
                        "elapsedSec": proc_elapsed_secs(pid),
                        "pid": pid,
                    });
                }
            }
        }
    }
    json!({ "active": false, "elapsedSec": 0, "pid": 0 })
}

fn download_dir() -> Option<PathBuf> {
    if let Some(p) = run_cmd_stdout("xdg-user-dir", &["DOWNLOAD"]) {
        let pb = PathBuf::from(&p);
        if pb.is_dir() {
            return Some(pb);
        }
    }
    for cand in ["Téléchargements", "Downloads"] {
        let pb = home_dir().join(cand);
        if pb.is_dir() {
            return Some(pb);
        }
    }
    None
}

fn fmt_size(nb: u64) -> String {
    if nb < 1024 * 1024 {
        format!("{} Ko", (nb / 1024).max(1))
    } else if nb < 1024 * 1024 * 1024 {
        format!("{:.1} Mo", nb as f64 / (1024.0 * 1024.0))
    } else {
        format!("{:.2} Go", nb as f64 / (1024.0 * 1024.0 * 1024.0))
    }
}

fn fmt_speed(bps: f64) -> String {
    if bps <= 0.0 {
        String::new()
    } else if bps < 1024.0 * 1024.0 {
        format!("{} Ko/s", ((bps / 1024.0) as u64).max(1))
    } else {
        format!("{:.1} Mo/s", bps / (1024.0 * 1024.0))
    }
}

#[derive(Default, Clone)]
struct DlMeta {
    total_bytes: u64,
    name: String,
}

fn load_gecko_meta(meta: &mut HashMap<String, DlMeta>) {
    let h = home_dir();
    let patterns = [
        ".mozilla/firefox/*/downloads.json",
        ".librewolf/*/downloads.json",
        ".zen/*/downloads.json",
        ".floorp/*/downloads.json",
        ".waterfox/*/downloads.json",
        ".var/app/org.mozilla.firefox/.mozilla/firefox/*/downloads.json",
        ".var/app/io.gitlab.librewolf-community/.librewolf/*/downloads.json",
        ".var/app/app.zen_browser.zen/.zen/*/downloads.json",
    ];
    for pat in patterns {
        let full = h.join(pat).to_string_lossy().to_string();
        if let Ok(paths) = glob(&full) {
            for p in paths.flatten() {
                let Some(val) = read_json::<Value>(&p) else { continue };
                let Some(list) = val.get("list").and_then(|v| v.as_array()) else { continue };
                for item in list {
                    let Some(tgt) = item.get("target") else { continue };
                    let part = tgt.get("partFilePath").and_then(|v| v.as_str()).unwrap_or("");
                    if part.is_empty() {
                        continue;
                    }
                    let final_p = tgt.get("path").and_then(|v| v.as_str()).unwrap_or("");
                    let name = Path::new(final_p)
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("")
                        .to_string();
                    let total = item.get("totalBytes").and_then(|v| v.as_u64()).unwrap_or(0);
                    meta.insert(part.to_string(), DlMeta { total_bytes: total, name });
                }
            }
        }
    }
}

fn load_chromium_meta(meta: &mut HashMap<String, DlMeta>) {
    let h = home_dir();
    let patterns = [
        ".config/google-chrome/*/History",
        ".config/chromium/*/History",
        ".config/BraveSoftware/Brave-Browser/*/History",
        ".config/opera/History",
        ".config/opera/*/History",
        ".config/vivaldi/*/History",
        ".config/microsoft-edge/*/History",
        ".var/app/com.google.Chrome/config/google-chrome/*/History",
        ".var/app/org.chromium.Chromium/config/chromium/*/History",
        ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/*/History",
        ".var/app/com.opera.Opera/config/opera/History",
    ];
    let tmp_db = runtime_dir().join(format!("qs-chrome-hist-{}.sqlite", std::process::id()));
    for pat in patterns {
        let full = h.join(pat).to_string_lossy().to_string();
        if let Ok(paths) = glob(&full) {
            for db in paths.flatten() {
                if fs::copy(&db, &tmp_db).is_err() {
                    continue;
                }
                if let Ok(conn) = Connection::open(&tmp_db) {
                    if let Ok(mut stmt) = conn.prepare(
                        "SELECT current_path, target_path, total_bytes FROM downloads WHERE state = 0",
                    ) {
                        if let Ok(rows) = stmt.query_map([], |row| {
                            let cur: String = row.get(0).unwrap_or_default();
                            let tgt: String = row.get(1).unwrap_or_default();
                            let tot: i64 = row.get(2).unwrap_or(0);
                            Ok((cur, tgt, tot))
                        }) {
                            for r in rows.flatten() {
                                if !r.0.is_empty() {
                                    let name = Path::new(&r.1)
                                        .file_name()
                                        .and_then(|s| s.to_str())
                                        .unwrap_or("")
                                        .to_string();
                                    meta.insert(
                                        r.0,
                                        DlMeta {
                                            total_bytes: r.2.max(0) as u64,
                                            name,
                                        },
                                    );
                                }
                            }
                        }
                    }
                }
                let _ = fs::remove_file(&tmp_db);
            }
        }
    }
}

#[derive(Serialize, Deserialize, Default)]
struct DlCacheEntry {
    size: u64,
    ts: f64,
    #[serde(rename = "speedBps")]
    speed_bps: f64,
}

fn probe_downloads() -> Vec<Value> {
    let Some(dl_dir) = download_dir() else { return vec![]; };
    let now = now_secs();
    let suffixes = [".part", ".crdownload", ".opdownload"];
    let mut raw = Vec::new();
    let Ok(entries) = fs::read_dir(&dl_dir) else { return vec![]; };
    for ent in entries.flatten() {
        let p = ent.path();
        if !p.is_file() {
            continue;
        }
        let fname = ent.file_name().to_string_lossy().to_string();
        let low = fname.to_ascii_lowercase();
        if !suffixes.iter().any(|s| low.ends_with(s)) {
            continue;
        }
        let Ok(meta) = ent.metadata() else { continue };
        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs_f64())
            .unwrap_or(0.0);
        if (now - mtime) > 45.0 {
            continue;
        }
        raw.push((p, fname, low, meta.len()));
    }
    if raw.is_empty() {
        return vec![];
    }

    let mut dl_meta = HashMap::new();
    if raw.iter().any(|(_, _, l, _)| l.ends_with(".part")) {
        load_gecko_meta(&mut dl_meta);
    }
    if raw
        .iter()
        .any(|(_, _, l, _)| l.ends_with(".crdownload") || l.ends_with(".opdownload"))
    {
        load_chromium_meta(&mut dl_meta);
    }

    let cache_path = runtime_dir().join("qs-dl-probe-cache.json");
    let prev_cache: HashMap<String, DlCacheEntry> = read_json(&cache_path).unwrap_or_default();
    let mut new_cache: HashMap<String, DlCacheEntry> = HashMap::new();
    let mut found: Vec<(String, Value)> = Vec::new();

    for (path, fname, low, size) in raw {
        let mut clean = fname.clone();
        for s in suffixes {
            if low.ends_with(s) {
                clean.truncate(clean.len() - s.len());
                break;
            }
        }
        let path_str = path.to_string_lossy().to_string();
        let m = dl_meta.get(&path_str).cloned().unwrap_or_default();
        if !m.name.is_empty() {
            clean = m.name;
        }
        let progress = if m.total_bytes > 0 {
            ((100.0 * size as f64 / m.total_bytes as f64).round() as i64).clamp(0, 100)
        } else {
            -1
        };
        let mut speed_bps = 0.0;
        if let Some(prev) = prev_cache.get(&path_str) {
            let dt = now - prev.ts;
            if dt > 0.2 && size > prev.size {
                speed_bps = (size - prev.size) as f64 / dt;
            } else if dt <= 6.0 && prev.speed_bps > 0.0 {
                speed_bps = prev.speed_bps;
            }
        }
        let eta_sec = if m.total_bytes > size && speed_bps > 0.0 {
            ((m.total_bytes - size) as f64 / speed_bps).round() as i64
        } else {
            -1
        };
        new_cache.insert(path_str, DlCacheEntry { size, ts: now, speed_bps });
        let display_name = if clean.is_empty() { fname } else { clean };
        found.push((
            display_name.to_ascii_lowercase(),
            json!({
                "name": display_name,
                "size": size,
                "totalBytes": m.total_bytes,
                "progress": progress,
                "sizeStr": fmt_size(size),
                "totalStr": if m.total_bytes > 0 { fmt_size(m.total_bytes) } else { String::new() },
                "speedBps": speed_bps.round() as i64,
                "speedStr": fmt_speed(speed_bps),
                "etaSec": eta_sec,
            }),
        ));
    }
    let _ = write_json_atomic(&cache_path, &new_cache, 0o644);
    found.sort_by(|a, b| a.0.cmp(&b.0));
    found.into_iter().map(|(_, v)| v).collect()
}

fn pkg_needs_input(root_pid: i32) -> bool {
    if root_pid <= 0 {
        return false;
    }
    let mut children: HashMap<i32, Vec<i32>> = HashMap::new();
    let mut states: HashMap<i32, (bool, String)> = HashMap::new();
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let Ok(pid) = ent.file_name().to_string_lossy().parse::<i32>() else { continue };
            let Ok(st) = fs::read_to_string(ent.path().join("stat")) else { continue };
            let Some((_, right)) = st.rsplit_once(')') else { continue };
            let cols: Vec<&str> = right.split_whitespace().collect();
            if cols.len() <= 5 { continue; }
            let ppid = cols[1].parse::<i32>().unwrap_or(0);
            let pgrp = cols[2].parse::<i32>().unwrap_or(0);
            let tpgid = cols[5].parse::<i32>().unwrap_or(-1);
            let is_fg = pgrp > 0 && pgrp == tpgid;
            let wchan = fs::read_to_string(ent.path().join("wchan")).unwrap_or_default().trim().to_string();
            children.entry(ppid).or_default().push(pid);
            states.insert(pid, (is_fg, wchan));
        }
    }
    let mut queue = VecDeque::from([root_pid]);
    let mut seen = HashSet::new();
    while let Some(cur) = queue.pop_front() {
        if !seen.insert(cur) { continue; }
        if let Some((is_fg, wchan)) = states.get(&cur) {
            if *is_fg && matches!(wchan.as_str(), "n_tty_read" | "wait_woken" | "tty_read") {
                return true;
            }
        }
        if let Some(ch) = children.get(&cur) {
            for &c in ch {
                if !seen.contains(&c) { queue.push_back(c); }
            }
        }
    }
    false
}

#[derive(Serialize, Deserialize, Default)]
struct PkgCache {
    pid: i32,
    initial: i64,
}

fn probe_pkg_update() -> Value {
    let arch_ignored = [
        "-c", "--check", "-l", "--list", "-n", "--news",
        "-s", "--services", "--tray", "--gen-config",
        "--show-config", "--edit-config", "-h", "--help", "-V", "--version",
    ];
    let pkg_verbs = ["upgrade", "update", "full-upgrade", "dist-upgrade", "distro-sync", "system-upgrade", "install"];
    let pkg_ignored = ["check-update", "makecache", "info", "search", "list", "show", "policy", "-h", "--help", "-V", "--version"];

    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let Ok(pid) = ent.file_name().to_string_lossy().parse::<i32>() else { continue };
            let Ok(raw) = fs::read(ent.path().join("cmdline")) else { continue };
            if raw.is_empty() { continue; }
            let tokens: Vec<String> = raw
                .split(|&b| b == 0)
                .filter(|s| !s.is_empty())
                .map(|s| String::from_utf8_lossy(s).to_string())
                .collect();
            if tokens.is_empty() { continue; }
            let head: Vec<String> = tokens
                .iter()
                .take(3)
                .filter_map(|t| Path::new(t).file_name().and_then(|s| s.to_str()).map(|s| s.to_string()))
                .collect();

            let mut matched = String::new();
            if head.iter().any(|h| h == "arch-update") {
                if tokens.iter().any(|t| arch_ignored.contains(&t.as_str())) {
                    continue;
                }
                matched = "arch-update".to_string();
            } else if let Some(tool) = head.iter().find(|h| matches!(h.as_str(), "dnf" | "dnf5" | "apt" | "apt-get" | "nala")) {
                if tokens.iter().any(|t| pkg_ignored.contains(&t.as_str())) {
                    continue;
                }
                if !tokens.iter().any(|t| pkg_verbs.contains(&t.as_str())) {
                    continue;
                }
                matched = tool.clone();
            }

            if !matched.is_empty() {
                let elapsed = proc_elapsed_secs(pid);
                let needs_input = pkg_needs_input(pid);
                let mut remaining = -1i64;
                let mut initial = -1i64;
                let mut progress = -1i64;
                let mut eta_sec = -1i64;
                if matched == "arch-update" {
                    if let Some(out) = run_cmd_stdout("pacman", &["-Qu"]) {
                        remaining = out.lines().filter(|l| !l.trim().is_empty()).count() as i64;
                    }
                    let cache_path = runtime_dir().join("qs-pkg-probe-cache.json");
                    let cache: PkgCache = read_json(&cache_path).unwrap_or_default();
                    if cache.pid == pid && cache.initial > 0 {
                        initial = cache.initial.max(remaining);
                    } else if remaining >= 0 {
                        initial = remaining;
                    }
                    let _ = write_json_atomic(&cache_path, &PkgCache { pid, initial }, 0o644);
                    if initial > 0 && remaining >= 0 && remaining < initial {
                        let done = initial - remaining;
                        progress = ((100.0 * done as f64 / initial as f64).round() as i64).clamp(0, 99);
                        if remaining > 0 {
                            eta_sec = (elapsed as f64 * remaining as f64 / done as f64).round() as i64;
                        }
                    }
                }
                return json!({
                    "active": true,
                    "elapsedSec": elapsed,
                    "pid": pid,
                    "tool": matched,
                    "needsInput": needs_input,
                    "remainingPkgs": remaining,
                    "initialPkgs": initial,
                    "progress": progress,
                    "etaSec": eta_sec,
                });
            }
        }
    }

    json!({
        "active": false,
        "elapsedSec": 0,
        "pid": 0,
        "tool": "",
        "needsInput": false,
        "remainingPkgs": -1,
        "initialPkgs": -1,
        "progress": -1,
        "etaSec": -1,
    })
}

fn ancestor_pids(pid: i32) -> HashSet<i32> {
    let mut out = HashSet::new();
    let mut cur = pid;
    for _ in 0..16 {
        if cur <= 1 || !out.insert(cur) {
            break;
        }
        let Ok(st) = fs::read_to_string(format!("/proc/{cur}/stat")) else { break };
        let Some((_, right)) = st.rsplit_once(')') else { break };
        cur = right.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    }
    out
}

fn focus_hypr_client(c: &Value) -> bool {
    let Some(addr) = c.get("address").and_then(|v| v.as_str()) else { return false };
    if let Some(ws_id) = c.get("workspace").and_then(|w| w.get("id")).and_then(|v| v.as_i64()) {
        if ws_id > 0 {
            let expr = format!("hl.dsp.focus({{ workspace = {ws_id} }})");
            let _ = run_cmd("hyprctl", &["dispatch", &expr]);
        }
    }
    let expr = format!("hl.dsp.focus({{ window = \"address:{addr}\" }})");
    let _ = run_cmd("hyprctl", &["dispatch", &expr]);
    true
}

fn focus_activity(kind: &str, pid: i32) -> bool {
    let Some(raw) = run_cmd_stdout("hyprctl", &["clients", "-j"]) else { return false };
    let Ok(clients) = serde_json::from_str::<Vec<Value>>(&raw) else { return false };
    if kind == "update" {
        let ancs = ancestor_pids(pid);
        for c in &clients {
            if let Some(cpid) = c.get("pid").and_then(|v| v.as_i64()) {
                if ancs.contains(&(cpid as i32)) {
                    return focus_hypr_client(c);
                }
            }
        }
        for c in &clients {
            let title = c.get("title").and_then(|v| v.as_str()).unwrap_or("").to_ascii_lowercase();
            if ["arch-update", "dnf", "apt", "nala"].iter().any(|k| title.contains(k)) {
                return focus_hypr_client(c);
            }
        }
        return false;
    }
    if kind == "download" {
        let browsers = ["firefox", "zen", "librewolf", "floorp", "waterfox", "chromium", "chrome", "brave", "vivaldi", "opera", "microsoft-edge"];
        let mut matches: Vec<&Value> = clients
            .iter()
            .filter(|c| {
                let cls = c.get("class").and_then(|v| v.as_str()).unwrap_or("").to_ascii_lowercase();
                let icls = c.get("initialClass").and_then(|v| v.as_str()).unwrap_or("").to_ascii_lowercase();
                browsers.iter().any(|b| cls.contains(b) || icls.contains(b))
            })
            .collect();
        matches.sort_by_key(|c| {
            let ws_name = c.get("workspace").and_then(|w| w.get("name")).and_then(|v| v.as_str()).unwrap_or("");
            let is_spec = if ws_name.starts_with("special:") { 1 } else { 0 };
            let fhid = c.get("focusHistoryID").and_then(|v| v.as_i64()).unwrap_or(999);
            (is_spec, fhid)
        });
        if let Some(first) = matches.first() {
            return focus_hypr_client(first);
        }
    }
    false
}

pub fn run(args: &[String]) -> i32 {
    if args.len() >= 2 && args[0] == "--focus" {
        let kind = args[1].as_str();
        let pid = args.get(2).and_then(|s| s.parse::<i32>().ok()).unwrap_or(0);
        return sortir(&json!({ "ok": focus_activity(kind, pid) }));
    }
    sortir(&json!({
        "recording": probe_wf_recorder(),
        "pkgUpdate": probe_pkg_update(),
        "downloads": probe_downloads(),
    }))
}
