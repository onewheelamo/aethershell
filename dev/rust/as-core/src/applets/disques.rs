use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{parse_options_arg, read_json_value, run_cmd_stdout};
use crate::common::paths::core_dir;
use serde_json::{json, Map, Value};
use std::collections::HashSet;
use std::ffi::CString;
use std::fs;
use std::path::Path;

const PSEUDO: &[&str] = &[
    "tmpfs", "devtmpfs", "efivarfs", "squashfs", "overlay", "proc", "sysfs",
    "cgroup", "cgroup2", "ramfs", "autofs", "fuse.portal", "devpts",
    "binfmt_misc", "securityfs", "pstore", "debugfs", "tracefs",
    "configfs", "fusectl", "hugetlbfs", "mqueue", "nsfs", "bpf",
];

fn round1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

fn niveau(pct: i64) -> &'static str {
    if pct >= 92 { "critique" } else if pct >= 80 { "attention" } else { "ok" }
}

fn montages() -> Vec<Value> {
    let Ok(txt) = fs::read_to_string("/proc/mounts") else { return vec![]; };
    let mut seen_src = HashSet::new();
    let mut out: Vec<(String, Value)> = Vec::new();
    for line in txt.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.len() < 3 { continue; }
        let (src, mp, fstype) = (cols[0], cols[1], cols[2]);
        if PSEUDO.contains(&fstype) || fstype.starts_with("fuse.") || !seen_src.insert(src.to_string()) {
            continue;
        }
        let Ok(c_mp) = CString::new(mp) else { continue };
        let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
        if unsafe { libc::statvfs(c_mp.as_ptr(), &mut st) } != 0 || st.f_blocks == 0 {
            continue;
        }
        let total = (st.f_blocks as u128) * (st.f_frsize as u128);
        let avail = (st.f_bavail as u128) * (st.f_frsize as u128);
        if total == 0 { continue; }
        let used = total.saturating_sub(avail);
        let pct = ((100.0 * used as f64 / total as f64).round() as i64).clamp(0, 100);
        out.push((
            mp.to_string(),
            json!({
                "source": src,
                "montage": mp,
                "fstype": fstype,
                "taille_go": round1(total as f64 / 1e9),
                "utilise_go": round1(used as f64 / 1e9),
                "libre_go": round1(avail as f64 / 1e9),
                "pourcent": pct,
                "niveau": niveau(pct),
            }),
        ));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out.into_iter().map(|(_, v)| v).collect()
}

fn temp_nvme() -> Option<i64> {
    let entries = fs::read_dir("/sys/class/hwmon").ok()?;
    for ent in entries.flatten() {
        let base = ent.path();
        let nom = fs::read_to_string(base.join("name")).unwrap_or_default();
        if matches!(nom.trim(), "nvme" | "drivetemp") {
            if let Ok(mc) = fs::read_to_string(base.join("temp1_input")).and_then(|s| s.trim().parse::<f64>().map_err(|_| std::io::ErrorKind::InvalidData.into())) {
                return Some((mc / 1000.0).round() as i64);
            }
        }
    }
    None
}

fn smart_info(dev: &str) -> Map<String, Value> {
    let mut infos = Map::new();
    let Some(raw) = run_cmd_stdout("smartctl", &["-a", "--json", dev]) else {
        return infos;
    };
    let Ok(d) = serde_json::from_str::<Value>(&raw) else { return infos; };
    if let Some(code) = d.get("smartctl").and_then(|s| s.get("exit_status")).and_then(|v| v.as_i64()) {
        if matches!(code, 1 | 2 | 3) {
            return infos;
        }
    }
    if let Some(p) = d.get("smart_status").and_then(|s| s.get("passed")).and_then(|v| v.as_bool()) {
        infos.insert("sante".into(), json!(p));
    }
    if let Some(h) = d.get("power_on_time").and_then(|s| s.get("hours")).and_then(|v| v.as_i64()) {
        infos.insert("heures".into(), json!(h));
    }
    if let Some(u) = d.get("nvme_smart_health_information_log").and_then(|s| s.get("percentage_used")).and_then(|v| v.as_i64()) {
        infos.insert("usure".into(), json!(u));
    }
    if let Some(t) = d.get("temperature").and_then(|s| s.get("current")).and_then(|v| v.as_i64()) {
        infos.insert("temperature".into(), json!(t));
    }
    infos
}

