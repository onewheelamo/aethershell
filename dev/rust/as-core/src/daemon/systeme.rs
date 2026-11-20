use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{parse_options_arg, read_json, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{quickshell_cache_dir, runtime_dir};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::ffi::CString;
use std::fs;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const CACHE_TTL: f64 = 3.0;
const SEUIL_ATTENTION: f64 = 60.0;
const SEUIL_CRITIQUE: f64 = 85.0;
const TEMP_ATTENTION: f64 = 70.0;
const TEMP_CRITIQUE: f64 = 85.0;
const MESURES_DEFAUT: &[&str] = &["cpu", "ram", "gpu", "temp"];
const MESURES: &[&str] = &["cpu", "ram", "gpu", "temp", "load", "swap", "disk", "net"];

#[derive(Clone, Serialize, Deserialize)]
struct CpuState {
    total: u64,
    idle: u64,
    coeurs: HashMap<String, [u64; 2]>,
    ts: f64,
}

#[derive(Clone, Serialize, Deserialize)]
struct NetState {
    rx: u64,
    tx: u64,
    ts: f64,
}

static MEM_CPU: Mutex<Option<CpuState>> = Mutex::new(None);
static MEM_NET: Mutex<Option<NetState>> = Mutex::new(None);
static CPU_NOM_CACHE: OnceLock<String> = OnceLock::new();
static MONO_ORIGIN: OnceLock<Instant> = OnceLock::new();

fn mono_secs() -> f64 {
    MONO_ORIGIN.get_or_init(Instant::now).elapsed().as_secs_f64()
}

fn unix_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn round1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

fn read_stat() -> Option<(u64, u64, HashMap<String, [u64; 2]>)> {
    let txt = fs::read_to_string("/proc/stat").ok()?;
    let mut total = 0u64;
    let mut idle = 0u64;
    let mut coeurs = HashMap::new();
    for line in txt.lines() {
        let mut parts = line.split_whitespace();
        let Some(nom) = parts.next() else { continue };
        if nom == "cpu" {
            let vals: Vec<u64> = parts.filter_map(|s| s.parse().ok()).collect();
            total = vals.iter().sum();
            idle = vals.get(3).copied().unwrap_or(0) + vals.get(4).copied().unwrap_or(0);
        } else if let Some(rest) = nom.strip_prefix("cpu") {
            if !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit()) {
                let vals: Vec<u64> = parts.filter_map(|s| s.parse().ok()).collect();
                let ct: u64 = vals.iter().sum();
                let ci: u64 = vals.get(3).copied().unwrap_or(0) + vals.get(4).copied().unwrap_or(0);
                coeurs.insert(nom.to_string(), [ct, ci]);
            }
        } else if !nom.starts_with("cpu") {
            break;
        }
    }
    Some((total, idle, coeurs))
}

fn cpu_freq_ghz() -> Option<f64> {
    let txt = fs::read_to_string("/proc/cpuinfo").ok()?;
    let mut sum = 0.0;
    let mut count = 0usize;
    for line in txt.lines() {
        if line.starts_with("cpu MHz") {
            if let Some((_, val)) = line.split_once(':') {
                if let Ok(mhz) = val.trim().parse::<f64>() {
                    sum += mhz;
                    count += 1;
                }
            }
        }
    }
    if count == 0 { None } else { Some(round2(sum / count as f64 / 1000.0)) }
}

fn cpu_nom() -> &'static str {
    CPU_NOM_CACHE.get_or_init(|| {
        let mut nom = String::new();
        if let Ok(txt) = fs::read_to_string("/proc/cpuinfo") {
            for line in txt.lines() {
                if line.to_ascii_lowercase().starts_with("model name") {
                    if let Some((_, rhs)) = line.split_once(':') {
                        nom = rhs.trim().to_string();
                        break;
                    }
                }
            }
        }
        if !nom.is_empty() {
            for pat in [
                r"\((?:R|TM|tm|r)\)",
                r"(?i)\s*@\s*[\d.]+\s*GHz",
                r"(?i)\b\d+-Core Processor\b",
                r"\bCPU\b",
            ] {
                if let Ok(re) = Regex::new(pat) {
                    nom = re.replace_all(&nom, "").to_string();
                }
            }
            nom = nom.split_whitespace().collect::<Vec<_>>().join(" ");
        }
        if nom.is_empty() { "CPU".to_string() } else { nom }
    })
}

