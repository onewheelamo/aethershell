use crate::common::io::{read_json_value, run_cmd_stdout};
use crate::common::paths::{core_dir, home_dir};
use crate::services::llm::mesure;
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::{BTreeSet, HashMap};
use std::env;
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const API_MODELES: &str = "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels";
const API_QUOTA: &str = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota";
const API_ASSIST: &str = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist";
const AGENT: &str = "antigravity/1.10.0";
const TTL: i64 = 120;
const RENEW_DELAI: i64 = 900;
const PLEIN_TTL: i64 = 6 * 3600;
const AGY_FAIL_TTL: i64 = 600;
const SEUIL_ALERTE: f64 = 0.05;

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn cache_file() -> PathBuf {
    core_dir().join("antigravity_cache.json")
}
fn plein_file() -> PathBuf {
    core_dir().join("antigravity_full_cache.json")
}
fn renew_file() -> PathBuf {
    core_dir().join("antigravity_renew_cache.json")
}
fn agy_fail_file() -> PathBuf {
    core_dir().join("antigravity_agy_fail.json")
}

fn ecrire_json(chemin: &Path, val: &Value) {
    if let Ok(s) = serde_json::to_string(val) {
        let _ = fs::write(chemin, format!("{}\n", s));
    }
}

fn parse_utc_iso_secs(s: &str) -> Option<i64> {
    let clean = s.trim().trim_end_matches('Z');
    let no_tz = clean.split('+').next().unwrap_or(clean);
    let no_ms = no_tz.split('.').next().unwrap_or(no_tz);
    let (d_p, t_p) = no_ms.split_once('T')?;
    let d: Vec<i32> = d_p.split('-').filter_map(|x| x.parse().ok()).collect();
    let t: Vec<i32> = t_p.split(':').filter_map(|x| x.parse().ok()).collect();
    if d.len() != 3 || t.len() < 3 {
        return None;
    }
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        tm.tm_year = d[0] - 1900;
        tm.tm_mon = d[1] - 1;
        tm.tm_mday = d[2];
        tm.tm_hour = t[0];
        tm.tm_min = t[1];
        tm.tm_sec = t[2];
        let epoch = libc::timegm(&mut tm);
        if epoch < 0 {
            None
        } else {
            Some(epoch as i64)
        }
    }
}

fn duree_fmt(secondes: i64) -> String {
    let s = secondes.max(0);
    let jours = s / 86400;
    let heures = (s % 86400) / 3600;
    let minutes = (s % 3600) / 60;
    if jours > 0 {
        format!("{} j {:02}", jours, heures)
    } else if heures > 0 {
        format!("{}h{:02}", heures, minutes)
    } else {
        format!("{} min", minutes)
    }
}

fn mesure_ext(valeur: &str, libelle: &str, fin: i64, depuis: i64, texte: &str, releve: i64) -> Value {
    json!({
        "valeur": valeur,
        "libelle": libelle,
        "texte": texte,
        "fin": fin,
        "depuis": depuis,
        "releve": releve,
    })
}

fn trouver_agy() -> String {
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            let p = dir.join("agy");
            if p.is_file() {
                return p.to_string_lossy().to_string();
            }
        }
    }
    let h = home_dir();
    for cand in [h.join(".local/bin/agy"), h.join(".gemini/bin/agy")] {
        if cand.is_file() {
            return cand.to_string_lossy().to_string();
        }
    }
    "agy".to_string()
}

fn groupe_court(nom: &str) -> String {
    let bas = nom.trim().to_ascii_lowercase();
    if bas == "gemini models" {
        return "Gemini Flash".to_string();
    }
    let mut mots: Vec<&str> = nom.split_whitespace().collect();
    if mots.last().map(|w| w.eq_ignore_ascii_case("models")).unwrap_or(false) {
        mots.pop();
    }
    let joined = mots.join(" ").replace(" and ", "/");
    if joined.is_empty() {
        "quota".to_string()
    } else {
        joined
    }
}

fn agy_echec(raison: &str) -> String {
    ecrire_json(&agy_fail_file(), &json!({ "ts": now_secs(), "raison": raison }));
    raison.to_string()
}

fn echeance_fmt(instant: i64) -> String {
    unsafe {
        let t_inst = instant as libc::time_t;
        let t_now = libc::time(std::ptr::null_mut());
        let mut q: libc::tm = std::mem::zeroed();
        let mut m: libc::tm = std::mem::zeroed();
        libc::localtime_r(&t_inst, &mut q);
        libc::localtime_r(&t_now, &mut m);
        if q.tm_year == m.tm_year && q.tm_yday == m.tm_yday {
            format!("{:02}:{:02}", q.tm_hour, q.tm_min)
        } else {
            format!("{:02}/{:02} {:02}:{:02}", q.tm_mday, q.tm_mon + 1, q.tm_hour, q.tm_min)
        }
    }
}

#[derive(Clone)]
struct AgyFenetre {
    groupe: String,
    tranche: String,
    reste: f64,
    reset_at: i64,
}

