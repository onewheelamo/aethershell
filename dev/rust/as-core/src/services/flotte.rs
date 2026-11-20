use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{core_dir, hostname, runtime_dir};
use serde_json::{json, Map, Value};
use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

const MESURE_PY: &str = r#"
import json, os, subprocess
def lire(p):
    try: return open(p).read()
    except OSError: return ""
charge = lire("/proc/loadavg").split()[:1]
memo = {}
for l in lire("/proc/meminfo").splitlines():
    c = l.split()
    if len(c) >= 2 and c[0] in ("MemTotal:", "MemAvailable:"):
        memo[c[0]] = int(c[1])
tot = memo.get("MemTotal:", 0); dispo = memo.get("MemAvailable:", 0)
shell = subprocess.run(["pgrep", "-x", "quickshell"], capture_output=True).returncode == 0
up = float(lire("/proc/uptime").split()[0] or 0)
print(json.dumps({
    "charge": charge[0] if charge else "",
    "ram_pct": round(100 * (tot - dispo) / tot) if tot else None,
    "shell": shell,
    "barre": shell,
    "uptime_j": round(up / 86400, 1),
}))
"#;

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn local_mesure() -> Value {
    let charge = fs::read_to_string("/proc/loadavg")
        .ok()
        .and_then(|s| s.split_whitespace().next().map(|x| x.to_string()))
        .unwrap_or_default();
    let mut tot = 0u64;
    let mut avail = 0u64;
    if let Ok(mem) = fs::read_to_string("/proc/meminfo") {
        for l in mem.lines() {
            let mut cols = l.split_whitespace();
            let Some(k) = cols.next() else { continue };
            let Some(v) = cols.next().and_then(|s| s.parse::<u64>().ok()) else { continue };
            if k == "MemTotal:" { tot = v; }
            if k == "MemAvailable:" { avail = v; }
        }
    }
    let ram_pct = if tot > 0 {
        Some(((100.0 * (tot.saturating_sub(avail)) as f64 / tot as f64).round()) as i64)
    } else {
        None
    };
    let shell = run_cmd_stdout("pgrep", &["-x", "quickshell"]).is_some();
    let up_s = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|x| x.parse::<f64>().ok()))
        .unwrap_or(0.0);
    let uptime_j = ((up_s / 86400.0) * 10.0).round() / 10.0;

    json!({
        "nom": hostname(),
        "charge": charge,
        "ram_pct": ram_pct,
        "shell": shell,
        "barre": shell,
        "uptime_j": uptime_j,
    })
}

fn distant_mesure(cible: &str) -> Option<Map<String, Value>> {
    let mut child = Command::new("ssh")
        .args([
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=3",
            "-o", "StrictHostKeyChecking=accept-new",
            cible,
            "python3", "-",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    if let Some(mut sin) = child.stdin.take() {
        let _ = sin.write_all(MESURE_PY.as_bytes());
    }
    let out = child.wait_with_output().ok()?;
    if !out.status.success() {
        return None;
    }
    let txt = String::from_utf8_lossy(&out.stdout);
    let last = txt.trim().lines().last()?;
    serde_json::from_str::<Map<String, Value>>(last).ok()
}

pub fn run(args: &[String]) -> i32 {
    let cfg = read_json_value(&core_dir().join("flotte.json"));
    let machines = cfg
        .get("machines")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    let cache_path = runtime_dir().join("quickshell").join("flotte-etat.json");
    let prev = read_json_value(&cache_path);

    let mut mach_map = Map::new();
    for m in machines {
        let cible = m.get("cible").and_then(|v| v.as_str()).unwrap_or("");
        let nom = m
            .get("nom")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .unwrap_or(if cible.is_empty() { "?" } else { cible })
            .to_string();
        if let Some(mut res) = if !cible.is_empty() { distant_mesure(cible) } else { None } {
            res.insert("nom".into(), json!(nom));
            res.insert("joignable".into(), json!(true));
            res.insert("quand".into(), json!(now_secs()));
            mach_map.insert(nom, Value::Object(res));
        } else {
            let vieux = prev.get("machines").and_then(|v| v.get(&nom));
            mach_map.insert(
                nom.clone(),
                json!({
                    "nom": nom,
                    "joignable": false,
                    "derniere_vue": vieux.and_then(|v| v.get("quand")).cloned().unwrap_or(Value::Null),
                    "charge": vieux.and_then(|v| v.get("charge")).cloned().unwrap_or(Value::Null),
                    "ram_pct": vieux.and_then(|v| v.get("ram_pct")).cloned().unwrap_or(Value::Null),
                    "barre": vieux.and_then(|v| v.get("barre")).cloned().unwrap_or(Value::Null),
                    "uptime_j": vieux.and_then(|v| v.get("uptime_j")).cloned().unwrap_or(Value::Null),
                }),
            );
        }
    }

    let etat = json!({
        "quand": now_secs(),
        "machines": Value::Object(mach_map.clone()),
        "local": local_mesure(),
    });
    let _ = write_json_atomic(&cache_path, &etat, 0o644);

    if args.iter().any(|a| a == "--brut") {
        if let Ok(s) = serde_json::to_string_pretty(&etat) {
            println!("{s}");
        }
        return 0;
    }

    let dist_count = mach_map.len();
    if dist_count == 0 {
        return sortir(&json!({
            "ok": true,
            "compact": { "valeur": "", "libelle": "flotte non configurée", "alerte": false },
            "detail": { "flotte": etat },
            "applet": "flotte",
            "icone": "cloud",
            "alerte": false,
        }));
    }
    let muettes = mach_map
        .values()
        .filter(|v| !v.get("joignable").and_then(|b| b.as_bool()).unwrap_or(false))
        .count();
    let barres_off = mach_map
        .values()
        .filter(|v| {
            v.get("joignable").and_then(|b| b.as_bool()).unwrap_or(false)
                && !v.get("barre").and_then(|b| b.as_bool()).unwrap_or(false)
        })
        .count();
    let alerte = muettes > 0 || barres_off > 0;
    let valeur = if alerte { (muettes + barres_off).to_string() } else { String::new() };
    let libelle = if muettes > 0 {
        "injoignable".to_string()
    } else if barres_off > 0 {
        "barre arrêtée".to_string()
    } else {
        format!("{dist_count} machine(s) en ligne")
    };

    sortir(&json!({
        "ok": true,
        "compact": { "valeur": valeur, "libelle": libelle, "alerte": alerte },
        "detail": { "flotte": etat },
        "applet": "flotte",
        "icone": "cloud",
        "alerte": alerte,
    }))
}