fn cpu_mesures(persister: bool) -> (Option<f64>, Vec<f64>, Option<f64>) {
    let mut now = mono_secs();
    let Some((mut total2, mut idle2, mut coeurs2)) = read_stat() else {
        return (None, vec![], None);
    };
    let cpu_state_path = runtime_dir().join("qs-systeme-cpu.json");
    let prev: Option<CpuState> = if persister {
        read_json(&cpu_state_path)
    } else {
        MEM_CPU.lock().ok().and_then(|g| g.clone())
    };

    let mut total1: Option<u64> = None;
    let mut idle1: u64 = 0;
    let mut coeurs1: HashMap<String, [u64; 2]> = HashMap::new();
    if let Some(p) = prev {
        let dt_ts = now - p.ts;
        if dt_ts > 0.0 && dt_ts <= 30.0 {
            total1 = Some(p.total);
            idle1 = p.idle;
            coeurs1 = p.coeurs;
        }
    }

    if total1.is_none() || total2 <= total1.unwrap_or(0) {
        total1 = Some(total2);
        idle1 = idle2;
        coeurs1 = coeurs2.clone();
        thread::sleep(Duration::from_millis(200));
        if let Some((t2, i2, c2)) = read_stat() {
            total2 = t2;
            idle2 = i2;
            coeurs2 = c2;
            now = mono_secs();
        }
    }

    let next_state = CpuState {
        total: total2,
        idle: idle2,
        coeurs: coeurs2.clone(),
        ts: now,
    };
    if persister {
        let _ = write_json_atomic(&cpu_state_path, &next_state, 0o644);
    } else if let Ok(mut g) = MEM_CPU.lock() {
        *g = Some(next_state);
    }

    let t1 = total1.unwrap_or(total2);
    let dt = total2.saturating_sub(t1);
    let di = idle2.saturating_sub(idle1);
    if dt == 0 {
        return (None, vec![], None);
    }
    let pct = (100.0 * (dt.saturating_sub(di)) as f64 / dt as f64).clamp(0.0, 100.0);

    let mut core_keys: Vec<String> = coeurs2.keys().cloned().collect();
    core_keys.sort_by_key(|k| k[3..].parse::<usize>().unwrap_or(0));
    let mut coeurs_pct = Vec::with_capacity(core_keys.len());
    for k in core_keys {
        let [t2, i2] = coeurs2[&k];
        if let Some(&[t1c, i1c]) = coeurs1.get(&k) {
            if t2 > t1c {
                let cdt = t2 - t1c;
                let cdi = i2.saturating_sub(i1c);
                let cp = (100.0 * (cdt.saturating_sub(cdi)) as f64 / cdt as f64).clamp(0.0, 100.0);
                coeurs_pct.push(round1(cp));
                continue;
            }
        }
        coeurs_pct.push(round1(pct));
    }
    (Some(pct), coeurs_pct, cpu_freq_ghz())
}

struct MemInfo {
    ram_pct: f64,
    utilisee_go: f64,
    dispo_go: f64,
    totale_go: f64,
    buffers_go: f64,
    cache_go: f64,
    htop_go: f64,
    swap_pct: f64,
    swap_utilisee_go: f64,
    swap_totale_go: f64,
}

fn memoire_mesures() -> Option<MemInfo> {
    let txt = fs::read_to_string("/proc/meminfo").ok()?;
    let mut map: HashMap<&str, u64> = HashMap::new();
    for line in txt.lines() {
        if let Some((k, rest)) = line.split_once(':') {
            if let Some(val) = rest.split_whitespace().next().and_then(|s| s.parse::<u64>().ok()) {
                map.insert(k.trim(), val);
            }
        }
    }
    let total = *map.get("MemTotal")?;
    if total == 0 {
        return None;
    }
    let dispo = *map.get("MemAvailable").unwrap_or(&0);
    let utilises = total.saturating_sub(dispo);
    let buffers_kio = *map.get("Buffers").unwrap_or(&0);
    let cached_kio = *map.get("Cached").unwrap_or(&0) + *map.get("SReclaimable").unwrap_or(&0);
    let cache_kio = buffers_kio + cached_kio;
    let htop_kio = total
        .saturating_sub(*map.get("MemFree").unwrap_or(&0))
        .saturating_sub(cache_kio)
        + *map.get("Shmem").unwrap_or(&0);
    let swap_total = *map.get("SwapTotal").unwrap_or(&0);
    let swap_free = *map.get("SwapFree").unwrap_or(&0);
    let swap_util = swap_total.saturating_sub(swap_free);
    Some(MemInfo {
        ram_pct: 100.0 * utilises as f64 / total as f64,
        utilisee_go: round1(utilises as f64 / 1048576.0),
        dispo_go: round1(dispo as f64 / 1048576.0),
        totale_go: round1(total as f64 / 1048576.0),
        buffers_go: round1(buffers_kio as f64 / 1048576.0),
        cache_go: round1(cache_kio as f64 / 1048576.0),
        htop_go: round1(htop_kio as f64 / 1048576.0),
        swap_pct: if swap_total > 0 { 100.0 * swap_util as f64 / swap_total as f64 } else { 0.0 },
        swap_utilisee_go: round1(swap_util as f64 / 1048576.0),
        swap_totale_go: round1(swap_total as f64 / 1048576.0),
    })
}

struct GpuInfo {
    utilisation: f64,
    temperature: f64,
    vram_mb: f64,
    vram_total_mb: f64,
    power_w: Option<f64>,
}

fn gpu_nvidia() -> Option<GpuInfo> {
    if !Path::new("/dev/nvidia0").exists() && !Path::new("/dev/nvidiactl").exists() {
        return None;
    }
    let out = run_cmd_stdout(
        "nvidia-smi",
        &[
            "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
            "--format=csv,noheader,nounits",
        ],
    )?;
    let line = out.lines().next()?;
    let cols: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
    if cols.len() < 4 {
        return None;
    }
    Some(GpuInfo {
        utilisation: cols[0].parse().ok()?,
        temperature: cols[1].parse().ok()?,
        vram_mb: cols[2].parse().ok()?,
        vram_total_mb: cols[3].parse().ok()?,
        power_w: cols.get(4).and_then(|s| s.parse::<f64>().ok()).map(round1),
    })
}

fn read_int_file(p: &Path) -> Option<i64> {
    fs::read_to_string(p).ok()?.trim().parse().ok()
}