fn depuis_agy(force: bool) -> (Vec<AgyFenetre>, String) {
    if !force {
        let echec = read_json_value(&agy_fail_file());
        let age = now_secs() - echec.get("ts").and_then(|v| v.as_i64()).unwrap_or(0);
        if let Some(raison) = echec.get("raison").and_then(|v| v.as_str()) {
            if !raison.is_empty() && (0..AGY_FAIL_TTL).contains(&age) {
                let mins = ((AGY_FAIL_TTL - age) / 60).max(1);
                return (vec![], format!("{} (retenté dans {} min)", raison, mins));
            }
        }
    }

    let agy = trouver_agy();
    let tmp_dir = env::temp_dir().join(format!("aether-agy-usage-{}", std::process::id()));
    let _ = fs::create_dir_all(&tmp_dir);

    let spawn_res = unsafe {
        Command::new(&agy)
            .args(["-p", "/usage", "--output-format", "json", "--print-timeout", "6s"])
            .current_dir(&tmp_dir)
            .env("AGY_CLI_DISABLE_AUTO_UPDATE", "true")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .pre_exec(|| {
                libc::setsid();
                Ok(())
            })
            .spawn()
    };

    let (code, sortie) = match spawn_res {
        Ok(mut child) => {
            let pid = child.id() as libc::pid_t;
            let start = Instant::now();
            let timeout = Duration::from_secs(6);
            loop {
                match child.try_wait() {
                    Ok(Some(_)) => match child.wait_with_output() {
                        Ok(o) => {
                            break (
                                o.status.code().unwrap_or(1),
                                String::from_utf8_lossy(&o.stdout).to_string(),
                            );
                        }
                        Err(_) => break (1, String::new()),
                    },
                    Ok(None) => {
                        if start.elapsed() >= timeout {
                            unsafe {
                                libc::killpg(pid, libc::SIGKILL);
                            }
                            let _ = child.wait();
                            let _ = fs::remove_dir_all(&tmp_dir);
                            return (vec![], agy_echec("agy n'a pas répondu à temps"));
                        }
                        thread::sleep(Duration::from_millis(100));
                    }
                    Err(e) => {
                        let _ = fs::remove_dir_all(&tmp_dir);
                        return (vec![], agy_echec(&format!("agy injoignable : {}", e)));
                    }
                }
            }
        }
        Err(e) => {
            let _ = fs::remove_dir_all(&tmp_dir);
            return (vec![], agy_echec(&format!("agy injoignable : {}", e)));
        }
    };
    let _ = fs::remove_dir_all(&tmp_dir);

    if code != 0 {
        let motif = serde_json::from_str::<Value>(&sortie)
            .ok()
            .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(|s| s.trim().to_string()))
            .unwrap_or_default();
        let msg = if !motif.is_empty() {
            format!("agy : {}", motif.chars().take(80).collect::<String>())
        } else {
            format!("agy a échoué (code {})", code)
        };
        return (vec![], agy_echec(&msg));
    }

    let Ok(corps) = serde_json::from_str::<Value>(&sortie) else {
        return (vec![], agy_echec("réponse agy illisible"));
    };
    if corps.get("status").and_then(|v| v.as_str()) != Some("SUCCESS")
        || corps.get("num_turns").and_then(|v| v.as_i64()) != Some(0)
    {
        return (vec![], agy_echec("réponse agy inattendue"));
    }
    let commande = corps.get("command").cloned().unwrap_or(Value::Null);
    if commande.get("name").and_then(|v| v.as_str()) != Some("usage") {
        return (vec![], agy_echec("commande /usage non reconnue"));
    }

    let mut fenetres = Vec::new();
    if let Some(groups) = commande
        .get("data")
        .and_then(|d| d.get("groups"))
        .and_then(|g| g.as_array())
    {
        for groupe in groups {
            let nom = groupe_court(groupe.get("name").and_then(|v| v.as_str()).unwrap_or(""));
            if let Some(buckets) = groupe.get("buckets").and_then(|b| b.as_array()) {
                for bucket in buckets {
                    let Some(raw_reste) = bucket.get("remaining_fraction").and_then(|v| v.as_f64())
                    else {
                        continue;
                    };
                    let reste = raw_reste.clamp(0.0, 1.0);
                    let fen = bucket.get("window").and_then(|v| v.as_str()).unwrap_or("");
                    let tranche = match fen {
                        "weekly" => "7 j",
                        "5h" => "5 h",
                        other => other,
                    };
                    let reset_at = bucket
                        .get("reset_time")
                        .and_then(|v| v.as_str())
                        .and_then(parse_utc_iso_secs)
                        .unwrap_or(0);
                    fenetres.push(AgyFenetre {
                        groupe: nom.clone(),
                        tranche: tranche.to_string(),
                        reste,
                        reset_at,
                    });
                }
            }
        }
    }
    if fenetres.is_empty() {
        return (vec![], agy_echec("aucune fenêtre dans la réponse"));
    }
    fenetres.sort_by(|a, b| {
        a.reste
            .partial_cmp(&b.reste)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.reset_at.cmp(&a.reset_at))
    });
    let _ = fs::remove_file(agy_fail_file());
    (fenetres, String::new())
}

