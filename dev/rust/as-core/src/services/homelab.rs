use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::read_json_value;
use crate::common::paths::core_dir;
use regex::Regex;
use serde_json::{json, Map, Value};
use std::process::Command;
use std::thread;

const IGNORE: &[&str] = &[
    "drkonqi-coredump-processor@",
    "systemd-coredump@",
    "drkonqi-coredump@",
];
const VERBES: &[&str] = &["start", "stop", "shutdown", "reboot"];

fn config_homelab() -> Value {
    let v = read_json_value(&core_dir().join("homelab.json"));
    if v.is_object() { v } else { json!({}) }
}

fn secrets_proxmox() -> Value {
    let v = read_json_value(&core_dir().join("secrets.json"));
    match v.get("proxmox") {
        Some(p) if p.is_object() => p.clone(),
        _ => json!({}),
    }
}

fn run_out(prog: &str, args: &[&str]) -> String {
    Command::new(prog)
        .args(args)
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default()
}

fn unites_en_echec() -> Value {
    let mut n = 0u64;
    let mut noms = Vec::new();
    let mut ignorees = 0u64;

    for portee in [&["--failed"][..], &["--user", "--failed"][..]] {
        let mut args = portee.to_vec();
        args.extend(["--no-legend", "--plain"]);
        let sortie = run_out("systemctl", &args);
        for ligne in sortie.lines() {
            let Some(unit) = ligne.split_whitespace().next() else {
                continue;
            };
            if IGNORE.iter().any(|p| unit.starts_with(p)) {
                ignorees += 1;
                continue;
            }
            n += 1;
            if noms.len() < 5 {
                noms.push(unit.to_string());
            }
        }
    }
    json!({ "nombre": n, "noms": noms, "ignorees": ignorees })
}

fn ping_host(cible: &str) -> Option<i64> {
    let res = run_out("ping", &["-c", "1", "-W", "1", cible]);
    let re1 = Regex::new(r"(?:time|temps)[=<]([\d.]+)\s*ms").unwrap();
    if let Some(cap) = re1.captures(&res) {
        if let Ok(v) = cap[1].parse::<f64>() {
            return Some(v.round() as i64);
        }
    }
    let re2 = Regex::new(r"rtt[^=]*=\s*[\d.]+/([\d.]+)/").unwrap();
    if let Some(cap) = re2.captures(&res) {
        if let Ok(v) = cap[1].parse::<f64>() {
            return Some(v.round() as i64);
        }
    }
    None
}

fn hotes() -> Vec<Value> {
    let conf = config_homelab();
    let Some(arr) = conf.get("hotes").and_then(|v| v.as_array()) else {
        return vec![];
    };
    let mut cibles: Vec<(String, String)> = Vec::new();
    for h in arr {
        if !h.is_object() {
            continue;
        }
        let nom_raw = h.get("nom").and_then(|v| v.as_str()).unwrap_or("");
        let url_raw = h.get("url").and_then(|v| v.as_str()).unwrap_or("");
        let nom = if !nom_raw.trim().is_empty() {
            nom_raw.trim().to_string()
        } else {
            url_raw.trim().to_string()
        };
        let cible = if !url_raw.trim().is_empty() {
            url_raw.trim().to_string()
        } else {
            nom_raw.trim().to_string()
        };
        if cible.is_empty() {
            continue;
        }
        cibles.push((nom, cible));
    }
    if cibles.is_empty() {
        return vec![];
    }

    let latences: Vec<Option<i64>> = thread::scope(|s| {
        let handles: Vec<_> = cibles
            .iter()
            .map(|(_, cible)| {
                let c = cible.as_str();
                s.spawn(move || ping_host(c))
            })
            .collect();
        handles
            .into_iter()
            .map(|h| h.join().unwrap_or(None))
            .collect()
    });

    cibles
        .into_iter()
        .zip(latences)
        .map(|((nom, cible), lat)| {
            json!({
                "nom": nom,
                "url": cible,
                "joignable": lat.is_some(),
                "latence_ms": lat,
            })
        })
        .collect()
}