fn gpu_amd() -> Option<GpuInfo> {
    let mut cards: Vec<PathBuf> = fs::read_dir("/sys/class/drm")
        .ok()?
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .map(|n| n.starts_with("card") && n[4..].bytes().all(|b| b.is_ascii_digit()))
                .unwrap_or(false)
        })
        .collect();
    cards.sort();

    for card in cards {
        let dev = card.join("device");
        let vendor = fs::read_to_string(dev.join("vendor")).unwrap_or_default();
        let busy_path = dev.join("gpu_busy_percent");
        if vendor.trim().to_ascii_lowercase() != "0x1002" && !busy_path.is_file() {
            continue;
        }
        let Some(util) = read_int_file(&busy_path) else { continue };
        let mut vram_used = read_int_file(&dev.join("mem_info_vram_used")).unwrap_or(0);
        let mut vram_tot = read_int_file(&dev.join("mem_info_vram_total")).unwrap_or(0);
        if vram_tot <= 0 {
            vram_used = read_int_file(&dev.join("mem_info_gtt_used")).unwrap_or(0);
            vram_tot = read_int_file(&dev.join("mem_info_gtt_total")).unwrap_or(0);
        }

        let mut temp: Option<f64> = None;
        let mut power_w: Option<f64> = None;
        let hw_root = dev.join("hwmon");
        if let Ok(hws) = fs::read_dir(&hw_root) {
            let mut hw_paths: Vec<PathBuf> = hws.flatten().map(|e| e.path()).collect();
            hw_paths.sort();
            for hw in hw_paths {
                let mut temp_vals = Vec::new();
                if let Ok(entries) = fs::read_dir(&hw) {
                    let mut paths: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
                    paths.sort();
                    for tf in paths {
                        let fname = tf.file_name().and_then(|s| s.to_str()).unwrap_or("");
                        if fname.starts_with("temp") && fname.ends_with("_input") {
                            if let Some(mc) = read_int_file(&tf) {
                                let c = mc as f64 / 1000.0;
                                let lbl_p = hw.join(fname.replace("_input", "_label"));
                                let lbl = fs::read_to_string(lbl_p).unwrap_or_default().trim().to_ascii_lowercase();
                                if lbl == "edge" {
                                    temp = Some(c);
                                    break;
                                }
                                temp_vals.push(c);
                            }
                        }
                    }
                }
                if temp.is_none() {
                    temp = temp_vals.first().copied();
                }
                for pf in ["power1_average", "power1_input"] {
                    if let Some(uw) = read_int_file(&hw.join(pf)) {
                        power_w = Some(round1(uw as f64 / 1_000_000.0));
                        break;
                    }
                }
                if temp.is_some() || power_w.is_some() {
                    break;
                }
            }
        }

        return Some(GpuInfo {
            utilisation: util as f64,
            temperature: temp.map(round1).unwrap_or(0.0),
            vram_mb: round1(vram_used as f64 / (1024.0 * 1024.0)),
            vram_total_mb: round1(vram_tot as f64 / (1024.0 * 1024.0)),
            power_w,
        });
    }
    None
}

fn temp_cpu() -> Option<f64> {
    let mut candidats = Vec::new();
    let hws = fs::read_dir("/sys/class/hwmon").ok()?;
    for hw in hws.flatten() {
        let p = hw.path();
        let Ok(nom) = fs::read_to_string(p.join("name")) else { continue };
        let nom = nom.trim();
        if nom == "amdgpu" || nom == "nvme" || nom == "iwlwifi_1" {
            continue;
        }
        let Ok(entries) = fs::read_dir(&p) else { continue };
        for ent in entries.flatten() {
            let ep = ent.path();
            let fname = ep.file_name().and_then(|s| s.to_str()).unwrap_or("");
            if !(fname.starts_with("temp") && fname.ends_with("_input")) {
                continue;
            }
            let Some(mc) = read_int_file(&ep) else { continue };
            let c = mc as f64 / 1000.0;
            let lbl = fs::read_to_string(p.join(fname.replace("_input", "_label")))
                .unwrap_or_default()
                .trim()
                .to_string();
            if nom == "coretemp" && lbl.starts_with("Package") {
                return Some(c);
            }
            if matches!(nom, "k10temp" | "zenpower") && matches!(lbl.as_str(), "Tdie" | "Tctl") {
                return Some(c);
            }
            candidats.push(c);
        }
    }
    candidats.into_iter().reduce(f64::max)
}

fn tous_capteurs_et_ventilateurs() -> (Vec<(f64, String)>, Vec<(i64, String)>) {
    let mut capteurs = Vec::new();
    let mut ventilos = Vec::new();
    if let Ok(hws) = fs::read_dir("/sys/class/hwmon") {
        let mut hw_paths: Vec<PathBuf> = hws.flatten().map(|e| e.path()).collect();
        hw_paths.sort();
        for p in hw_paths {
            let Ok(nom) = fs::read_to_string(p.join("name")) else { continue };
            let nom = nom.trim().to_string();
            if let Ok(entries) = fs::read_dir(&p) {
                for ent in entries.flatten() {
                    let ep = ent.path();
                    let fname = ep.file_name().and_then(|s| s.to_str()).unwrap_or("");
                    if fname.starts_with("temp") && fname.ends_with("_input") {
                        if let Some(mc) = read_int_file(&ep) {
                            let val = mc as f64 / 1000.0;
                            if val > 0.0 && val < 150.0 {
                                let lbl = fs::read_to_string(p.join(fname.replace("_input", "_label")))
                                    .ok()
                                    .map(|s| s.trim().to_string())
                                    .filter(|s| !s.is_empty())
                                    .unwrap_or_else(|| nom.clone());
                                capteurs.push((val, lbl));
                            }
                        }
                    } else if fname.starts_with("fan") && fname.ends_with("_input") {
                        if let Some(rpm) = read_int_file(&ep) {
                            if rpm > 0 {
                                ventilos.push((rpm, nom.clone()));
                            }
                        }
                    }
                }
            }
        }
    }
    capteurs.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    capteurs.truncate(6);
    ventilos.truncate(4);
    (capteurs, ventilos)
}