fn lignes_de_agy(fenetres: &[AgyFenetre]) -> Vec<Value> {
    let mut lignes: Vec<(bool, f64, Value)> = fenetres
        .iter()
        .map(|f| {
            let alerte = f.reste <= SEUIL_ALERTE;
            let pct = (f.reste * 100.0).round() as i64;
            let ech = if f.reset_at != 0 {
                echeance_fmt(f.reset_at)
            } else {
                String::new()
            };
            let v = json!({
                "nom": f.groupe,
                "tranche": f.tranche,
                "valeur": format!("{:>3} %", pct),
                "echeance": ech,
                "reste": f.reste,
                "alerte": alerte,
            });
            (alerte, f.reste, v)
        })
        .collect();
    lignes.sort_by(|a, b| {
        let ka = if a.0 { 0 } else { 1 };
        let kb = if b.0 { 0 } else { 1 };
        ka.cmp(&kb)
            .then_with(|| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
    });
    lignes.into_iter().map(|t| t.2).collect()
}

// ── source 1 : API ────────────────────────────────────────────────────────────

fn renouveler() -> bool {
    let maintenant = now_secs();
    let last = read_json_value(&renew_file())
        .get("ts")
        .and_then(|v| v.as_i64())
        .unwrap_or(0);
    if maintenant - last < RENEW_DELAI {
        return false;
    }
    ecrire_json(&renew_file(), &json!({ "ts": maintenant }));
    let binaire = trouver_agy();
    let res = unsafe {
        Command::new(binaire)
            .arg("models")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .pre_exec(|| {
                libc::setsid();
                Ok(())
            })
            .status()
    };
    res.is_ok()
}

fn jeton() -> (Option<String>, Option<String>) {
    let Some(brut) = run_cmd_stdout(
        "secret-tool",
        &["lookup", "service", "gemini", "username", "antigravity"],
    ) else {
        return (None, Some("jeton absent du trousseau".to_string()));
    };
    let Ok(charge) = serde_json::from_str::<Value>(brut.trim()) else {
        return (None, Some("jeton absent du trousseau".to_string()));
    };
    let bloc = charge.get("token").cloned().unwrap_or(Value::Null);
    let Some(acces) = bloc
        .get("access_token")
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
    else {
        return (None, Some("jeton sans access_token".to_string()));
    };
    if let Some(ech) = bloc.get("expiry").and_then(|v| v.as_str()) {
        if let Some(ts) = parse_utc_iso_secs(ech) {
            if ts <= now_secs() {
                return (
                    None,
                    Some("jeton expiré (relancer agy le renouvelle)".to_string()),
                );
            }
        }
    }
    (Some(acces.to_string()), None)
}

fn poster(url: &str, corps: &Value, acces: &str) -> Result<Value, (String, Option<u16>)> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(20))
        .build();
    match agent
        .post(url)
        .set("Authorization", &format!("Bearer {}", acces))
        .set("Content-Type", "application/json")
        .set("User-Agent", AGENT)
        .send_json(corps.clone())
    {
        Ok(r) => r
            .into_json::<Value>()
            .map_err(|e| (e.to_string(), None)),
        Err(ureq::Error::Status(code, _)) => Err((format!("HTTP {}", code), Some(code))),
        Err(ureq::Error::Transport(t)) => Err((t.to_string(), None)),
    }
}

fn etiquette(model: &str) -> &'static str {
    let bas = model.to_ascii_lowercase();
    for (motif, nom) in [
        ("claude-opus", "Claude Opus"),
        ("claude-sonnet", "Claude Sonnet"),
        ("gpt", "GPT-OSS 120B"),
        ("argon", "Gemini Argon"),
        ("-pro", "Gemini Pro"),
        ("flash", "Gemini Flash"),
    ] {
        if bas.contains(motif) {
            return nom;
        }
    }
    ""
}

fn famille(model_id: &str) -> &'static str {
    if model_id.starts_with("claude") {
        "Claude"
    } else if model_id.starts_with("gemini") {
        "Gemini Flash"
    } else if model_id.starts_with("gpt") {
        "GPT"
    } else {
        "autres"
    }
}

fn court_nom(nom: &str) -> String {
    let re = Regex::new(r"\s*\([^)]*\)\s*$").unwrap();
    let stripped = re.replace(nom, "").trim().to_string();
    if stripped.to_ascii_lowercase().starts_with("claude ") {
        stripped[7..].to_string()
    } else {
        stripped
    }
}

struct ModeleInfo {
    model: String,
    #[allow(dead_code)]
    nom: String,
    reste: f64,
    reset: String,
}

