use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{core_dir, runtime_dir};
use serde_json::{json, Map, Value};
use std::fs;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TEMP_DEFAUT: i64 = 4000;
const TEMP_MIN: i64 = 2200;
const TEMP_MAX: i64 = 6500;

fn style_path() -> PathBuf {
    core_dir().join("style_vars.json")
}

fn read_style() -> Map<String, Value> {
    match read_json_value(&style_path()) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

fn write_style_key(cle: &str, val: Value) {
    let p = style_path();
    let mut m = read_style();
    m.insert(cle.into(), val);
    let _ = write_json_atomic(&p, &Value::Object(m), 0o644);
}

fn signature() -> Option<String> {
    if let Ok(sig) = std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if !sig.is_empty() {
            return Some(sig);
        }
    }
    let base = runtime_dir().join("hypr");
    let mut entries: Vec<String> = fs::read_dir(&base)
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    entries.sort();
    entries.pop()
}

fn socket_path() -> PathBuf {
    let base = runtime_dir().join("hypr");
    match signature() {
        Some(sig) => base.join(sig).join(".hyprsunset.sock"),
        None => base.join("absent").join(".hyprsunset.sock"),
    }
}

fn daemon_vivant() -> bool {
    let sock = socket_path();
    if !sock.exists() {
        return false;
    }
    if let Ok(stream) = UnixStream::connect(&sock) {
        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
        return true;
    }
    false
}

fn demarrer_daemon() -> bool {
    if daemon_vivant() {
        return true;
    }
    let _ = fs::remove_file(socket_path());
    let mut cmd = Command::new("hyprsunset");
    cmd.arg("-i")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if let Some(sig) = signature() {
        cmd.env("HYPRLAND_INSTANCE_SIGNATURE", sig);
    }
    if cmd.spawn().is_err() {
        return false;
    }
    for _ in 0..30 {
        if daemon_vivant() {
            return true;
        }
        thread::sleep(Duration::from_millis(100));
    }
    false
}

fn hyprctl_sunset(args: &[&str]) -> bool {
    let mut cmd = Command::new("hyprctl");
    cmd.arg("hyprsunset").args(args).stdin(Stdio::null());
    if let Some(sig) = signature() {
        cmd.env("HYPRLAND_INSTANCE_SIGNATURE", sig);
    }
    cmd.output().map(|o| o.status.success()).unwrap_or(false)
}

fn appliquer_filtre(temp: Option<i64>) -> bool {
    let temp_str = temp.map(|t| t.to_string()).unwrap_or_default();
    let args: Vec<&str> = match temp {
        None => vec!["identity"],
        Some(_) => vec!["temperature", temp_str.as_str()],
    };
    for essai in 0..2 {
        if !demarrer_daemon() {
            return false;
        }
        if hyprctl_sunset(&args) {
            return true;
        }
        if essai == 0 {
            let _ = fs::remove_file(socket_path());
            thread::sleep(Duration::from_millis(200));
        }
    }
    false
}

pub fn etat() -> Value {
    let d = read_style();
    let allume = d.get("night_mode").and_then(|v| v.as_bool()).unwrap_or(false);
    let temp = d
        .get("night_temp")
        .and_then(|v| v.as_f64())
        .map(|v| v as i64)
        .unwrap_or(TEMP_DEFAUT);
    let de = d.get("night_from").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let a = d.get("night_to").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let plage = !de.trim().is_empty();
    let has_hyprsunset = run_cmd_stdout("which", &["hyprsunset"]).is_some();
    json!({
        "allume": allume,
        "temperature": temp,
        "de": de,
        "a": a,
        "plage": plage,
        "daemon": daemon_vivant(),
        "hyprsunset": has_hyprsunset,
    })
}

fn parse_hhmm(s: &str) -> Option<i32> {
    let (h_s, m_s) = s.trim().split_once(':')?;
    let h: i32 = h_s.parse().ok()?;
    let m: i32 = m_s.parse().ok()?;
    if (0..24).contains(&h) && (0..60).contains(&m) {
        Some(h * 60 + m)
    } else {
        None
    }
}

fn local_minute_of_day() -> i32 {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as libc::time_t)
        .unwrap_or(0);
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&secs, &mut tm) };
    tm.tm_hour * 60 + tm.tm_min
}

fn dans_la_plage(now: i32, debut: i32, fin: i32) -> bool {
    if debut <= fin {
        now >= debut && now < fin
    } else {
        now >= debut || now < fin
    }
}

fn appliquer() -> Value {
    let e = etat();
    let plage = e.get("plage").and_then(|v| v.as_bool()).unwrap_or(false);
    if !plage {
        return e;
    }
    let de = e.get("de").and_then(|v| v.as_str()).unwrap_or("");
    let a = e.get("a").and_then(|v| v.as_str()).unwrap_or("");
    let (Some(debut), Some(fin)) = (parse_hhmm(de), parse_hhmm(a)) else {
        return e;
    };
    let vouloir = dans_la_plage(local_minute_of_day(), debut, fin);
    let allume = e.get("allume").and_then(|v| v.as_bool()).unwrap_or(false);
    let temp = e.get("temperature").and_then(|v| v.as_i64()).unwrap_or(TEMP_DEFAUT);
    let daemon = e.get("daemon").and_then(|v| v.as_bool()).unwrap_or(false);

    if vouloir != allume {
        write_style_key("night_mode", json!(vouloir));
        appliquer_filtre(if vouloir { Some(temp) } else { None });
        return etat();
    } else if vouloir && !daemon {
        appliquer_filtre(Some(temp));
    }
    e
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("etat");
    match action {
        "etat" => sortir(&etat()),
        "activer" | "desactiver" | "basculer" => {
            let e = etat();
            let allume = e.get("allume").and_then(|v| v.as_bool()).unwrap_or(false);
            let temp = e.get("temperature").and_then(|v| v.as_i64()).unwrap_or(TEMP_DEFAUT);
            let vouloir = match action {
                "basculer" => !allume,
                "activer" => true,
                _ => false,
            };
            write_style_key("night_mode", json!(vouloir));
            appliquer_filtre(if vouloir { Some(temp) } else { None });
            sortir(&etat())
        }
        "temperature" if args.len() > 1 => {
            let t = args[1]
                .parse::<i64>()
                .unwrap_or(TEMP_DEFAUT)
                .clamp(TEMP_MIN, TEMP_MAX);
            write_style_key("night_temp", json!(t));
            let e = etat();
            if e.get("allume").and_then(|v| v.as_bool()).unwrap_or(false) {
                appliquer_filtre(Some(t));
            }
            sortir(&etat())
        }
        "plage" => {
            let de = args.get(1).map(|s| s.trim()).unwrap_or("");
            let a = args.get(2).map(|s| s.trim()).unwrap_or("");
            write_style_key("night_from", json!(de));
            write_style_key("night_to", json!(a));
            sortir(&appliquer())
        }
        "appliquer" => sortir(&appliquer()),
        _ => sortir(&etat()),
    }
}