fn statvfs_usage(mp: &str) -> Option<(f64, f64, f64)> {
    let c_mp = CString::new(mp).ok()?;
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::statvfs(c_mp.as_ptr(), &mut st) };
    if rc != 0 || st.f_blocks == 0 {
        return None;
    }
    let total = (st.f_blocks as u128) * (st.f_frsize as u128);
    let avail = (st.f_bavail as u128) * (st.f_frsize as u128);
    if total == 0 {
        return None;
    }
    let used = total.saturating_sub(avail);
    let pct = 100.0 * used as f64 / total as f64;
    Some((
        round1(used as f64 / 1073741824.0),
        round1(total as f64 / 1073741824.0),
        round1(pct),
    ))
}

fn systemes_fichiers_locaux() -> Vec<(String, f64, f64, f64)> {
    let types_ok = ["ext4", "btrfs", "xfs", "vfat", "ntfs", "fuseblk", "zfs", "f2fs", "ext3"];
    let mut vus = HashSet::new();
    let mut out = Vec::new();
    if let Ok(mounts) = fs::read_to_string("/proc/mounts") {
        for line in mounts.lines() {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() < 3 {
                continue;
            }
            let (dev, mp, fs_type) = (cols[0], cols[1], cols[2]);
            if !types_ok.contains(&fs_type) || !vus.insert(dev.to_string()) {
                continue;
            }
            if let Some((u, t, p)) = statvfs_usage(mp) {
                out.push((mp.to_string(), u, t, p));
                if out.len() >= 5 {
                    break;
                }
            }
        }
    }
    out
}

fn read_net_dev() -> (u64, u64) {
    let mut rx = 0u64;
    let mut tx = 0u64;
    if let Ok(txt) = fs::read_to_string("/proc/net/dev") {
        for line in txt.lines().skip(2) {
            let Some((iface, rest)) = line.split_once(':') else { continue };
            if iface.trim() == "lo" {
                continue;
            }
            let cols: Vec<&str> = rest.split_whitespace().collect();
            if cols.len() >= 10 {
                rx += cols[0].parse::<u64>().unwrap_or(0);
                tx += cols[8].parse::<u64>().unwrap_or(0);
            }
        }
    }
    (rx, tx)
}

fn format_debit(bps: f64) -> String {
    if bps >= 1048576.0 {
        format!("{:.1} M/s", bps / 1048576.0)
    } else if bps >= 1024.0 {
        format!("{:.0} K/s", bps / 1024.0)
    } else {
        format!("{bps:.0} o/s")
    }
}

fn reseau_debits(persister: bool) -> Option<Value> {
    let now = mono_secs();
    let (rx2, tx2) = read_net_dev();
    let net_path = runtime_dir().join("qs-systeme-net.json");
    let prev: Option<NetState> = if persister {
        read_json(&net_path)
    } else {
        MEM_NET.lock().ok().and_then(|g| g.clone())
    };
    let mut rx_bps = 0.0;
    let mut tx_bps = 0.0;
    if let Some(p) = prev {
        let dt = now - p.ts;
        if (0.05..=30.0).contains(&dt) {
            rx_bps = (rx2.saturating_sub(p.rx) as f64) / dt;
            tx_bps = (tx2.saturating_sub(p.tx) as f64) / dt;
        }
    }
    let next = NetState { rx: rx2, tx: tx2, ts: now };
    if persister {
        let _ = write_json_atomic(&net_path, &next, 0o644);
    } else if let Ok(mut g) = MEM_NET.lock() {
        *g = Some(next);
    }
    let pct = ((rx_bps + tx_bps) / (50.0 * 1048576.0) * 100.0).min(100.0);
    Some(json!({
        "rx_kio": round1(rx_bps / 1024.0),
        "tx_kio": round1(tx_bps / 1024.0),
        "rx_texte": format_debit(rx_bps),
        "tx_texte": format_debit(tx_bps),
        "pct": round1(pct),
    }))
}

fn uptime_info() -> Option<Value> {
    let txt = fs::read_to_string("/proc/uptime").ok()?;
    let sec = txt.split_whitespace().next()?.parse::<f64>().ok()? as u64;
    let mins = (sec / 60) % 60;
    let heures = (sec / 3600) % 24;
    let jours = sec / 86400;
    let texte = if jours > 0 {
        format!("{jours}j {heures}h")
    } else if sec >= 3600 {
        format!("{}h{:02}", sec / 3600, mins)
    } else {
        format!("{}m", (sec / 60).max(1))
    };
    Some(json!({ "secondes": sec, "texte": texte }))
}