fn fenetres_de(modeles: Vec<ModeleInfo>) -> Vec<Value> {
    let mut partages: HashMap<String, Vec<ModeleInfo>> = HashMap::new();
    for m in modeles {
        if !m.reset.is_empty() {
            partages.entry(m.reset.clone()).or_default().push(m);
        }
    }
    let mut fenetres: Vec<(i64, f64, Vec<String>, Vec<Value>)> = Vec::new();
    for (remise, groupe) in partages {
        let Some(reset_at) = parse_utc_iso_secs(&remise) else {
            continue;
        };
        let pire = groupe
            .iter()
            .map(|m| m.reste)
            .fold(f64::INFINITY, f64::min);
        let fams: BTreeSet<String> = groupe
            .iter()
            .filter(|m| m.reste <= pire + 1e-9)
            .map(|m| famille(&m.model).to_string())
            .collect();
        let mods: Vec<Value> = groupe
            .iter()
            .map(|m| json!({ "model": m.model, "reste": m.reste }))
            .collect();
        fenetres.push((reset_at, pire, fams.into_iter().collect(), mods));
    }
    if fenetres.is_empty() {
        return vec![];
    }
    let maintenant = now_secs();
    let tardive = fenetres.iter().map(|f| f.0).max().unwrap_or(0);
    let count = fenetres.len();
    let mut out: Vec<(f64, i64, Value)> = fenetres
        .into_iter()
        .map(|(reset_at, pire, fams, mods)| {
            let hebdo = if count > 1 {
                reset_at == tardive
            } else {
                reset_at - maintenant > 48 * 3600
            };
            let v = json!({
                "reset_at": reset_at,
                "reste": pire,
                "familles": fams,
                "models": mods,
                "kind": if hebdo { "week" } else { "session" },
                "label": if hebdo { "hebdo" } else { "5 h" },
            });
            (pire, reset_at, v)
        })
        .collect();
    out.sort_by(|a, b| {
        a.0.partial_cmp(&b.0)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.1.cmp(&a.1))
    });
    out.into_iter().map(|t| t.2).collect()
}

fn lire_assist(acces: &str) -> (String, String, Option<String>) {
    match poster(API_ASSIST, &json!({ "metadata": { "ideType": "ANTIGRAVITY" } }), acces) {
        Ok(rep) => {
            let palier = rep
                .get("paidTier")
                .and_then(|p| p.get("id"))
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .or_else(|| {
                    rep.get("currentTier")
                        .and_then(|p| p.get("id"))
                        .and_then(|v| v.as_str())
                })
                .unwrap_or("")
                .to_string();
            let proj = rep
                .get("cloudaicompanionProject")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            (proj, palier, None)
        }
        Err((msg, _)) => (String::new(), String::new(), Some(format!("Code Assist : {}", msg))),
    }
}

fn lire_modeles(acces: &str, projet: &str) -> (Option<Vec<Value>>, Option<String>, Option<u16>) {
    let body = if projet.is_empty() {
        json!({})
    } else {
        json!({ "project": projet })
    };
    let rep = match poster(API_MODELES, &body, acces) {
        Ok(r) => r,
        Err((msg, code)) => return (None, Some(format!("API modèles : {}", msg)), code),
    };
    let nom_re = Regex::new(r"(?i)gemini|claude|gpt").unwrap();
    let mut utiles = Vec::new();
    if let Some(table) = rep.get("models").and_then(|v| v.as_object()) {
        for (nom, info) in table {
            if !nom_re.is_match(nom) {
                continue;
            }
            let quota = info.get("quotaInfo").cloned().unwrap_or(Value::Null);
            let Some(reset) = quota.get("resetTime").and_then(|v| v.as_str()) else {
                continue;
            };
            if reset.is_empty() {
                continue;
            }
            let reste = quota
                .get("remainingFraction")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
            utiles.push(ModeleInfo {
                model: nom.clone(),
                nom: court_nom(info.get("displayName").and_then(|v| v.as_str()).unwrap_or(nom)),
                reste: (reste * 10000.0).round() / 10000.0,
                reset: reset.to_string(),
            });
        }
    }
    let fenetres = fenetres_de(utiles);
    if fenetres.is_empty() {
        (None, Some("aucun modèle quota dans la réponse".to_string()), None)
    } else {
        (Some(fenetres), None, None)
    }
}

fn lire_quota(acces: &str, projet: &str) -> (Option<Vec<Value>>, Option<String>, Option<u16>) {
    let rep = match poster(API_QUOTA, &json!({ "project": projet }), acces) {
        Ok(r) => r,
        Err((msg, code)) => return (None, Some(format!("API quota : {}", msg)), code),
    };
    let mut modeles = Vec::new();
    if let Some(buckets) = rep.get("buckets").and_then(|v| v.as_array()) {
        for b in buckets {
            let reste = b
                .get("remainingFraction")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);
            modeles.push(ModeleInfo {
                model: b
                    .get("modelId")
                    .and_then(|v| v.as_str())
                    .unwrap_or("?")
                    .to_string(),
                nom: String::new(),
                reste: (reste * 10000.0).round() / 10000.0,
                reset: b
                    .get("resetTime")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
            });
        }
    }
    let fenetres = fenetres_de(modeles);
    if fenetres.is_empty() {
        (None, Some("aucun compartiment quota dans la réponse".to_string()), None)
    } else {
        (Some(fenetres), None, None)
    }
}