fn api_proxmox(
    base: &str,
    chemin: &str,
    jeton: &str,
    verifier_tls: bool,
    methode: &str,
) -> (Option<Value>, Option<String>) {
    let url = format!("{}/api2/json{}", base.trim_end_matches('/'), chemin);
    let auth = format!("PVEAPIToken={}", jeton);

    if verifier_tls {
        let agent = ureq::AgentBuilder::new()
            .timeout(std::time::Duration::from_secs(5))
            .build();
        let req = agent
            .request(methode, &url)
            .set("Authorization", &auth)
            .set("Accept", "application/json");
        let resp = if methode == "POST" {
            req.send_bytes(&[])
        } else {
            req.call()
        };
        return match resp {
            Ok(r) => match r.into_json::<Value>() {
                Ok(v) => (v.get("data").cloned(), None),
                Err(_) => (None, Some("réponse illisible".to_string())),
            },
            Err(ureq::Error::Status(code, _)) => match code {
                401 => (None, Some("jeton refusé".to_string())),
                403 => (None, Some("droits insuffisants".to_string())),
                _ => (None, Some(format!("HTTP {}", code))),
            },
            Err(_) => (None, Some("injoignable".to_string())),
        };
    }

    // Proxmox sert un certificat auto-signé par défaut : curl -sk gère -k proprement.
    let auth_hdr = format!("Authorization: {}", auth);
    let mut args = vec![
        "-s",
        "-k",
        "-m",
        "5",
        "-X",
        methode,
        "-H",
        &auth_hdr,
        "-H",
        "Accept: application/json",
        "-w",
        "\n%{http_code}",
        &url,
    ];
    if methode == "POST" {
        args.extend(["-d", ""]);
    }
    let Ok(out) = Command::new("curl").args(&args).output() else {
        return (None, Some("injoignable".to_string()));
    };
    if !out.status.success() {
        return (None, Some("injoignable".to_string()));
    }
    let txt = String::from_utf8_lossy(&out.stdout);
    let (body, code_str) = match txt.rsplit_once('\n') {
        Some((b, c)) => (b, c.trim()),
        None => ("", txt.trim()),
    };
    let code: u16 = code_str.parse().unwrap_or(0);
    if code == 401 {
        return (None, Some("jeton refusé".to_string()));
    }
    if code == 403 {
        return (None, Some("droits insuffisants".to_string()));
    }
    if code >= 400 || code == 0 {
        return (
            None,
            Some(if code == 0 {
                "injoignable".to_string()
            } else {
                format!("HTTP {}", code)
            }),
        );
    }
    match serde_json::from_str::<Value>(body) {
        Ok(v) => (v.get("data").cloned(), None),
        Err(_) => (None, Some("réponse illisible".to_string())),
    }
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

fn proxmox() -> Value {
    let conf_root = config_homelab();
    let conf = conf_root.get("proxmox").cloned().unwrap_or_else(|| json!({}));
    let url = conf
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if url.is_empty() {
        return json!({});
    }
    let sec = secrets_proxmox();
    let ident = conf
        .get("token_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .or_else(|| sec.get("token_id").and_then(|v| v.as_str()))
        .unwrap_or("")
        .trim()
        .to_string();
    let secret = sec
        .get("token_secret")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if ident.is_empty() || secret.is_empty() {
        return json!({ "configure": true, "url": url, "erreur": "jeton absent" });
    }

    let jeton = format!("{}={}", ident, secret);
    let verifier = conf
        .get("verifier_tls")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    let (noeuds_opt, err) = api_proxmox(&url, "/nodes", &jeton, verifier, "GET");
    if let Some(e) = err {
        return json!({ "configure": true, "url": url, "erreur": e });
    }
    let (vms_opt, err_vm) = api_proxmox(&url, "/cluster/resources?type=vm", &jeton, verifier, "GET");
    let vms_raw = if err_vm.is_some() {
        vec![]
    } else {
        vms_opt
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default()
    };

    let mut noeuds = Vec::new();
    for n in noeuds_opt
        .and_then(|v| v.as_array().cloned())
        .unwrap_or_default()
    {
        if !n.is_object() {
            continue;
        }
        let maxmem = n.get("maxmem").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let mem = n.get("mem").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let cpu = n.get("cpu").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let uptime = n.get("uptime").and_then(|v| v.as_f64()).unwrap_or(0.0);
        noeuds.push(json!({
            "nom": n.get("node").and_then(|v| v.as_str()).unwrap_or(""),
            "en_ligne": n.get("status").and_then(|v| v.as_str()).unwrap_or("") == "online",
            "cpu": (100.0 * cpu).round() as i64,
            "ram": if maxmem > 0.0 { Some((100.0 * mem / maxmem).round() as i64) } else { None },
            "ram_go": if mem != 0.0 { Some(round1(mem / 1073741824.0)) } else { None },
            "ram_max_go": if maxmem > 0.0 { Some(round1(maxmem / 1073741824.0)) } else { None },
            "uptime_j": round1(uptime / 86400.0),
        }));
    }

    let mut vms = Vec::new();
    for v in vms_raw {
        if !v.is_object() {
            continue;
        }
        if v.get("template").and_then(|x| x.as_bool()).unwrap_or(false)
            || v.get("template").and_then(|x| x.as_i64()).unwrap_or(0) != 0
        {
            continue;
        }
        let etat = v.get("status").and_then(|x| x.as_str()).unwrap_or("");
        let maxmem = v.get("maxmem").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let mem = v.get("mem").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let maxdisk = v.get("maxdisk").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let disque = v.get("disk").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let cpu = v.get("cpu").and_then(|x| x.as_f64()).unwrap_or(0.0);
        let uptime = v.get("uptime").and_then(|x| x.as_f64()).unwrap_or(0.0);
        vms.push(json!({
            "id": v.get("vmid").cloned().unwrap_or(Value::Null),
            "nom": v.get("name").and_then(|x| x.as_str()).unwrap_or(""),
            "type": v.get("type").and_then(|x| x.as_str()).unwrap_or(""),
            "etat": etat,
            "noeud": v.get("node").and_then(|x| x.as_str()).unwrap_or(""),
            "cpu": (100.0 * cpu).round() as i64,
            "ram": if maxmem > 0.0 { Some((100.0 * mem / maxmem).round() as i64) } else { None },
            "ram_go": round1(mem / 1073741824.0),
            "ram_max_go": round1(maxmem / 1073741824.0),
            "disque_go": round1(disque / 1073741824.0),
            "disque_max_go": round1(maxdisk / 1073741824.0),
            "uptime_j": round1(uptime / 86400.0),
        }));
    }

    let en_cours = vms
        .iter()
        .filter(|v| v.get("etat").and_then(|x| x.as_str()) == Some("running"))
        .count();
    let total = vms.len();
    let ct = vms
        .iter()
        .filter(|v| v.get("type").and_then(|x| x.as_str()) == Some("lxc"))
        .count();
    let vm = vms
        .iter()
        .filter(|v| v.get("type").and_then(|x| x.as_str()) == Some("qemu"))
        .count();

    let mut out = json!({
        "configure": true,
        "url": url,
        "erreur": Value::Null,
        "noeuds": noeuds,
        "vms": vms,
        "en_cours": en_cours,
        "total": total,
        "ct": ct,
        "vm": vm,
    });
    if total == 0 {
        let (droits, _) = api_proxmox(&url, "/access/permissions", &jeton, verifier, "GET");
        let aucuns = matches!(&droits, Some(Value::Object(m)) if m.is_empty());
        let statut_droits = if aucuns { "aucun" } else { "limites" };
        out.as_object_mut()
            .unwrap()
            .insert("droits".into(), json!(statut_droits));
        if aucuns {
            out.as_object_mut().unwrap().insert(
                "aide".into(),
                json!(format!(
                    "pveum acl modify / --tokens '{}' --roles PVEAuditor",
                    ident
                )),
            );
        }
    }
    out
}

fn agir(verbe: &str, genre: &str, noeud: &str, vmid: &str) -> Value {
    let conf_root = config_homelab();
    let conf = conf_root.get("proxmox").cloned().unwrap_or_else(|| json!({}));
    let url = conf
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    let sec = secrets_proxmox();
    let ident = conf
        .get("token_id")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .or_else(|| sec.get("token_id").and_then(|v| v.as_str()))
        .unwrap_or("")
        .trim()
        .to_string();
    let secret = sec
        .get("token_secret")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    if url.is_empty() || ident.is_empty() || secret.is_empty() {
        return json!({ "ok": false, "message": "Proxmox non configuré" });
    }
    let Ok(vmid_num) = vmid.parse::<i64>() else {
        return json!({ "ok": false, "message": "cible invalide" });
    };
    if !matches!(genre, "lxc" | "qemu") || !VERBES.contains(&verbe) || noeud.is_empty() {
        return json!({ "ok": false, "message": "cible invalide" });
    }
    let chemin = format!("/nodes/{}/{}/{}/status/{}", noeud, genre, vmid_num, verbe);
    let verifier = conf
        .get("verifier_tls")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let jeton = format!("{}={}", ident, secret);
    let (_, err) = api_proxmox(&url, &chemin, &jeton, verifier, "POST");
    if let Some(e) = err {
        return json!({ "ok": false, "message": e, "chemin": chemin });
    }
    json!({ "ok": true, "message": format!("{} demandé", verbe), "chemin": chemin })
}

fn analyser() -> Map<String, Value> {
    let unites = unites_en_echec();
    let h = hotes();
    let pve = proxmox();

    let injoignables_cnt = h
        .iter()
        .filter(|x| !x.get("joignable").and_then(|v| v.as_bool()).unwrap_or(false))
        .count();
    let unites_n = unites.get("nombre").and_then(|v| v.as_u64()).unwrap_or(0);
    let pve_err = pve
        .get("erreur")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty());
    let pve_cfg = pve
        .get("configure")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let pve_droits = pve.get("droits").and_then(|v| v.as_str()).unwrap_or("");
    let pve_total = pve.get("total").and_then(|v| v.as_u64()).unwrap_or(0);
    let pve_en_cours = pve.get("en_cours").and_then(|v| v.as_u64()).unwrap_or(0);

    let alerte = injoignables_cnt > 0 || unites_n > 0 || pve_err.is_some();

    let (valeur, libelle) = if injoignables_cnt > 0 {
        (
            injoignables_cnt.to_string(),
            "hôte(s) injoignable(s)".to_string(),
        )
    } else if unites_n > 0 {
        (unites_n.to_string(), "service(s) en échec".to_string())
    } else if let Some(e) = pve_err {
        ("!".to_string(), format!("Proxmox {}", e))
    } else if pve_cfg && pve_droits == "aucun" {
        ("!".to_string(), "Proxmox sans droits".to_string())
    } else if pve_cfg && pve_total > 0 {
        (
            format!("{}/{}", pve_en_cours, pve_total),
            "invités".to_string(),
        )
    } else {
        (String::new(), String::new())
    };

    let mut barres = Vec::new();
    if pve_cfg {
        if let Some(e) = pve_err {
            barres.push(json!({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": 0, "remplissage": 0, "texte": e,
                "niveau": "critique", "alerte": true,
            }));
        } else if pve_droits == "aucun" {
            barres.push(json!({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": 0, "remplissage": 0, "texte": "sans droits",
                "niveau": "attention", "alerte": true,
            }));
        } else if pve_total > 0 {
            let pct = ((100.0 * pve_en_cours as f64) / (pve_total.max(1) as f64)).round() as i64;
            barres.push(json!({
                "cle": "proxmox", "nom": "Proxmox", "icone": "cloud-check",
                "valeur": pct, "remplissage": pct,
                "texte": format!("{}/{}", pve_en_cours, pve_total),
                "niveau": if pct < 100 { "attention" } else { "ok" },
                "alerte": false,
            }));
        }
    }
    if !h.is_empty() {
        let joignables = h.len() - injoignables_cnt;
        let pct = ((100.0 * joignables as f64) / (h.len() as f64)).round() as i64;
        barres.push(json!({
            "cle": "hotes", "nom": "Hôtes", "icone": "cloud-check",
            "valeur": pct, "remplissage": pct,
            "texte": format!("{}/{}", joignables, h.len()),
            "niveau": if pct < 100 { "critique" } else { "ok" },
            "alerte": pct < 100,
        }));
    }

    let cmp = compact(
        &valeur,
        &libelle,
        alerte,
        0,
        if barres.is_empty() { None } else { Some(barres) },
    );
    let mut map = Map::new();
    map.insert("ok".into(), Value::Bool(true));
    map.insert("compact".into(), cmp);
    map.insert(
        "detail".into(),
        json!({ "unites": unites, "hotes": h, "proxmox": pve }),
    );
    map.insert("applet".into(), json!("homelab"));
    map.insert("icone".into(), json!("cloud-check"));
    map.insert("alerte".into(), json!(alerte));
    map
}

pub fn run(args: &[String]) -> i32 {
    if args.iter().any(|a| a == "--action") {
        let val = |nom: &str, defaut: &str| -> String {
            for i in 0..args.len() {
                if args[i] == nom && i + 1 < args.len() {
                    return args[i + 1].clone();
                }
            }
            defaut.to_string()
        };
        let verdict = agir(
            &val("--action", ""),
            &val("--type", "lxc"),
            &val("--node", ""),
            &val("--vmid", ""),
        );
        println!("{}", verdict);
        return if verdict.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            0
        } else {
            1
        };
    }

    let donnees = analyser();
    let cmp = donnees.get("compact").cloned().unwrap_or(Value::Null);
    let out = presenter(donnees, "homelab", "cloud-check", Some(cmp), None, None, None, None);
    sortir(&out)
}