fn load_mesures() -> Option<Value> {
    let txt = fs::read_to_string("/proc/loadavg").ok()?;
    let mut parts = txt.split_whitespace();
    let l1: f64 = parts.next()?.parse().ok()?;
    let l5: f64 = parts.next()?.parse().ok()?;
    let l15: f64 = parts.next()?.parse().ok()?;
    let coeurs = thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    let pct = (100.0 * l1 / coeurs as f64).min(100.0);
    Some(json!({
        "l1": round2(l1),
        "l5": round2(l5),
        "l15": round2(l15),
        "coeurs": coeurs,
        "pct": round1(pct),
    }))
}

fn psi(kind: &str) -> String {
    let Ok(txt) = fs::read_to_string(format!("/proc/pressure/{kind}")) else {
        return String::new();
    };
    let mut some = None;
    let mut full = None;
    for line in txt.lines() {
        let mut parts = line.split_whitespace();
        let Some(cle) = parts.next() else { continue };
        for field in parts {
            if let Some(v) = field.strip_prefix("avg10=") {
                if let Ok(val) = v.parse::<f64>() {
                    if cle == "some" { some = Some(val); }
                    if cle == "full" { full = Some(val); }
                }
                break;
            }
        }
    }
    match (some, full) {
        (Some(s), Some(f)) => format!("some {s:.1}% · full {f:.1}%"),
        (Some(s), None) => format!("some {s:.1}%"),
        _ => String::new(),
    }
}

fn zombies_proc() -> u64 {
    let mut z = 0u64;
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            if !ent.file_name().to_string_lossy().bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            if let Ok(st) = fs::read_to_string(ent.path().join("stat")) {
                if let Some((_, rest)) = st.rsplit_once(')') {
                    if rest.trim_start().starts_with('Z') {
                        z += 1;
                    }
                }
            }
        }
    }
    z
}

fn systemd_failed(user: bool) -> Vec<String> {
    let args: Vec<&str> = if user {
        vec!["--user", "--failed", "--no-legend", "--plain", "--no-pager"]
    } else {
        vec!["--failed", "--no-legend", "--plain", "--no-pager"]
    };
    let Some(out) = run_cmd_stdout("systemctl", &args) else {
        return vec![];
    };
    let mut unites = Vec::new();
    for line in out.lines() {
        let mut cols = line.split_whitespace();
        if let Some(first) = cols.next() {
            if first != "●" {
                unites.push(first.to_string());
            } else if let Some(second) = cols.next() {
                unites.push(second.to_string());
            }
        }
    }
    unites
}

fn niveau(v: f64, att: f64, crit: f64) -> &'static str {
    if v >= crit { "critique" } else if v >= att { "attention" } else { "ok" }
}

fn mk_barre(cle: &str, valeur: f64, texte: &str) -> Map<String, Value> {
    let (nom, icone) = match cle {
        "cpu" => ("CPU", "cpu"),
        "ram" => ("RAM", "ram"),
        "gpu" => ("GPU", "gpu"),
        "temp" => ("Temp", "temp"),
        "load" => ("Load", "load"),
        "swap" => ("Swap", "swap"),
        "disk" => ("Disque", "disque"),
        "net" => ("Réseau", "reseau"),
        _ => (cle, cle),
    };
    let (niv, remp) = match cle {
        "temp" => (niveau(valeur, TEMP_ATTENTION, TEMP_CRITIQUE), ((valeur - 30.0) / 70.0 * 100.0).clamp(0.0, 100.0)),
        "disk" => (niveau(valeur, 80.0, 92.0), valeur.clamp(0.0, 100.0)),
        "net" => ("ok", valeur.clamp(0.0, 100.0)),
        _ => (niveau(valeur, SEUIL_ATTENTION, SEUIL_CRITIQUE), valeur.clamp(0.0, 100.0)),
    };
    let mut m = Map::new();
    m.insert("cle".into(), json!(cle));
    m.insert("nom".into(), json!(nom));
    m.insert("icone".into(), json!(icone));
    m.insert("valeur".into(), json!(round1(valeur)));
    m.insert("remplissage".into(), json!(round1(remp)));
    m.insert("texte".into(), json!(texte));
    m.insert("niveau".into(), json!(niv));
    m.insert("alerte".into(), json!(niv != "ok"));
    m
}