fn interroger_api(acces: &str) -> (Option<Vec<Value>>, Option<String>, Option<u16>, String) {
    let (projet, palier, souci) = lire_assist(acces);
    if let Some(s) = souci {
        return (None, Some(s), None, String::new());
    }
    let (f1, r1, c1) = lire_modeles(acces, &projet);
    if f1.is_some() {
        return (f1, None, None, palier);
    }
    if c1 == Some(401) {
        return (None, r1, Some(401), palier);
    }
    let (f2, r2, c2) = lire_quota(acces, &projet);
    if f2.is_some() {
        return (f2, None, None, palier);
    }
    (None, r2.or(r1), c2, palier)
}

fn depuis_api() -> (Option<Vec<Value>>, Option<String>, String) {
    let (mut acces, raison) = jeton();
    if acces.is_none() {
        if raison.as_deref().unwrap_or("").contains("expiré") && renouveler() {
            acces = jeton().0;
        }
        if acces.is_none() {
            return (None, raison, String::new());
        }
    }
    let a = acces.unwrap();
    let (f1, souci, code, palier) = interroger_api(&a);
    if f1.is_some() {
        return (f1, None, palier);
    }
    if code == Some(401) && renouveler() {
        if let (Some(a2), _) = jeton() {
            let (f2, souci2, _, palier2) = interroger_api(&a2);
            if f2.is_some() {
                return (f2, None, palier2);
            }
            return (None, souci2.or(souci).or(raison), palier2);
        }
    }
    (None, souci.or(raison), palier)
}

// ── source 2 : logs ───────────────────────────────────────────────────────────

fn annee_du_fichier(chemin: &Path) -> (i32, i32, i32) {
    let name = chemin.file_name().and_then(|s| s.to_str()).unwrap_or("");
    let re = Regex::new(r"(20\d{2})(\d{2})(\d{2})_").unwrap();
    if let Some(cap) = re.captures(name) {
        return (
            cap[1].parse().unwrap_or(2026),
            cap[2].parse().unwrap_or(1),
            cap[3].parse().unwrap_or(1),
        );
    }
    let mtime = fs::metadata(chemin)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as libc::time_t)
        .unwrap_or(0);
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&mtime, &mut tm);
        (tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)
    }
}

fn depuis_logs() -> Map<String, Value> {
    let now = now_secs();
    let line_re = Regex::new(r"^([IWEF])(\d{2})(\d{2}) (\d{2}):(\d{2}):(\d{2})\.\d+\s+\d+\s+\S+\]\s*(.*)$").unwrap();
    let delai_re = Regex::new(r"Resets in (?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?").unwrap();
    let h = home_dir();
    let log_dirs = [
        h.join(".gemini/antigravity/log"),
        h.join(".gemini/antigravity-cli/log"),
    ];

    let mut tous: Vec<(i64, i64, String)> = Vec::new();
    for dir in &log_dirs {
        let Ok(rd) = fs::read_dir(dir) else {
            continue;
        };
        let mut files: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("log"))
            .collect();
        files.sort();
        for f in files {
            let (annee, mois_f, jour_f) = annee_du_fichier(&f);
            let Ok(txt) = fs::read_to_string(&f) else {
                continue;
            };
            for line in txt.lines() {
                if !line.contains("Individual quota reached") {
                    continue;
                }
                let Some(cap) = line_re.captures(line) else {
                    continue;
                };
                let Some(dcap) = delai_re.captures(&cap[7]) else {
                    continue;
                };
                let hh: i64 = dcap.get(1).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
                let mm: i64 = dcap.get(2).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
                let ss: i64 = dcap.get(3).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
                let secs = hh * 3600 + mm * 60 + ss;
                if secs <= 0 {
                    continue;
                }
                let mois: i32 = cap[2].parse().unwrap_or(1);
                let jour: i32 = cap[3].parse().unwrap_or(1);
                let mut annee_l = annee;
                if mois_f == 12 && mois == 1 {
                    annee_l += 1;
                } else if (mois, jour) > (mois_f, jour_f) {
                    annee_l -= 1;
                }
                let instant = unsafe {
                    let mut tm: libc::tm = std::mem::zeroed();
                    tm.tm_year = annee_l - 1900;
                    tm.tm_mon = mois - 1;
                    tm.tm_mday = jour;
                    tm.tm_hour = cap[4].parse().unwrap_or(0);
                    tm.tm_min = cap[5].parse().unwrap_or(0);
                    tm.tm_sec = cap[6].parse().unwrap_or(0);
                    tm.tm_isdst = -1;
                    libc::mktime(&mut tm) as i64
                };
                if instant > 0 {
                    tous.push((instant, secs, f.to_string_lossy().to_string()));
                }
            }
        }
    }

    let mut map = Map::new();
    map.insert("ok".into(), json!(true));
    map.insert("provider".into(), json!("antigravity"));
    map.insert("source".into(), json!("logs"));

    if tous.is_empty() {
        map.insert("state".into(), json!("free"));
        map.insert("windows".into(), json!([]));
        map.insert("detail".into(), json!("aucun épuisement journalisé"));
        return map;
    }

    let mut fenetres: HashMap<&str, (i64, i64)> = HashMap::new();
    for &(instant, secs, _) in &tous {
        let genre = if secs < 24 * 3600 { "session" } else { "week" };
        if fenetres.get(genre).map(|e| instant > e.0).unwrap_or(true) {
            fenetres.insert(genre, (instant, secs));
        }
    }
    let mut sortie: Vec<(i64, Value)> = fenetres
        .into_iter()
        .map(|(genre, (instant, secs))| {
            let remise = instant + secs;
            (
                remise,
                json!({
                    "kind": genre,
                    "reset_at": remise,
                    "seconds_left": (remise - now).max(0),
                }),
            )
        })
        .collect();
    sortie.sort_by_key(|t| t.0);
    let actives = sortie
        .iter()
        .any(|(_, v)| v.get("seconds_left").and_then(|s| s.as_i64()).unwrap_or(0) > 0);
    let dernier = tous.iter().max_by_key(|e| e.0).unwrap();
    let passee = tous
        .iter()
        .filter(|e| e.0 + e.1 < now)
        .map(|e| (e.0 + e.1, if e.1 < 24 * 3600 { "session" } else { "week" }))
        .max_by_key(|t| t.0);

    map.insert(
        "state".into(),
        json!(if actives { "exhausted" } else { "free" }),
    );
    map.insert(
        "windows".into(),
        Value::Array(sortie.into_iter().map(|t| t.1).collect()),
    );
    map.insert("source_log".into(), json!(dernier.2));
    map.insert("last_event".into(), json!(dernier.0));
    map.insert("last_reset_at".into(), json!(passee.map(|p| p.0).unwrap_or(0)));
    map.insert("last_reset_kind".into(), json!(passee.map(|p| p.1).unwrap_or("")));
    map.insert("detail".into(), json!("déduit des logs (API indisponible)"));
    map
}