fn disques_physiques() -> Vec<Value> {
    let Some(raw) = run_cmd_stdout("lsblk", &["-J", "-b", "-d", "-o", "NAME,MODEL,SIZE,TYPE,ROTA,TRAN"]) else {
        return vec![];
    };
    let Ok(v) = serde_json::from_str::<Value>(&raw) else { return vec![]; };
    let Some(devs) = v.get("blockdevices").and_then(|b| b.as_array()) else { return vec![]; };
    let t_nvme = temp_nvme();
    let mut out: Vec<(String, Value)> = Vec::new();
    for dev in devs {
        let nom = dev.get("name").and_then(|s| s.as_str()).unwrap_or("");
        let taille = dev.get("size").and_then(|s| s.as_u64()).unwrap_or(0);
        if nom.is_empty() || taille == 0 { continue; }
        let tran = dev.get("tran").and_then(|s| s.as_str()).unwrap_or("");
        let rota = dev.get("rota").and_then(|s| s.as_bool()).unwrap_or(false);
        let nature = if tran == "nvme" { "nvme" } else if rota { "disque" } else { "ssd" };
        let mut m = Map::new();
        m.insert("nom".into(), json!(nom));
        m.insert("modele".into(), json!(dev.get("model").and_then(|s| s.as_str()).unwrap_or("").trim()));
        m.insert("taille_go".into(), json!(round1(taille as f64 / 1e9)));
        m.insert("type".into(), json!(nature));
        if nature == "nvme" {
            if let Some(t) = t_nvme {
                m.insert("temperature".into(), json!(t));
            }
        }
        for (k, val) in smart_info(&format!("/dev/{nom}")) {
            m.insert(k, val);
        }
        out.push((nom.to_string(), Value::Object(m)));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    out.into_iter().map(|(_, v)| v).collect()
}

pub fn run(args: &[String]) -> i32 {
    let mut opts = parse_options_arg(args);
    if opts.is_empty() {
        let reg = read_json_value(&core_dir().join("bar_applets.json"));
        if let Some(o) = reg
            .get("actifs")
            .and_then(|a| a.get("disques"))
            .and_then(|d| d.get("options"))
            .and_then(|o| o.as_object())
        {
            opts = o.clone();
        }
    }

    let all_mounts = montages();
    let choisis: Option<HashSet<String>> = opts
        .get("montages")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|x| x.as_str().map(|s| s.to_string())).collect());

    let filtered: Vec<&Value> = all_mounts
        .iter()
        .filter(|m| {
            let mp = m.get("montage").and_then(|v| v.as_str()).unwrap_or("");
            match &choisis {
                Some(set) => set.contains(mp),
                None => mp != "/",
            }
        })
        .collect();

    let (tot_u, tot_t) = filtered.iter().fold((0.0, 0.0), |(u, t), m| {
        (
            u + m.get("utilise_go").and_then(|v| v.as_f64()).unwrap_or(0.0),
            t + m.get("taille_go").and_then(|v| v.as_f64()).unwrap_or(0.0),
        )
    });
    let pct = if tot_t > 0.0 {
        ((100.0 * tot_u / tot_t).round() as i64).clamp(0, 100)
    } else {
        0
    };
    let alerte = filtered
        .iter()
        .any(|m| m.get("niveau").and_then(|v| v.as_str()) != Some("ok"));
    let val_str = if tot_t > 0.0 { format!("{pct}%") } else { "—".to_string() };

    let phys = disques_physiques();
    let mut detail = Map::new();
    detail.insert("ok".into(), json!(true));
    detail.insert(
        "detail".into(),
        json!({
            "montages": all_mounts,
            "disques": phys,
        }),
    );

    let comp = compact(&val_str, "disques", alerte, 0, None);
    let out = presenter(detail, "disques", "disque", Some(comp), None, None, Some(alerte), None);
    sortir(&out)
}