fn filtrer(mut donnees: Map<String, Value>, options: &Map<String, Value>) -> Value {
    let voulues: Vec<&str> = match options.get("mesures").and_then(|v| v.as_array()) {
        None => MESURES_DEFAUT.to_vec(),
        Some(arr) => {
            let set: HashSet<&str> = arr.iter().filter_map(|v| v.as_str()).collect();
            MESURES.iter().copied().filter(|m| set.contains(m)).collect()
        }
    };
    let barres: Vec<Value> = donnees
        .get("compact")
        .and_then(|c| c.get("barres"))
        .and_then(|b| b.as_array())
        .map(|arr| {
            arr.iter()
                .filter(|b| b.get("cle").and_then(|v| v.as_str()).map(|c| voulues.contains(&c)).unwrap_or(false))
                .cloned()
                .collect()
        })
        .unwrap_or_default();

    let first_txt = barres
        .first()
        .and_then(|b| b.get("texte"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let alerts = donnees.get("detail").and_then(|d| d.get("alerts"));
    let has_zombies = alerts.and_then(|a| a.get("zombies")).and_then(|v| v.as_u64()).unwrap_or(0) > 0;
    let has_failed = alerts
        .and_then(|a| a.get("systemd_failed"))
        .and_then(|v| v.as_array())
        .map(|a| !a.is_empty())
        .unwrap_or(false);
    let alerte = barres.iter().any(|b| b.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false))
        || has_zombies
        || has_failed;
    let cles: Vec<Value> = barres
        .iter()
        .filter_map(|b| b.get("cle").cloned())
        .collect();

    donnees.insert("compact".into(), compact(&first_txt, "système", alerte, 0, Some(barres)));
    donnees.insert("mesures".into(), Value::Array(cles));
    Value::Object(donnees)
}

pub fn analyser(options: &Map<String, Value>, force: bool, persister: bool) -> Value {
    let cache_path = quickshell_cache_dir().join("systeme_applet_cache.json");
    if !force && persister {
        if let Some(lu) = read_json::<Map<String, Value>>(&cache_path) {
            let ts = lu.get("ts").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let age = unix_secs() - ts;
            if (0.0..CACHE_TTL).contains(&age) {
                return filtrer(lu, options);
            }
        }
    }

    let mut barres: Vec<Map<String, Value>> = Vec::new();
    let mut detail = Map::new();
    let mem = memoire_mesures();

    for &cle in MESURES {
        match cle {
            "cpu" => {
                let (v_opt, coeurs, freq) = cpu_mesures(persister);
                if let Some(v) = v_opt {
                    barres.push(mk_barre("cpu", v, &format!("{v:.0}%")));
                    detail.insert("cpu".into(), json!({
                        "nom": cpu_nom(),
                        "pct": round1(v),
                        "coeurs": coeurs,
                        "freq_ghz": freq,
                    }));
                }
            }
            "ram" => {
                if let Some(ref m) = mem {
                    barres.push(mk_barre("ram", m.ram_pct, &format!("{:.0}%", m.ram_pct)));
                    detail.insert("ram".into(), json!({
                        "utilisee_go": m.utilisee_go,
                        "totale_go": m.totale_go,
                        "cache_go": m.cache_go,
                    }));
                }
            }
            "gpu" => {
                if let Some(g) = gpu_nvidia().or_else(gpu_amd) {
                    barres.push(mk_barre("gpu", g.utilisation, &format!("{:.0}%", g.utilisation)));
                    detail.insert("gpu".into(), json!({
                        "pct": round1(g.utilisation),
                        "temperature": g.temperature,
                        "vram_go": round1(g.vram_mb / 1024.0),
                        "vram_totale_go": round1(g.vram_total_mb / 1024.0),
                        "power_w": g.power_w,
                    }));
                }
            }
            "temp" => {
                if let Some(t) = temp_cpu() {
                    barres.push(mk_barre("temp", t, &format!("{t:.0}°")));
                    detail.insert("temp".into(), json!({ "cpu": round1(t) }));
                }
            }
            "load" => {
                if let Some(ld) = load_mesures() {
                    let pct = ld.get("pct").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    let l1 = ld.get("l1").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    barres.push(mk_barre("load", pct, &format!("{l1:.2}")));
                    detail.insert("load".into(), ld);
                }
            }
            "swap" => {
                if let Some(ref m) = mem {
                    if m.swap_totale_go > 0.0 {
                        barres.push(mk_barre("swap", m.swap_pct, &format!("{:.0}%", m.swap_pct)));
                        detail.insert("swap".into(), json!({
                            "utilisee_go": m.swap_utilisee_go,
                            "totale_go": m.swap_totale_go,
                            "pct": round1(m.swap_pct),
                        }));
                    }
                }
            }
            "disk" => {
                if let Some((u, t, pct)) = statvfs_usage("/") {
                    barres.push(mk_barre("disk", pct, &format!("{pct:.0}%")));
                    detail.insert("disk".into(), json!({
                        "utilise_go": u,
                        "total_go": t,
                        "pct": pct,
                    }));
                }
            }
            "net" => {
                if let Some(nt) = reseau_debits(persister) {
                    let pct = nt.get("pct").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    let rx_t = nt.get("rx_texte").and_then(|v| v.as_str()).unwrap_or("0 o/s");
                    barres.push(mk_barre("net", pct, &format!("↓{rx_t}")));
                    detail.insert("net".into(), nt);
                }
            }
            _ => {}
        }
    }

    if let Some(up) = uptime_info() {
        detail.insert("uptime".into(), up);
    }

    let zombies = zombies_proc();
    let mut failed_sys = systemd_failed(false);
    for u in systemd_failed(true) {
        failed_sys.push(format!("user:{u}"));
    }
    let seuils: Vec<Value> = barres
        .iter()
        .filter(|b| b.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false))
        .map(|b| json!({
            "cle": b.get("cle"),
            "nom": b.get("nom"),
            "texte": b.get("texte"),
            "niveau": b.get("niveau"),
        }))
        .collect();
    let total_alerts = (if zombies > 0 { 1 } else { 0 }) + failed_sys.len() + seuils.len();
    detail.insert("alerts".into(), json!({
        "total": total_alerts,
        "zombies": zombies,
        "systemd_failed": failed_sys,
        "seuils": seuils,
    }));

    let (capteurs_t, ventilos_t) = tous_capteurs_et_ventilateurs();
    if let Some(max_rpm) = ventilos_t.iter().map(|(r, _)| *r).max() {
        detail.insert("fan_rpm".into(), json!(max_rpm));
    }
    let fs_locaux = systemes_fichiers_locaux();

    for b in &mut barres {
        let cle = b.get("cle").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let texte = b.get("texte").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let al = b.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
        let mut sv: Vec<Value> = Vec::new();
        let add_sv = |list: &mut Vec<Value>, nom: &str, val: String, al: bool| {
            list.push(json!({ "nom": nom, "valeur": val, "alerte": al }));
        };
        match cle.as_str() {
            "cpu" => {
                if let Some(d_cpu) = detail.get("cpu") {
                    let freq = d_cpu.get("freq_ghz").and_then(|v| v.as_f64()).map(|f| format!(" · {f} GHz")).unwrap_or_default();
                    add_sv(&mut sv, "CPU", format!("{texte}{freq}"), al);
                    let psi_c = psi("cpu");
                    if !psi_c.is_empty() { add_sv(&mut sv, "PSI CPU", psi_c, false); }
                }
            }
            "ram" => {
                if let Some(ref m) = mem {
                    add_sv(&mut sv, "Utilisée", format!("{} / {} Go ({texte})", m.utilisee_go, m.totale_go), al);
                    add_sv(&mut sv, "Disponible", format!("{} Go", m.dispo_go), false);
                    add_sv(&mut sv, "Tampon / Cache", format!("{} / {} Go", m.buffers_go, m.cache_go), false);
                    add_sv(&mut sv, "htop", format!("{} Go", m.htop_go), false);
                    let psi_m = psi("memory");
                    if !psi_m.is_empty() { add_sv(&mut sv, "PSI RAM", psi_m, false); }
                }
            }
            "gpu" => {
                if let Some(dg) = detail.get("gpu") {
                    let t = dg.get("temperature").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    let vg = dg.get("vram_go").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    let vt = dg.get("vram_totale_go").and_then(|v| v.as_f64()).unwrap_or(0.0);
                    add_sv(&mut sv, "GPU", format!("{texte} · {t:.0}°C"), al);
                    add_sv(&mut sv, "VRAM", format!("{vg} / {vt} Go"), false);
                    if let Some(pw) = dg.get("power_w").and_then(|v| v.as_f64()) {
                        add_sv(&mut sv, "Puissance", format!("{pw} W"), false);
                    }
                }
            }
            "temp" => {
                for (val_t, lbl_t) in &capteurs_t {
                    add_sv(&mut sv, &lbl_t.chars().take(18).collect::<String>(), format!("{val_t:.1}°C"), *val_t >= TEMP_ATTENTION);
                }
                for (rpm, nom_v) in &ventilos_t {
                    add_sv(&mut sv, &format!("Ventilo ({nom_v})"), format!("{rpm} RPM"), false);
                }
            }
            "disk" => {
                for (mp, u_d, t_d, pct_d) in &fs_locaux {
                    add_sv(&mut sv, mp, format!("{u_d} / {t_d} Go ({pct_d:.0}%)"), *pct_d >= 80.0);
                }
                let psi_io = psi("io");
                if !psi_io.is_empty() { add_sv(&mut sv, "PSI I/O", psi_io, false); }
            }
            _ => {}
        }
        b.insert("survol".into(), Value::Array(sv));
    }

    let first_txt = barres.first().and_then(|b| b.get("texte")).and_then(|v| v.as_str()).unwrap_or("").to_string();
    let any_bar_alert = barres.iter().any(|b| b.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false));
    let barres_vals: Vec<Value> = barres.into_iter().map(Value::Object).collect();
    let cles: Vec<Value> = barres_vals.iter().filter_map(|b| b.get("cle").cloned()).collect();

    let mut donnees = Map::new();
    donnees.insert("ok".into(), json!(true));
    donnees.insert("ts".into(), json!(unix_secs()));
    donnees.insert("compact".into(), compact(&first_txt, "système", any_bar_alert || total_alerts > 0, 0, Some(barres_vals)));
    donnees.insert("detail".into(), Value::Object(detail));
    donnees.insert("mesures".into(), Value::Array(cles));

    if persister {
        let _ = write_json_atomic(&cache_path, &donnees, 0o644);
    }
    filtrer(donnees, options)
}