// ── présentation ──────────────────────────────────────────────────────────────

fn lignes_de(fenetres: &[Value]) -> Vec<Value> {
    let mut pires: HashMap<(&str, &str), (f64, i64)> = HashMap::new();
    for f in fenetres {
        let tranche = if f.get("kind").and_then(|v| v.as_str()) == Some("week") {
            "7 j"
        } else {
            "5 h"
        };
        let reset_at = f.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
        if let Some(mods) = f.get("models").and_then(|v| v.as_array()) {
            for m in mods {
                let nom = etiquette(m.get("model").and_then(|v| v.as_str()).unwrap_or(""));
                if nom.is_empty() {
                    continue;
                }
                let reste = m.get("reste").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let key = (nom, tranche);
                if pires.get(&key).map(|e| reste < e.0).unwrap_or(true) {
                    pires.insert(key, (reste, reset_at));
                }
            }
        }
    }
    let mut lignes: Vec<(bool, &str, Value)> = pires
        .into_iter()
        .map(|((nom, tranche), (reste, remise))| {
            let alerte = reste <= SEUIL_ALERTE;
            let pct = (reste * 100.0).round() as i64;
            let ech = if remise != 0 {
                echeance_fmt(remise)
            } else {
                String::new()
            };
            (
                alerte,
                nom,
                json!({
                    "nom": nom,
                    "tranche": tranche,
                    "valeur": format!("{:>3} %", pct),
                    "echeance": ech,
                    "alerte": alerte,
                }),
            )
        })
        .collect();
    lignes.sort_by(|a, b| {
        let ka = if a.0 { 0 } else { 1 };
        let kb = if b.0 { 0 } else { 1 };
        ka.cmp(&kb).then_with(|| a.1.cmp(b.1))
    });
    lignes.into_iter().map(|t| t.2).collect()
}

