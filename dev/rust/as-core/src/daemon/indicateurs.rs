use crate::common::io::run_cmd_stdout;
use serde_json::json;
use std::fs;
use std::path::Path;

const VIDEO_PROCS: &[&str] = &["wf-recorder", "wl-screenrec", "gpu-screen-recorder", "obs"];
const IGNORED_AUDIO_APPS: &[&str] = &["cava", "pwscope", "pavucontrol"];

pub fn detect_vpn() -> &'static str {
    if let Some(out) = run_cmd_stdout("nmcli", &["-t", "-f", "NAME,TYPE,STATE", "connection", "show"]) {
        let mut has_activating = false;
        for line in out.lines() {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() < 3 {
                continue;
            }
            let nature = parts[1].trim();
            let state = parts[2].trim();
            if matches!(nature, "wireguard" | "vpn" | "tun") {
                if state == "activated" {
                    return "connected";
                }
                if matches!(state, "activating" | "deactivating") {
                    has_activating = true;
                }
            }
        }
        if has_activating {
            return "error";
        }
    }

    if let Ok(entries) = fs::read_dir("/sys/class/net") {
        for entry in entries.flatten() {
            let iface = entry.file_name().to_string_lossy().to_string();
            if iface.starts_with("tun")
                || iface.starts_with("tap")
                || iface.starts_with("wg")
                || iface.starts_with("proton")
                || iface.starts_with("mullvad")
            {
                let op = entry.path().join("operstate");
                if let Ok(state) = fs::read_to_string(op) {
                    let s = state.trim().to_ascii_lowercase();
                    if s == "up" || s == "unknown" {
                        return "connected";
                    }
                }
            }
        }
    }

    if let Some(out) = run_cmd_stdout(
        "systemctl",
        &["is-failed", "mullvad-daemon", "openvpn-client@*", "wg-quick@*"],
    ) {
        if out.lines().any(|l| l.trim() == "failed") {
            return "error";
        }
    }

    "disconnected"
}

pub fn detect_video_capture() -> bool {
    let Ok(entries) = fs::read_dir("/proc") else {
        return false;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let pid_str = name.to_string_lossy();
        if !pid_str.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let p: &Path = &entry.path();
        if let Ok(comm) = fs::read_to_string(p.join("comm")) {
            if VIDEO_PROCS.contains(&comm.trim()) {
                return true;
            }
        }
        if let Ok(fds) = fs::read_dir(p.join("fd")) {
            for fd in fds.flatten() {
                if let Ok(target) = fs::read_link(fd.path()) {
                    if target.to_string_lossy().starts_with("/dev/video") {
                        return true;
                    }
                }
            }
        }
    }
    false
}

pub fn detect_audio_capture() -> bool {
    let Some(out) = run_cmd_stdout("pactl", &["list", "source-outputs"]) else {
        return false;
    };
    if out.trim().is_empty() {
        return false;
    }
    for blk in out.split("Source Output #").skip(1) {
        let lower = blk.to_ascii_lowercase();
        if lower.contains(".monitor") {
            continue;
        }
        if IGNORED_AUDIO_APPS.iter().any(|app| lower.contains(app)) {
            continue;
        }
        return true;
    }
    false
}

pub fn run() -> i32 {
    let vpn = detect_vpn();
    let capture = if detect_video_capture() {
        "video"
    } else if detect_audio_capture() {
        "audio"
    } else {
        "none"
    };
    let val = json!({ "vpn": vpn, "capture": capture });
    crate::common::contrat::sortir(&val)
}
