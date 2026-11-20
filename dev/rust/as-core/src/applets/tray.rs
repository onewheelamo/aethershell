use crate::common::io::{read_json_value, run_cmd, run_cmd_stdout, tie_to_parent_death};
use crate::common::paths::core_dir;
use crate::launcher::app_index::{couvre, jetons};
use serde_json::Value;
use std::collections::HashSet;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

const WATCHER: &str = "org.kde.StatusNotifierWatcher";
const PATH: &str = "/StatusNotifierWatcher";
const IFACE: &str = "org.kde.StatusNotifierWatcher";

fn fenetres() -> Vec<Value> {
    let Some(sortie) = run_cmd_stdout("hyprctl", &["clients", "-j"]) else {
        return vec![];
    };
    serde_json::from_str::<Vec<Value>>(&sortie).unwrap_or_default()
}

fn choisir_fenetre<'a>(recherche: &HashSet<String>, clients: &'a [Value]) -> Option<&'a Value> {
    let mut candidates: Vec<(usize, i64, &'a Value)> = Vec::new();
    for c in clients {
        let cls = c.get("class").and_then(|v| v.as_str()).unwrap_or("");
        let title = c.get("title").and_then(|v| v.as_str()).unwrap_or("");
        let mut candidat = jetons(cls);
        candidat.extend(jetons(title));
        if couvre(recherche, &candidat) {
            let focus_id = c
                .get("focusHistoryID")
                .and_then(|v| v.as_i64())
                .unwrap_or(9999);
            candidates.push((candidat.len(), focus_id, c));
        }
    }
    candidates.sort_by_key(|t| (t.0, t.1));
    candidates.first().map(|t| t.2)
}

fn choisir_desktop<'a>(recherche: &HashSet<String>, index: &'a [Value]) -> Option<&'a Value> {
    let distinctifs: HashSet<String> = recherche
        .iter()
        .filter(|j| j.len() >= 3)
        .cloned()
        .collect();
    if distinctifs.is_empty() {
        return None;
    }
    let mut candidates: Vec<(usize, usize, &'a Value)> = Vec::new();
    for e in index {
        let desk = e.get("desktop").and_then(|v| v.as_str()).unwrap_or("");
        let stem = jetons(desk.strip_suffix(".desktop").unwrap_or(desk));
        if couvre(&distinctifs, &stem) {
            let exact = if stem == distinctifs { 0 } else { 1 };
            let extra = stem.difference(&distinctifs).count();
            candidates.push((exact, extra, e));
        }
    }
    candidates.sort_by_key(|t| (t.0, t.1));
    candidates.first().map(|t| t.2)
}

fn lancer_cmd(commande: &str) {
    let script = format!("cd \"$HOME\" && exec {}", commande);
    let _ = Command::new("setsid")
        .args(["sh", "-c", &script])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

pub fn run_apps(args: &[String]) -> i32 {
    let mut pos: Vec<&str> = Vec::new();
    let mut sec = false;
    for a in args {
        if a == "--dry-run" {
            sec = true;
        } else if !a.starts_with("--") {
            pos.push(a.as_str());
        }
    }
    if pos.is_empty() {
        eprintln!("tray_apps.py <id-item> [<titre-item>] [--dry-run]");
        return 2;
    }

    let item_id = pos[0];
    let titre = if pos.len() > 1 { pos[1] } else { "" };
    let mut recherche = jetons(item_id);
    recherche.extend(jetons(titre));

    let clients = fenetres();
    if let Some(win) = choisir_fenetre(&recherche, &clients) {
        let adresse = win.get("address").and_then(|v| v.as_str()).unwrap_or("");
        if sec {
            let cls = win.get("class").and_then(|v| v.as_str()).unwrap_or("");
            println!("focus {} ({})", adresse, cls);
            return 0;
        }
        let arg = format!("hl.dsp.focus({{ window = \"address:{}\" }})", adresse);
        let _ = run_cmd("hyprctl", &["dispatch", &arg]);
        return 0;
    }

    let idx_val = read_json_value(&core_dir().join("app_index.json"));
    let index = idx_val.as_array().map(|a| a.as_slice()).unwrap_or(&[]);
    if let Some(entree) = choisir_desktop(&recherche, index) {
        let exec = entree.get("exec").and_then(|v| v.as_str()).unwrap_or("");
        if sec {
            let desk = entree.get("desktop").and_then(|v| v.as_str()).unwrap_or("");
            println!("lance {} → {}", desk, exec);
            return 0;
        }
        lancer_cmd(exec);
        return 0;
    }

    if sec {
        println!("rien (activate() au choix du QML)");
    }
    3
}

fn busctl(args: &[&str]) -> Option<std::process::Output> {
    let mut full = vec!["--user"];
    full.extend_from_slice(args);
    run_cmd("busctl", &full)
}

fn watcher_items() -> Option<Vec<String>> {
    let out = busctl(&[
        "get-property",
        WATCHER,
        PATH,
        IFACE,
        "RegisteredStatusNotifierItems",
    ])?;
    if !out.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let items = stdout
        .split_whitespace()
        .filter(|tok| tok.starts_with('"'))
        .map(|tok| tok.trim_matches('"').to_string())
        .collect();
    Some(items)
}

fn live_items() -> Vec<String> {
    let Some(out) = busctl(&["list", "--no-legend"]) else {
        return vec![];
    };
    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut services = Vec::new();
    for line in stdout.lines() {
        if let Some(name) = line.split_whitespace().next() {
            if name.starts_with("org.kde.StatusNotifierItem-") {
                services.push(name.to_string());
            }
        }
    }
    services
}

fn watcher_alive() -> bool {
    let Some(out) = busctl(&["status", WATCHER]) else {
        return false;
    };
    out.status.success() && String::from_utf8_lossy(&out.stdout).contains("PID=")
}

fn heal(verbose: bool) {
    let Some(registered) = watcher_items() else {
        return;
    };
    let have: HashSet<String> = registered
        .into_iter()
        .map(|e| e.split('/').next().unwrap_or("").to_string())
        .collect();
    for service in live_items() {
        if have.contains(&service) {
            continue;
        }
        if let Some(out) = busctl(&[
            "call",
            WATCHER,
            PATH,
            IFACE,
            "RegisterStatusNotifierItem",
            "s",
            &service,
        ]) {
            if out.status.success() && verbose {
                println!("ré-enregistré : {}", service);
            }
        }
    }
}

pub fn run_watchdog(args: &[String]) -> i32 {
    tie_to_parent_death();
    let mut once = false;
    let mut interval: u64 = 10;
    for i in 0..args.len() {
        if args[i] == "--once" {
            once = true;
        } else if args[i] == "--interval" && i + 1 < args.len() {
            if let Ok(v) = args[i + 1].parse::<u64>() {
                interval = v.max(2);
            }
        }
    }

    let parent = unsafe { libc::getppid() };
    let mut absences = 0u32;
    loop {
        let cur_parent = unsafe { libc::getppid() };
        if cur_parent == 1 && parent != 1 {
            return 0;
        }
        if !watcher_alive() {
            absences += 1;
            if absences >= 6 {
                return 0;
            }
        } else {
            absences = 0;
            heal(true);
        }
        if once {
            return 0;
        }
        let sleep_secs = if absences == 0 { interval } else { 3 };
        thread::sleep(Duration::from_secs(sleep_secs));
    }
}