fn presenter_ag(mut donnees: Map<String, Value>) -> Value {
    if !donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return Value::Object(donnees);
    }

    if let Some(lignes_agy) = donnees.get("lignes").and_then(|v| v.as_array()).cloned() {
        if !lignes_agy.is_empty() {
            let mut pied = Vec::new();
            if donnees.get("source").and_then(|v| v.as_str()) == Some("cache") {
                let rel = donnees.get("releve_ts").and_then(|v| v.as_i64()).unwrap_or(0);
                pied.push(mesure_ext("", "", 0, rel, "relevé", 0));
            }
            let alerte = lignes_agy
                .iter()
                .any(|l| l.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false));
            donnees.insert("fournisseur".into(), json!("Antigravity"));
            donnees.insert("icone".into(), json!("rocket"));
            donnees.insert("mesures".into(), Value::Array(pied));
            donnees.insert("alerte".into(), json!(alerte));
            return Value::Object(donnees);
        }
    }

    if let Some(fenetres) = donnees
        .get("percent_windows")
        .and_then(|v| v.as_array())
        .cloned()
    {
        if !fenetres.is_empty() {
            let lignes = lignes_de(&fenetres);
            let mut pied = Vec::new();
            if lignes.is_empty() {
                if let Some(b) = fenetres
                    .iter()
                    .find(|f| f.get("reste").and_then(|v| v.as_f64()).unwrap_or(0.0) <= 0.0)
                {
                    let lbl = b.get("label").and_then(|v| v.as_str()).unwrap_or("");
                    let ra = b.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
                    pied.push(mesure_ext(
                        "",
                        "",
                        0,
                        0,
                        &format!("{} rouvre {}", lbl, echeance_fmt(ra)),
                        0,
                    ));
                } else if donnees.get("source").and_then(|v| v.as_str()) == Some("cache") {
                    let now = now_secs();
                    if let Some(plus_tard) = donnees
                        .get("windows")
                        .and_then(|v| v.as_array())
                        .into_iter()
                        .flatten()
                        .filter(|f| f.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0) > now)
                        .max_by_key(|f| f.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0))
                    {
                        let k = if plus_tard.get("kind").and_then(|v| v.as_str()) == Some("week") {
                            "hebdo"
                        } else {
                            "5 h"
                        };
                        let ra = plus_tard.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
                        pied.push(mesure_ext(
                            "",
                            "",
                            0,
                            0,
                            &format!("{} rouvre {}", k, echeance_fmt(ra)),
                            0,
                        ));
                    }
                }
            }
            if donnees.get("source").and_then(|v| v.as_str()) == Some("cache") {
                let rel = donnees.get("releve_ts").and_then(|v| v.as_i64()).unwrap_or(0);
                pied.push(mesure_ext("", "", 0, rel, "relevé", 0));
            }
            let palier = donnees
                .get("palier")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let sans_pro = !palier.is_empty() && !palier.to_ascii_lowercase().contains("pro");
            if sans_pro {
                pied.push(mesure_ext(
                    "",
                    "",
                    0,
                    0,
                    &format!("palier {}", palier.replace('-', " ")),
                    0,
                ));
            }
            let min_reste = fenetres
                .iter()
                .map(|f| f.get("reste").and_then(|v| v.as_f64()).unwrap_or(1.0))
                .fold(f64::INFINITY, f64::min);
            let alerte = sans_pro
                || lignes
                    .iter()
                    .any(|l| l.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false))
                || min_reste <= SEUIL_ALERTE;

            donnees.insert("fournisseur".into(), json!("Antigravity"));
            donnees.insert("icone".into(), json!("rocket"));
            donnees.insert("alerte".into(), json!(alerte));
            if !lignes.is_empty() {
                donnees.insert("mesures".into(), Value::Array(pied));
                donnees.insert("lignes".into(), Value::Array(lignes));
                return Value::Object(donnees);
            }
            let mut mesures = Vec::new();
            for (i, f) in fenetres.iter().enumerate() {
                let pct = (f.get("reste").and_then(|v| v.as_f64()).unwrap_or(0.0) * 100.0).round() as i64;
                let fams: Vec<&str> = f
                    .get("familles")
                    .and_then(|v| v.as_array())
                    .map(|a| a.iter().filter_map(|x| x.as_str()).collect())
                    .unwrap_or_default();
                let fam_str = if fams.is_empty() {
                    "quota".to_string()
                } else {
                    fams.join(" · ")
                };
                let lbl = f.get("label").and_then(|v| v.as_str()).unwrap_or("");
                let ra = f.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
                if i == 0 {
                    mesures.push(mesure_ext(
                        &format!("{} %", pct),
                        &format!("{} · {}", lbl, fam_str),
                        0,
                        0,
                        "",
                        ra,
                    ));
                } else {
                    mesures.push(mesure_ext(
                        "",
                        "",
                        0,
                        0,
                        &format!("{} · {} {} %", lbl, fam_str, pct),
                        ra,
                    ));
                }
            }
            mesures.extend(pied);
            donnees.insert("mesures".into(), Value::Array(mesures));
            return Value::Object(donnees);
        }
    }

    let maintenant = now_secs();
    let mut par_genre: HashMap<String, (i64, String)> = HashMap::new();
    for f in donnees
        .get("windows")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
    {
        let k = f.get("kind").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let ra = f.get("reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
        par_genre.insert(k.clone(), (ra, k));
    }
    fn libelle_g(g: &str) -> &str {
        match g {
            "session" => "5 h",
            "week" => "hebdo",
            other => other,
        }
    }
    let actives: Vec<&(i64, String)> = par_genre.values().filter(|v| v.0 > maintenant).collect();
    let mut mesures = Vec::new();
    if let Some(principale) = actives.iter().max_by_key(|v| v.0) {
        let genre = principale.1.as_str();
        mesures.push(mesure_ext(
            &duree_fmt(principale.0 - maintenant),
            &format!("{} · épuisé", libelle_g(genre)),
            principale.0,
            0,
            "",
            0,
        ));
        let autre = if genre == "week" { "session" } else { "week" };
        if let Some((ra, _)) = par_genre.get(autre).filter(|v| v.0 > maintenant) {
            mesures.push(mesure_ext(
                &duree_fmt(*ra - maintenant),
                &format!("{} épuisée", libelle_g(autre)),
                *ra,
                0,
                "",
                0,
            ));
        } else {
            mesures.push(mesure(libelle_g(autre), "libre"));
        }
    } else {
        mesures.push(mesure("libre", "Antigravity"));
        let remise = donnees.get("last_reset_at").and_then(|v| v.as_i64()).unwrap_or(0);
        if remise > 0 {
            let genre = donnees
                .get("last_reset_kind")
                .and_then(|v| v.as_str())
                .unwrap_or("");
            mesures.push(mesure_ext(
                &format!("reset {}", libelle_g(genre)),
                "",
                0,
                remise,
                "",
                0,
            ));
        }
    }
    donnees.insert("fournisseur".into(), json!("Antigravity"));
    donnees.insert("icone".into(), json!("rocket"));
    donnees.insert("mesures".into(), Value::Array(mesures));
    donnees.insert("alerte".into(), json!(!actives.is_empty()));
    Value::Object(donnees)
}

