use crate::common::contrat::sortir;
use crate::common::io::{run_cmd, run_cmd_stdout};
use glob::glob;
use serde_json::json;
use std::fs;
use std::path::PathBuf;

fn list_video_devices() -> Vec<String> {
    let mut devs: Vec<String> = glob("/dev/video*")
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .map(|p| p.to_string_lossy().to_string())
        .collect();
    devs.sort();
    devs
}

fn detect_tool() -> Option<&'static str> {
    if run_cmd_stdout("which", &["zbarcam"]).is_some() {
        Some("zbarcam")
    } else if run_cmd_stdout("which", &["ffmpeg"]).is_some()
        && run_cmd_stdout("which", &["zbarimg"]).is_some()
    {
        Some("ffmpeg")
    } else {
        None
    }
}

fn parse_wifi_qr(raw: &str) -> (String, String) {
    let s = raw.trim();
    let Some(rest) = s.strip_prefix("WIFI:") else {
        return (String::new(), s.to_string());
    };
    let mut ssid = String::new();
    let mut pwd = String::new();
    for part in rest.split(';') {
        if let Some(v) = part.strip_prefix("S:") {
            ssid = v.to_string();
        } else if let Some(v) = part.strip_prefix("P:") {
            pwd = v.to_string();
        }
    }
    (ssid, pwd)
}

fn scan_with_zbarcam(dev: &str) -> Option<String> {
    let out = run_cmd_stdout("timeout", &["35", "zbarcam", "--raw", "--oneshot", "-q", dev])?;
    out.lines().next().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

fn scan_with_ffmpeg(dev: &str) -> Option<String> {
    let tmp = std::env::temp_dir().join(format!("qs-qr-{}", std::process::id()));
    let _ = fs::create_dir_all(&tmp);
    let pat = tmp.join("f_%03d.png");
    let _ = run_cmd(
        "ffmpeg",
        &["-y", "-f", "v4l2", "-i", dev, "-t", "12", "-vf", "fps=2", &pat.to_string_lossy()],
    );
    let mut found = None;
    if let Ok(entries) = fs::read_dir(&tmp) {
        let mut imgs: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
        imgs.sort();
        for img in imgs {
            if let Some(out) = run_cmd_stdout("zbarimg", &["--raw", "-q", &img.to_string_lossy()]) {
                if let Some(line) = out.lines().next() {
                    let t = line.trim();
                    if !t.is_empty() {
                        found = Some(t.to_string());
                        break;
                    }
                }
            }
        }
    }
    let _ = fs::remove_dir_all(&tmp);
    found
}

pub fn run(args: &[String]) -> i32 {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("status");
    if cmd == "status" {
        let devs = list_video_devices();
        let tool = detect_tool().unwrap_or("");
        return sortir(&json!({
            "available": !devs.is_empty() && !tool.is_empty(),
            "devices": devs,
            "tool": tool,
        }));
    }
    if cmd == "scan" {
        let devs = list_video_devices();
        if devs.is_empty() {
            sortir(&json!({ "ok": false, "error": "Aucune webcam détectée" }));
            return 1;
        }
        let Some(tool) = detect_tool() else {
            sortir(&json!({ "ok": false, "error": "Outil zbarcam/zbarimg manquant" }));
            return 1;
        };
        let mut raw = None;
        for dev in devs.iter().take(4) {
            raw = if tool == "zbarcam" {
                scan_with_zbarcam(dev)
            } else {
                scan_with_ffmpeg(dev)
            };
            if raw.is_some() {
                break;
            }
        }
        let Some(data) = raw else {
            sortir(&json!({ "ok": false, "error": "Scan annulé ou aucun QR code lu" }));
            return 1;
        };
        let (ssid, password) = parse_wifi_qr(&data);
        return sortir(&json!({
            "ok": true,
            "ssid": ssid,
            "password": password,
        }));
    }
    sortir(&json!({ "ok": false, "error": format!("Commande inconnue : {cmd}") }));
    2
}