fn jiffies_snapshot() -> HashMap<i32, (u64, String, u64)> {
    let mut map = HashMap::new();
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let s = ent.file_name().to_string_lossy().to_string();
            let Ok(pid) = s.parse::<i32>() else { continue };
            let Ok(st) = fs::read_to_string(ent.path().join("stat")) else { continue };
            let Some((left, right)) = st.rsplit_once(')') else { continue };
            let nom = left.split_once('(').map(|(_, n)| n.trim()).unwrap_or("");
            let rest: Vec<&str> = right.split_whitespace().collect();
            if rest.len() <= 21 { continue; }
            let cpu = rest[11].parse::<u64>().unwrap_or(0) + rest[12].parse::<u64>().unwrap_or(0);
            let rss = rest[21].parse::<u64>().unwrap_or(0);
            map.insert(pid, (cpu, nom.chars().take(24).collect(), rss));
        }
    }
    map
}

fn gpu_par_processus() -> HashMap<i32, i64> {
    let mut out = HashMap::new();
    if !Path::new("/dev/nvidia0").exists() {
        return out;
    }
    if let Some(txt) = run_cmd_stdout("nvidia-smi", &["--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits"]) {
        for line in txt.lines() {
            let cols: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
            if cols.len() >= 2 {
                if let (Ok(pid), Ok(mem)) = (cols[0].parse::<i32>(), cols[1].parse::<i64>()) {
                    out.insert(pid, mem);
                }
            }
        }
    }
    out
}