fn analyser(force: bool) -> Map<String, Value> {
    let (agy, raison_agy) = depuis_agy(force);
    if !agy.is_empty() {
        let pire = agy.iter().map(|f| f.reste).fold(f64::INFINITY, f64::min);
        let maintenant = now_secs();
        let windows: Vec<Value> = agy
            .iter()
            .map(|f| {
                json!({
                    "kind": if f.tranche == "7 j" { "week" } else { "session" },
                    "reset_at": f.reset_at,
                    "seconds_left": (f.reset_at - maintenant).max(0),
                })
            })
            .collect();
        let mut map = Map::new();
        map.insert("ok".into(), json!(true));
        map.insert("provider".into(), json!("antigravity"));
        map.insert("state".into(), json!(if pire <= 0.0 { "exhausted" } else { "free" }));
        map.insert("reste_min".into(), json!(pire));
        map.insert("lignes".into(), Value::Array(lignes_de_agy(&agy)));
        map.insert("windows".into(), Value::Array(windows));
        map.insert("source".into(), json!("agy"));
        return map;
    }

    let (fenetres_opt, raison, palier) = depuis_api();
    if let Some(fenetres) = fenetres_opt {
        let pire = fenetres
            .iter()
            .map(|f| f.get("reste").and_then(|v| v.as_f64()).unwrap_or(0.0))
            .fold(f64::INFINITY, f64::min);
        ecrire_json(
            &plein_file(),
            &json!({ "ts": now_secs(), "percent_windows": fenetres, "palier": palier }),
        );
        let mut map = Map::new();
        map.insert("ok".into(), json!(true));
        map.insert("provider".into(), json!("antigravity"));
        map.insert("state".into(), json!(if pire <= 0.0 { "exhausted" } else { "free" }));
        map.insert("reste_min".into(), json!(pire));
        map.insert("percent_windows".into(), Value::Array(fenetres));
        map.insert("palier".into(), json!(palier));
        map.insert("source".into(), json!("api"));
        return map;
    }

    let mut donnees = depuis_logs();
    donnees.insert(
        "api_error".into(),
        raison.map(|s| json!(s)).unwrap_or(Value::Null),
    );
    if !raison_agy.is_empty() {
        donnees.insert("agy_error".into(), json!(raison_agy));
    }
    donnees.insert("palier".into(), json!(palier));

    let plein = read_json_value(&plein_file());
    let plein_ts = plein.get("ts").and_then(|v| v.as_i64()).unwrap_or(0);
    let age = now_secs() - plein_ts;
    if let Some(pw) = plein.get("percent_windows").and_then(|v| v.as_array()) {
        if !pw.is_empty() && (-60..PLEIN_TTL).contains(&age) {
            donnees.insert("percent_windows".into(), Value::Array(pw.clone()));
            if let Some(p) = plein.get("palier").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
                donnees.insert("palier".into(), json!(p));
            }
            donnees.insert("releve_ts".into(), json!(plein_ts));
            donnees.insert("source".into(), json!("cache"));
        }
    }
    donnees
}

pub fn antigravity_data(force: bool) -> Value {
    let cp = cache_file();
    if !force {
        if let Some(mut c) = read_json_value(&cp).as_object().cloned() {
            let ts = c.get("ts").and_then(|v| v.as_i64()).unwrap_or(0);
            if (now_secs() - ts) < TTL {
                c.insert("cached".into(), json!(true));
                return presenter_ag(c);
            }
        }
    }
    let mut donnees = analyser(force);
    if donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        donnees.insert("ts".into(), json!(now_secs()));
        donnees.insert("cached".into(), json!(false));
        ecrire_json(&cp, &Value::Object(donnees.clone()));
    }
    presenter_ag(donnees)
}

pub fn run(args: &[String]) -> i32 {
    let force = args.iter().any(|a| a == "--force");
    println!("{}", antigravity_data(force));
    0
}
