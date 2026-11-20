use crate::common::contrat::sortir;
use crate::common::io::run_cmd_stdout;
use regex::Regex;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::thread;
use std::time::{Duration, Instant};

fn ctl(args: &[&str]) -> String {
    run_cmd_stdout("bluetoothctl", args).unwrap_or_default()
}

fn parse_device_line(line: &str) -> Option<(String, String)> {
    let re = Regex::new(r"^Device\s+([0-9A-Fa-f:]{17})\s*(.*)$").ok()?;
    let cap = re.captures(line.trim())?;
    let mac = cap[1].to_ascii_uppercase();
    let nom = cap[2].trim();
    Some((mac.clone(), if nom.is_empty() { mac } else { nom.to_string() }))
}

fn devices(sub: &str) -> Vec<(String, String)> {
    ctl(&["devices", sub])
        .lines()
        .filter_map(parse_device_line)
        .collect()
}

fn powered_now() -> bool {
    Regex::new(r"(?m)^\s*Powered:\s*yes")
        .ok()
        .map(|re| re.is_match(&ctl(&["show"])))
        .unwrap_or(false)
}

pub fn etat() -> Value {
    let show = ctl(&["show"]);
    if show.is_empty() && run_cmd_stdout("which", &["bluetoothctl"]).is_none() {
        return json!({ "present": false });
    }
    if !show.contains("Controller") {
        return json!({ "present": false, "erreur": "aucun adaptateur" });
    }
    let allume = Regex::new(r"(?m)^\s*Powered:\s*yes")
        .ok()
        .map(|re| re.is_match(&show))
        .unwrap_or(false);
    let adresse = Regex::new(r"Controller\s+([0-9A-Fa-f:]{17})")
        .ok()
        .and_then(|re| re.captures(&show))
        .map(|c| c[1].to_ascii_uppercase())
        .unwrap_or_default();

    let connectes_list = devices("Connected");
    let mut connectes_map: BTreeMap<String, String> = BTreeMap::new();
    for (m, n) in &connectes_list {
        connectes_map.insert(m.clone(), n.clone());
    }

    let mut appaires = Vec::new();
    let mut connus = HashSet::new();
    for (mac, nom) in devices("Paired") {
        connus.insert(mac.clone());
        let conn = connectes_map.contains_key(&mac);
        appaires.push(json!({ "mac": mac, "nom": nom, "connecte": conn }));
    }
    for (mac, nom) in &connectes_map {
        if !connus.contains(mac) {
            appaires.push(json!({ "mac": mac, "nom": nom, "connecte": true }));
        }
    }

    let connectes: Vec<Value> = connectes_map
        .into_iter()
        .map(|(m, n)| json!({ "mac": m, "nom": n }))
        .collect();

    json!({
        "present": true,
        "allume": allume,
        "adresse": adresse,
        "connectes": connectes,
        "appaires": appaires,
    })
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.trim()).unwrap_or("etat");
    match action {
        "etat" => sortir(&etat()),
        "basculer" | "activer" | "desactiver" => {
            let e = etat();
            if !e.get("present").and_then(|v| v.as_bool()).unwrap_or(false) {
                return sortir(&e);
            }
            let cur = e.get("allume").and_then(|v| v.as_bool()).unwrap_or(false);
            let cible = match action {
                "basculer" => !cur,
                "activer" => true,
                _ => false,
            };
            let _ = ctl(&["power", if cible { "on" } else { "off" }]);
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if powered_now() == cible {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }
            sortir(&etat())
        }
        "connecter" | "deconnecter" if args.len() > 1 => {
            let mac = args[1].trim();
            let sub = if action == "connecter" { "connect" } else { "disconnect" };
            let _ = ctl(&[sub, mac]);
            sortir(&etat())
        }
        _ => {
            sortir(&json!({ "erreur": "action inconnue" }));
            2
        }
    }
}
