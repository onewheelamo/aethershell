use crate::common::io::{read_json, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{hostname, quickshell_cache_dir};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::fs;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Serialize, Deserialize)]
pub struct TraficState {
    pub dev: String,
    pub rx: u64,
    pub tx: u64,
    pub ts: f64,
}

static MEM_TRAFIC: Mutex<Option<TraficState>> = Mutex::new(None);

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn interface_active() -> (String, String, String) {
    let Some(out) = run_cmd_stdout(
        "nmcli",
        &["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "dev", "status"],
    ) else {
        return (String::new(), String::new(), String::new());
    };
    for line in out.lines() {
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() < 4 {
            continue;
        }
        let (dev, nature, state, conn) = (parts[0], parts[1], parts[2], parts[3]);
        if !matches!(nature, "wifi" | "ethernet") || !state.starts_with("connected") {
            continue;
        }
        return (dev.to_string(), nature.to_string(), conn.to_string());
    }
    (String::new(), String::new(), String::new())
}

fn wifi_info(dev: &str, out: &mut Map<String, Value>) {
    let Some(link) = run_cmd_stdout("iw", &["dev", dev, "link"]) else {
        return;
    };
    if link.contains("Not connected") || link.trim().is_empty() {
        return;
    }
    if let Some(cap) = Regex::new(r"SSID:\s*(.+)").ok().and_then(|r| r.captures(&link)) {
        out.insert("ssid".into(), json!(cap[1].trim()));
    }
    if let Some(cap) = Regex::new(r"freq:\s*([\d.]+)").ok().and_then(|r| r.captures(&link)) {
        if let Ok(freq) = cap[1].parse::<f64>() {
            out.insert("frequence".into(), json!(freq.round() as i64));
            let (bande, canal) = if freq < 3000.0 {
                ("2,4 GHz", ((freq - 2407.0) / 5.0).round() as i64)
            } else if freq < 5925.0 {
                ("5 GHz", ((freq - 5000.0) / 5.0).round() as i64)
            } else {
                ("6 GHz", ((freq - 5950.0) / 5.0).round() as i64)
            };
            out.insert("bande".into(), json!(bande));
            out.insert("canal".into(), json!(canal));
        }
    }
    if let Some(cap) = Regex::new(r"signal:\s*(-?\d+)").ok().and_then(|r| r.captures(&link)) {
        if let Ok(dbm) = cap[1].parse::<i64>() {
            out.insert("dbm".into(), json!(dbm));
            let sig = (2 * (dbm + 100)).clamp(0, 100);
            out.insert("signal".into(), json!(sig));
        }
    }
    if let Some(cap) = Regex::new(r"rx bitrate:\s*([\d.]+)").ok().and_then(|r| r.captures(&link)) {
        if let Ok(v) = cap[1].parse::<f64>() {
            out.insert("rx_mbps".into(), json!((v * 10.0).round() / 10.0));
        }
    }
    if let Some(cap) = Regex::new(r"tx bitrate:\s*([\d.]+)").ok().and_then(|r| r.captures(&link)) {
        if let Ok(v) = cap[1].parse::<f64>() {
            out.insert("tx_mbps".into(), json!((v * 10.0).round() / 10.0));
        }
    }
}

fn adresse_info(dev: &str, out: &mut Map<String, Value>) {
    if let Some(addr) = run_cmd_stdout("ip", &["-4", "addr", "show", dev]) {
        if let Some(cap) = Regex::new(r"inet\s+([\d.]+)/(\d+)").ok().and_then(|r| r.captures(&addr)) {
            out.insert("ip".into(), json!(&cap[1]));
            if let Ok(p) = cap[2].parse::<i64>() {
                out.insert("prefixe".into(), json!(p));
            }
        }
    }
    if let Some(route) = run_cmd_stdout("ip", &["route", "show", "default", "dev", dev]) {
        if let Some(cap) = Regex::new(r"via\s+([\d.]+)").ok().and_then(|r| r.captures(&route)) {
            out.insert("passerelle".into(), json!(&cap[1]));
        }
    }
}

fn vpn_name() -> Option<String> {
    let out = run_cmd_stdout(
        "nmcli",
        &["-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"],
    )?;
    for line in out.lines() {
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() >= 3 && matches!(parts[1], "wireguard" | "vpn" | "tun") {
            return Some(parts[0].to_string());
        }
    }
    None
}

fn trafic_info(dev: &str, persister: bool, out: &mut Map<String, Value>) {
    let base = format!("/sys/class/net/{dev}/statistics");
    let Ok(rx_s) = fs::read_to_string(format!("{base}/rx_bytes")) else { return; };
    let Ok(tx_s) = fs::read_to_string(format!("{base}/tx_bytes")) else { return; };
    let Ok(rx) = rx_s.trim().parse::<u64>() else { return; };
    let Ok(tx) = tx_s.trim().parse::<u64>() else { return; };

    let now = now_secs();
    let etat_path = quickshell_cache_dir().join("reseau_etat.json");
    let prev: Option<TraficState> = if persister {
        read_json(&etat_path)
    } else {
        MEM_TRAFIC.lock().ok().and_then(|g| g.clone())
    };

    out.insert("rx_total_go".into(), json!(((rx as f64 / 1e9) * 10.0).round() / 10.0));
    out.insert("tx_total_go".into(), json!(((tx as f64 / 1e9) * 10.0).round() / 10.0));

    if let Some(p) = prev {
        if p.dev == dev {
            let dt = now - p.ts;
            if dt > 0.3 && dt < 120.0 {
                let rx_ko = ((rx.saturating_sub(p.rx) as f64) / dt / 1024.0).round() as u64;
                let tx_ko = ((tx.saturating_sub(p.tx) as f64) / dt / 1024.0).round() as u64;
                out.insert("rx_ko_s".into(), json!(rx_ko));
                out.insert("tx_ko_s".into(), json!(tx_ko));
            }
        }
    }

    let next = TraficState {
        dev: dev.to_string(),
        rx,
        tx,
        ts: now,
    };
    if persister {
        let _ = write_json_atomic(&etat_path, &next, 0o644);
    } else if let Ok(mut g) = MEM_TRAFIC.lock() {
        *g = Some(next);
    }
}

fn latence_ms(gw: &str) -> Option<i64> {
    let out = run_cmd_stdout("ping", &["-c", "1", "-W", "1", gw])?;
    let cap = Regex::new(r"(?:time|temps)[=<]([\d.]+)\s*ms")
        .ok()
        .and_then(|r| r.captures(&out))
        .or_else(|| {
            Regex::new(r"rtt[^=]*=\s*[\d.]+/([\d.]+)/")
                .ok()
                .and_then(|r| r.captures(&out))
        })?;
    cap[1].parse::<f64>().ok().map(|v| v.round() as i64)
}

pub fn analyser(persister: bool) -> Value {
    let (dev, nature, conn) = interface_active();
    if dev.is_empty() {
        return json!({ "ok": true, "connecte": false });
    }
    let mut out = Map::new();
    out.insert("ok".into(), json!(true));
    out.insert("connecte".into(), json!(true));
    out.insert("interface".into(), json!(dev));
    out.insert("nature".into(), json!(nature));
    out.insert("connexion".into(), json!(conn));
    if nature == "wifi" {
        wifi_info(&dev, &mut out);
    }
    adresse_info(&dev, &mut out);
    trafic_info(&dev, persister, &mut out);
    if let Some(v) = vpn_name() {
        out.insert("vpn".into(), json!(v));
    }
    if let Some(gw) = out.get("passerelle").and_then(|v| v.as_str()).map(|s| s.to_string()) {
        if let Some(ms) = latence_ms(&gw) {
            out.insert("latence_ms".into(), json!(ms));
        }
    }
    out.insert("hote".into(), json!(hostname()));
    Value::Object(out)
}

pub fn run(args: &[String]) -> i32 {
    let force = args.iter().any(|a| a == "--force");
    let cache_path = quickshell_cache_dir().join("reseau_cache.json");
    if !force {
        if let Some(mut cached) = read_json::<Map<String, Value>>(&cache_path) {
            let ts = cached.remove("analyse_ts").and_then(|v| v.as_f64()).unwrap_or(0.0);
            if (now_secs() - ts) < 1.5 {
                return crate::common::contrat::sortir(&Value::Object(cached));
            }
        }
    }
    let val = analyser(true);
    if let Value::Object(mut m) = val.clone() {
        m.insert("analyse_ts".into(), json!(now_secs()));
        let _ = write_json_atomic(&cache_path, &m, 0o644);
    }
    crate::common::contrat::sortir(&val)
}