fn cmdline_of(pid: i32) -> String {
    let Ok(bytes) = fs::read(format!("/proc/{pid}/cmdline")) else {
        return String::new();
    };
    let binding: Vec<u8> = bytes.into_iter().map(|b| if b == 0 { b' ' } else { b }).collect();
    let s = String::from_utf8_lossy(&binding);
    s.trim().chars().take(160).collect()
}

fn processus_list(limite: usize) -> (Vec<Value>, bool) {
    let first = jiffies_snapshot();
    let start = Instant::now();
    thread::sleep(Duration::from_millis(250));
    let second = jiffies_snapshot();
    let elapsed = start.elapsed().as_secs_f64().max(0.05);
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as f64;
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(4096) as f64;
    let gpu = gpu_par_processus();
    let has_gpu = !gpu.is_empty();
    let my_uid = unsafe { libc::getuid() };

    let mut rows: Vec<(i32, String, f64, f64, i64)> = Vec::new();
    for (pid, (cpu2, nom, rss)) in second {
        let Some(&(cpu1, _, _)) = first.get(&pid) else { continue };
        let pct = ((cpu2.saturating_sub(cpu1)) as f64 / (elapsed * ticks)) * 100.0;
        let ram_mo = (rss as f64 * page_size) / 1048576.0;
        let gpu_mo = gpu.get(&pid).copied().unwrap_or(0);
        rows.push((pid, nom, round1(pct), round1(ram_mo), gpu_mo));
    }

    let mut by_pid: BTreeMap<i32, (i32, String, f64, f64, i64)> = BTreeMap::new();
    let mut par_cpu: Vec<_> = rows.iter().filter(|r| r.2 >= 0.5).cloned().collect();
    par_cpu.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));
    for r in par_cpu.into_iter().take(limite) { by_pid.insert(r.0, r); }

    let mut par_ram: Vec<_> = rows.iter().filter(|r| r.3 > 0.0).cloned().collect();
    par_ram.sort_by(|a, b| b.3.partial_cmp(&a.3).unwrap_or(std::cmp::Ordering::Equal));
    for r in par_ram.into_iter().take(limite) { by_pid.insert(r.0, r); }

    let mut par_gpu: Vec<_> = rows.iter().filter(|r| r.4 > 0).cloned().collect();
    par_gpu.sort_by(|a, b| b.4.cmp(&a.4));
    for r in par_gpu.into_iter().take(limite) { by_pid.insert(r.0, r); }

    let mut selected: Vec<_> = by_pid.into_values().collect();
    selected.sort_by(|a, b| {
        b.2.partial_cmp(&a.2)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.3.partial_cmp(&a.3).unwrap_or(std::cmp::Ordering::Equal))
    });

    let out = selected
        .into_iter()
        .map(|(pid, nom, cpu, ram_mo, gpu_mo)| {
            let uid = fs::metadata(format!("/proc/{pid}")).map(|m| m.uid()).unwrap_or(my_uid);
            json!({
                "pid": pid,
                "nom": nom,
                "cpu": cpu,
                "ram_mo": ram_mo,
                "gpu_mo": gpu_mo,
                "commande": cmdline_of(pid),
                "moi": uid == my_uid,
                "user": if uid == my_uid { String::new() } else { uid.to_string() },
            })
        })
        .collect();
    (out, has_gpu)
}

fn tuer(pid_str: &str, force: bool) -> (bool, String) {
    let Ok(pid) = pid_str.parse::<i32>() else {
        return (false, "pid invalide".into());
    };
    if pid <= 1 {
        return (false, "refusé : pid système".into());
    }
    let self_pid = std::process::id() as i32;
    let ppid = unsafe { libc::getppid() };
    if pid == self_pid || pid == ppid {
        return (false, "refusé : c'est le shell qui exécute la commande".into());
    }
    let my_uid = unsafe { libc::getuid() };
    let Ok(meta) = fs::metadata(format!("/proc/{pid}")) else {
        return (false, "processus disparu".into());
    };
    if meta.uid() != my_uid {
        return (false, "refusé : processus d'un autre utilisateur".into());
    }
    let sig = if force { libc::SIGKILL } else { libc::SIGTERM };
    let rc = unsafe { libc::kill(pid, sig) };
    if rc != 0 {
        return (false, std::io::Error::last_os_error().to_string());
    }
    (true, if force { "tué (SIGKILL)".into() } else { "arrêt demandé (SIGTERM)".into() })
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("");
    if action == "processus" {
        let (procs, gpu) = processus_list(14);
        return sortir(&json!({ "processus": procs, "gpu": gpu }));
    }
    if action == "tuer" {
        if let Some(pid_str) = args.get(1) {
            let force = args.iter().any(|a| a == "--force");
            let (ok, message) = tuer(pid_str, force);
            sortir(&json!({ "ok": ok, "message": message }));
            return if ok { 0 } else { 1 };
        }
    }
    let force = args.iter().any(|a| a == "--force");
    let options = parse_options_arg(args);
    let val = analyser(&options, force, true);
    if let Value::Object(m) = val {
        let comp = m.get("compact").cloned();
        let alerte = comp.as_ref().and_then(|c| c.get("alerte")).and_then(|v| v.as_bool());
        let presented = presenter(m, "systeme", "cpu", comp, None, None, alerte, None);
        return sortir(&presented);
    }
    0
}
