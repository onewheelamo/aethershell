use crate::common::io::{read_json_value, run_cmd, run_cmd_stdout, write_json_atomic};
use crate::common::lock::FileLock;
use crate::common::paths::{home_dir, runtime_dir};
use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Map, Value};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::MetadataExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const MAX_SESSIONS: usize = 10;
const DELAI_INACTIF: f64 = 900.0;
const DELAI_PERIME: f64 = 300.0;
const MAX_EXECUTIONS: usize = 5;
const MAX_CRON: usize = 4;
const DELAI_APPROBATION: f64 = 300.0;

fn now_f64() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn format_utc_iso(epoch: f64) -> String {
    unsafe {
        let secs = epoch as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::gmtime_r(&secs, &mut tm);
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    }
}

fn now_utc_iso() -> String {
    format_utc_iso(now_f64())
}

fn parse_utc_iso(s: &str) -> Option<f64> {
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
            Some(epoch as f64)
        }
    }
}

fn which_exists(prog: &str) -> bool {
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            if dir.join(prog).is_file() {
                return true;
            }
        }
    }
    false
}

fn hermes_home() -> PathBuf {
    home_dir().join(".hermes")
}

fn qs_runtime_dir() -> PathBuf {
    runtime_dir().join("quickshell")
}

fn chemin_etat() -> PathBuf {
    qs_runtime_dir().join("hermes-etat.json")
}

fn chemin_approbations() -> PathBuf {
    qs_runtime_dir().join("hermes-approbations.json")
}

fn chemin_socket() -> PathBuf {
    qs_runtime_dir().join("hermes-approbations.sock")
}

fn val_f64(v: Option<&Value>) -> Option<f64> {
    v.and_then(|x| {
        x.as_f64()
            .or_else(|| x.as_i64().map(|i| i as f64))
            .or_else(|| x.as_str().and_then(|s| s.parse::<f64>().ok()))
    })
}

fn val_i64(v: Option<&Value>) -> i64 {
    v.and_then(|x| {
        x.as_i64()
            .or_else(|| x.as_f64().map(|f| f as i64))
            .or_else(|| x.as_str().and_then(|s| s.parse::<i64>().ok()))
    })
    .unwrap_or(0)
}

// ── hermes_lecteur ────────────────────────────────────────────────────────────

fn bases() -> Vec<(String, PathBuf)> {
    let mut trouvees = Vec::new();
    let racine = hermes_home();
    let profils = racine.join("profiles");
    if profils.is_dir() {
        if let Ok(rd) = fs::read_dir(&profils) {
            let mut dirs: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
            dirs.sort();
            for d in dirs {
                let base = d.join("state.db");
                if base.is_file() {
                    if let Some(name) = d.file_name().and_then(|s| s.to_str()) {
                        trouvees.push((name.to_string(), base));
                    }
                }
            }
        }
    }
    let globale = racine.join("state.db");
    if globale.is_file() {
        trouvees.push(("defaut".to_string(), globale));
    }
    trouvees
}

fn open_ro(chemin: &Path) -> rusqlite::Result<Connection> {
    let cx = Connection::open_with_flags(
        chemin,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    let _ = cx.busy_timeout(Duration::from_secs(2));
    Ok(cx)
}

fn table_columns(cx: &Connection, table: &str) -> HashSet<String> {
    let mut cols = HashSet::new();
    let Ok(mut stmt) = cx.prepare(&format!("PRAGMA table_info({})", table)) else {
        return cols;
    };
    if let Ok(rows) = stmt.query_map([], |r| r.get::<_, String>(1)) {
        for c in rows.flatten() {
            cols.insert(c);
        }
    }
    cols
}

fn sql_val_to_json(v: rusqlite::types::ValueRef<'_>) -> Value {
    match v {
        rusqlite::types::ValueRef::Null => Value::Null,
        rusqlite::types::ValueRef::Integer(i) => json!(i),
        rusqlite::types::ValueRef::Real(f) => json!(f),
        rusqlite::types::ValueRef::Text(b) => json!(String::from_utf8_lossy(b).to_string()),
        rusqlite::types::ValueRef::Blob(b) => json!(String::from_utf8_lossy(b).to_string()),
    }
}

const CHAMPS_SESSIONS: &[&str] = &[
    "id",
    "title",
    "model",
    "cwd",
    "source",
    "started_at",
    "last_activity_at",
    "last_activity_description",
    "ended_at",
    "end_reason",
    "archived",
    "pinned",
    "profile_name",
    "input_tokens",
    "output_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "estimated_cost_usd",
    "tool_call_count",
    "message_count",
    "git_repo_root",
    "git_branch",
];

fn derniere_demande(chemin: &Path, session_id: &str, longueur: usize) -> String {
    let Ok(cx) = open_ro(chemin) else {
        return String::new();
    };
    let has_msgs: bool = cx
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='messages'",
            [],
            |r| r.get::<_, i64>(0),
        )
        .unwrap_or(0)
        > 0;
    if !has_msgs {
        return String::new();
    }
    let cols = table_columns(&cx, "messages");
    if !cols.contains("session_id") || !cols.contains("role") || !cols.contains("content") {
        return String::new();
    }
    let filtre = if cols.contains("active") {
        " AND active = 1"
    } else {
        ""
    };
    let ordre = if cols.contains("timestamp") {
        "timestamp"
    } else {
        "id"
    };
    let sql = format!(
        "SELECT content FROM messages WHERE session_id = ? AND role = 'user'{} ORDER BY {} DESC LIMIT 1",
        filtre, ordre
    );
    let texte: String = cx
        .query_row(&sql, [session_id], |r| {
            Ok(r.get::<_, Option<String>>(0)?.unwrap_or_default())
        })
        .unwrap_or_default();
    let collapsed: Vec<&str> = texte.split_whitespace().collect();
    collapsed
        .join(" ")
        .chars()
        .take(longueur)
        .collect()
}

fn lire_sessions(limite: usize) -> Option<Vec<Map<String, Value>>> {
    let all_bases = bases();
    let mut toutes: Vec<Map<String, Value>> = Vec::new();
    let mut lisible = false;

    for (profil, chemin) in &all_bases {
        let Ok(cx) = open_ro(chemin) else {
            continue;
        };
        let cols = table_columns(&cx, "sessions");
        if cols.is_empty() {
            continue;
        }
        lisible = true;
        let champs: Vec<&str> = CHAMPS_SESSIONS
            .iter()
            .copied()
            .filter(|c| cols.contains(*c))
            .collect();
        if champs.is_empty() {
            continue;
        }
        let ordre = if cols.contains("last_activity_at") {
            "last_activity_at"
        } else {
            "started_at"
        };
        let where_clause = if cols.contains("archived") {
            " WHERE archived = 0"
        } else {
            ""
        };
        let sql = format!(
            "SELECT {} FROM sessions{} ORDER BY {} DESC LIMIT ?",
            champs.join(", "),
            where_clause,
            ordre
        );
        let Ok(mut stmt) = cx.prepare(&sql) else {
            continue;
        };
        let Ok(rows) = stmt.query_map([limite as i64], |row| {
            let mut m = Map::new();
            for (idx, col) in champs.iter().enumerate() {
                if let Ok(vr) = row.get_ref(idx) {
                    m.insert((*col).to_string(), sql_val_to_json(vr));
                }
            }
            Ok(m)
        }) else {
            continue;
        };
        for mut d in rows.flatten() {
            let prof_val = d
                .get("profile_name")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .unwrap_or(profil)
                .to_string();
            d.insert("profil".into(), json!(prof_val));

            let ended = d.get("ended_at").map(|v| !v.is_null()).unwrap_or(false);
            let title_empty = d
                .get("title")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .is_empty();
            let in_tok = val_i64(d.get("input_tokens"));
            let msg_cnt = val_i64(d.get("message_count"));
            if ended && title_empty && in_tok == 0 && msg_cnt == 0 {
                continue;
            }
            toutes.push(d);
        }
    }

    if !lisible {
        return None;
    }

    toutes.sort_by(|a, b| {
        let ka = val_f64(a.get("last_activity_at").or_else(|| a.get("started_at"))).unwrap_or(0.0);
        let kb = val_f64(b.get("last_activity_at").or_else(|| b.get("started_at"))).unwrap_or(0.0);
        kb.partial_cmp(&ka).unwrap_or(std::cmp::Ordering::Equal)
    });
    toutes.truncate(limite);

    let base_map: HashMap<String, PathBuf> = all_bases.into_iter().collect();
    let fallback_db = hermes_home().join("state.db");
    for s in toutes.iter_mut().take(3) {
        let prof = s.get("profil").and_then(|v| v.as_str()).unwrap_or("");
        let db_path = base_map.get(prof).unwrap_or(&fallback_db);
        let sid = match s.get("id") {
            Some(Value::String(st)) => st.clone(),
            Some(Value::Number(n)) => n.to_string(),
            _ => String::new(),
        };
        let dem = if sid.is_empty() {
            String::new()
        } else {
            derniere_demande(db_path, &sid, 90)
        };
        s.insert("demande".into(), json!(dem));
    }
    Some(toutes)
}

fn dossiers_profils() -> Vec<(String, PathBuf)> {
    let mut trouves = Vec::new();
    let racine = hermes_home();
    let profils = racine.join("profiles");
    if profils.is_dir() {
        if let Ok(rd) = fs::read_dir(&profils) {
            let mut dirs: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
            dirs.sort();
            for d in dirs {
                if let Some(name) = d.file_name().and_then(|s| s.to_str()) {
                    trouves.push((name.to_string(), d));
                }
            }
        }
    }
    trouves.push(("defaut".to_string(), racine));
    trouves
}

fn taches_planifiees(limite: usize) -> Vec<Value> {
    let mut liste = Vec::new();
    for (profil, dossier) in dossiers_profils() {
        let data = read_json_value(&dossier.join("cron").join("jobs.json"));
        let taches_opt = if let Some(arr) = data.get("jobs").and_then(|v| v.as_array()) {
            Some(arr)
        } else {
            data.as_array()
        };
        let Some(taches) = taches_opt else {
            continue;
        };
        for t in taches {
            if !t.is_object() {
                continue;
            }
            let planif = t
                .get("schedule_display")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .or_else(|| {
                    t.get("schedule")
                        .and_then(|s| s.get("display"))
                        .and_then(|v| v.as_str())
                })
                .unwrap_or("");
            liste.push(json!({
                "nom": t.get("name").and_then(|v| v.as_str()).unwrap_or("sans nom"),
                "prochaine": t.get("next_run_at").cloned().unwrap_or(Value::Null),
                "dernier": t.get("last_status").and_then(|v| v.as_str()).unwrap_or(""),
                "quand": t.get("last_run_at").cloned().unwrap_or(Value::Null),
                "planification": planif,
                "profil": profil,
                "actif": t.get("enabled").and_then(|v| v.as_bool()).unwrap_or(true),
            }));
        }
    }
    liste.sort_by(|a, b| {
        let aa = !a.get("actif").and_then(|v| v.as_bool()).unwrap_or(true);
        let ba = !b.get("actif").and_then(|v| v.as_bool()).unwrap_or(true);
        let pa = a.get("prochaine").and_then(|v| v.as_str()).unwrap_or("9999");
        let pb = b.get("prochaine").and_then(|v| v.as_str()).unwrap_or("9999");
        (aa, pa).cmp(&(ba, pb))
    });
    liste.truncate(limite);
    liste
}

fn jetons_du_jour() -> Value {
    let debut: f64 = unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        tm.tm_hour = 0;
        tm.tm_min = 0;
        tm.tm_sec = 0;
        tm.tm_isdst = -1;
        libc::mktime(&mut tm) as f64
    };
    let mut total = 0i64;
    for (_, chemin) in bases() {
        let Ok(cx) = open_ro(&chemin) else {
            continue;
        };
        let cols = table_columns(&cx, "sessions");
        if !cols.contains("input_tokens") || !cols.contains("output_tokens") {
            continue;
        }
        let champ = if cols.contains("last_activity_at") {
            "last_activity_at"
        } else {
            "started_at"
        };
        let sql = format!(
            "SELECT COALESCE(SUM(input_tokens),0) + COALESCE(SUM(output_tokens),0) FROM sessions WHERE {} >= ?",
            champ
        );
        if let Ok(sum) = cx.query_row(&sql, [debut], |r| r.get::<_, i64>(0)) {
            total += sum;
        }
    }
    json!({ "jour": total, "tache": 0 })
}

fn processus_hermes() -> HashMap<String, Vec<u32>> {
    let mut vivants: HashMap<String, Vec<u32>> = HashMap::new();
    let uid = unsafe { libc::getuid() };
    let Ok(rd) = fs::read_dir("/proc") else {
        return vivants;
    };
    for ent in rd.flatten() {
        let name = ent.file_name();
        let Some(name_s) = name.to_str() else {
            continue;
        };
        if !name_s.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let Ok(pid) = name_s.parse::<u32>() else {
            continue;
        };
        let p = ent.path();
        let Ok(meta) = fs::metadata(&p) else {
            continue;
        };
        if meta.uid() != uid {
            continue;
        }
        let Ok(brut) = fs::read(p.join("cmdline")) else {
            continue;
        };
        if !brut.windows(10).any(|w| w == b"hermes_cli")
            || brut.windows(18).any(|w| w == b"process_supervisor")
        {
            continue;
        }
        let morceaux: Vec<&[u8]> = brut.split(|&b| b == 0).collect();
        let mut profil: Option<String> = None;
        for i in 0..morceaux.len() {
            if morceaux[i] == b"-p" && i + 1 < morceaux.len() {
                let cand = String::from_utf8_lossy(morceaux[i + 1]).trim().to_string();
                if !cand.is_empty() && !cand.starts_with('-') {
                    profil = Some(cand);
                }
            }
        }
        if let Some(pr) = profil {
            vivants.entry(pr).or_default().push(pid);
        }
    }
    vivants
}

fn marquer_vivantes(sessions: &mut [Map<String, Value>], vivants: &HashMap<String, Vec<u32>>) {
    let mut by_profil: HashMap<String, Vec<usize>> = HashMap::new();
    for (idx, s) in sessions.iter().enumerate() {
        let ended = val_f64(s.get("ended_at")).unwrap_or(0.0);
        if s.get("ended_at").map(|v| v.is_null()).unwrap_or(true) || ended == 0.0 {
            let prof = s
                .get("profil")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            by_profil.entry(prof).or_default().push(idx);
        }
    }
    for s in sessions.iter_mut() {
        s.insert("vivante".into(), json!(false));
        s.insert("pid".into(), Value::Null);
    }
    for (profil, mut indices) in by_profil {
        let pids = vivants.get(&profil);
        indices.sort_by(|&ia, &ib| {
            let ka = val_f64(sessions[ia].get("last_activity_at").or_else(|| sessions[ia].get("started_at"))).unwrap_or(0.0);
            let kb = val_f64(sessions[ib].get("last_activity_at").or_else(|| sessions[ib].get("started_at"))).unwrap_or(0.0);
            kb.partial_cmp(&ka).unwrap_or(std::cmp::Ordering::Equal)
        });
        if let (Some(pid_list), Some(&first_idx)) = (pids, indices.first()) {
            if let Some(&pid0) = pid_list.first() {
                sessions[first_idx].insert("vivante".into(), json!(true));
                sessions[first_idx].insert("pid".into(), json!(pid0));
            }
        }
    }
}

fn read_approbations_file() -> Vec<Value> {
    let d = read_json_value(&chemin_approbations());
    d.get("approbations")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter(|a| a.is_object()).cloned().collect())
        .unwrap_or_default()
}

fn iso_opt(v: Option<&Value>) -> Value {
    match val_f64(v) {
        Some(f) if f > 0.0 => json!(format_utc_iso(f)),
        _ => Value::Null,
    }
}

fn duree_session(s: &Map<String, Value>) -> i64 {
    let debut = val_f64(s.get("started_at")).unwrap_or(0.0);
    let ended = val_f64(s.get("ended_at")).unwrap_or(0.0);
    let vivante = s.get("vivante").and_then(|v| v.as_bool()).unwrap_or(false);
    let fin = if ended > 0.0 {
        ended
    } else if vivante {
        now_f64()
    } else {
        val_f64(s.get("last_activity_at")).unwrap_or(debut)
    };
    (fin - debut).max(0.0) as i64
}

fn secondes_session(s: &Map<String, Value>) -> f64 {
    val_f64(s.get("last_activity_at"))
        .or_else(|| val_f64(s.get("started_at")))
        .unwrap_or(0.0)
}

fn etat_gateway() -> Value {
    let racine = hermes_home();
    let gw = read_json_value(&racine.join("gateway_state.json"));
    let pid_val = gw
        .get("pid")
        .and_then(|v| v.as_i64())
        .or_else(|| read_json_value(&racine.join("gateway.pid")).get("pid").and_then(|v| v.as_i64()));
    let vivant = pid_val
        .map(|p| Path::new(&format!("/proc/{}", p)).exists())
        .unwrap_or(false);

    let ticker_file = racine.join("cron").join("ticker_heartbeat");
    let ticker_age = fs::read_to_string(&ticker_file)
        .ok()
        .and_then(|txt| txt.split_whitespace().next().and_then(|s| s.parse::<f64>().ok()))
        .map(|ts| (now_f64() - ts).max(0.0) as i64);

    let etat_service = run_cmd_stdout("systemctl", &["--user", "is-active", "hermes-gateway.service"])
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    let actif = vivant || etat_service == "active";
    let etat_str = if actif {
        "running"
    } else if etat_service == "inactive" {
        "stopped"
    } else {
        "unknown"
    };
    let svc_etat = if !etat_service.is_empty() {
        etat_service
    } else if vivant {
        "active".to_string()
    } else {
        "inactive".to_string()
    };

    json!({
        "actif": actif,
        "pid": if vivant { pid_val } else { None },
        "etat": etat_str,
        "service": "hermes-gateway.service",
        "service_etat": svc_etat,
        "profils": gw.get("served_profiles").cloned().unwrap_or_else(|| json!(["default"])),
        "active_agents": val_i64(gw.get("active_agents")),
        "version": gw.get("code_version").and_then(|v| v.as_str()).unwrap_or(""),
        "ticker_age_s": ticker_age,
        "ticker_actif": ticker_age.map(|a| a < 180).unwrap_or(false),
    })
}

fn derniers_logs(limite: usize) -> Vec<String> {
    let journal = hermes_home().join("logs").join("agent.log");
    let Ok(mut f) = File::open(&journal) else {
        return vec![];
    };
    let taille = f.metadata().map(|m| m.len()).unwrap_or(0);
    let offset = taille.saturating_sub(8192);
    let _ = f.seek(SeekFrom::Start(offset));
    let mut buf = Vec::new();
    if f.read_to_end(&mut buf).is_err() {
        return vec![];
    }
    let texte = String::from_utf8_lossy(&buf);
    let mut lignes: Vec<String> = texte
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();
    if lignes.len() > limite {
        lignes = lignes.split_off(lignes.len() - limite);
    }
    lignes
}

pub fn lecteur_etat() -> Value {
    let maintenant = now_f64();
    let Some(mut sessions) = lire_sessions(MAX_SESSIONS) else {
        return json!({ "present": false, "raison": "aucune base lisible" });
    };
    marquer_vivantes(&mut sessions, &processus_hermes());
    let attente = read_approbations_file();

    let mut actives_ids = HashSet::new();
    let mut actives_refs: Vec<&Map<String, Value>> = Vec::new();
    for s in &sessions {
        let viv = s.get("vivante").and_then(|v| v.as_bool()).unwrap_or(false);
        let ended = val_f64(s.get("ended_at")).unwrap_or(0.0);
        let open = s.get("ended_at").map(|v| v.is_null()).unwrap_or(true) || ended == 0.0;
        if viv || (open && (maintenant - secondes_session(s)) < DELAI_INACTIF) {
            let sid = s.get("id").map(|v| v.to_string()).unwrap_or_default();
            actives_ids.insert(sid);
            actives_refs.push(s);
        }
    }

    let mut executions = Vec::new();
    for s in &sessions {
        let viv = s.get("vivante").and_then(|v| v.as_bool()).unwrap_or(false);
        let ended = val_f64(s.get("ended_at")).unwrap_or(0.0);
        if viv || ended == 0.0 {
            continue;
        }
        let debut = val_f64(s.get("started_at")).unwrap_or(0.0);
        let fin = if ended > 0.0 { ended } else { debut };
        let duree = (fin - debut).max(0.0) as i64;
        let nom = s
            .get("title")
            .and_then(|v| v.as_str())
            .filter(|st| !st.is_empty())
            .or_else(|| s.get("last_activity_description").and_then(|v| v.as_str()))
            .unwrap_or("session");
        executions.push(json!({
            "nom": nom,
            "debut": iso_opt(s.get("started_at")),
            "duree_s": duree,
            "resultat": s.get("end_reason").and_then(|v| v.as_str()).unwrap_or("ok"),
            "modele": s.get("model").and_then(|v| v.as_str()).unwrap_or(""),
        }));
    }
    executions.truncate(5);

    let etat_court = if !attente.is_empty() {
        "attente"
    } else if !actives_refs.is_empty() {
        "en_cours"
    } else {
        "repos"
    };

    let mut tache = String::new();
    let mut depuis = Value::Null;
    if let Some(principal) = actives_refs.first() {
        tache = principal
            .get("demande")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .or_else(|| principal.get("title").and_then(|v| v.as_str()))
            .unwrap_or("session en cours")
            .to_string();
        depuis = iso_opt(principal.get("started_at"));
    } else if let Some(s0) = sessions.first() {
        tache = s0
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
    }

    let age_s = sessions
        .first()
        .map(|s0| (maintenant - secondes_session(s0)).max(0.0) as i64);

    let mut profils_set = BTreeSet::new();
    for s in &actives_refs {
        if let Some(p) = s.get("profil").and_then(|v| v.as_str()) {
            if !p.is_empty() {
                profils_set.insert(p.to_string());
            }
        }
    }
    let profils: Vec<String> = profils_set.into_iter().collect();

    let sessions_out: Vec<Value> = sessions
        .iter()
        .map(|s| {
            let sid_str = s.get("id").map(|v| v.to_string()).unwrap_or_default();
            let ended_present = s.get("ended_at").map(|v| !v.is_null()).unwrap_or(false)
                && val_f64(s.get("ended_at")).unwrap_or(0.0) != 0.0;
            let etat_s = if actives_ids.contains(&sid_str) {
                "en_cours"
            } else if ended_present {
                "terminee"
            } else {
                "inactive"
            };
            let tache_s = s
                .get("demande")
                .and_then(|v| v.as_str())
                .filter(|st| !st.is_empty())
                .or_else(|| s.get("title").and_then(|v| v.as_str()))
                .unwrap_or("");
            json!({
                "id": s.get("id").cloned().unwrap_or(Value::Null),
                "titre": s.get("title").and_then(|v| v.as_str()).unwrap_or(""),
                "tache": tache_s,
                "modele": s.get("model").and_then(|v| v.as_str()).unwrap_or(""),
                "profil": s.get("profil").and_then(|v| v.as_str()).unwrap_or(""),
                "dossier": s.get("cwd").and_then(|v| v.as_str()).unwrap_or(""),
                "depot": s.get("git_repo_root").and_then(|v| v.as_str()).unwrap_or(""),
                "branche": s.get("git_branch").and_then(|v| v.as_str()).unwrap_or(""),
                "source": s.get("source").and_then(|v| v.as_str()).unwrap_or(""),
                "debut": iso_opt(s.get("started_at")),
                "activite": iso_opt(s.get("last_activity_at")),
                "fin": iso_opt(s.get("ended_at")),
                "etat": etat_s,
                "vivante": s.get("vivante").and_then(|v| v.as_bool()).unwrap_or(false),
                "pid": s.get("pid").cloned().unwrap_or(Value::Null),
                "duree_s": duree_session(s),
                "jetons": val_i64(s.get("input_tokens")) + val_i64(s.get("output_tokens")),
                "outils": val_i64(s.get("tool_call_count")),
                "cout": s.get("estimated_cost_usd").cloned().unwrap_or(Value::Null),
            })
        })
        .collect();

    let att_3: Vec<Value> = attente.iter().take(3).cloned().collect();
    json!({
        "present": true,
        "source": "state.db",
        "etat": etat_court,
        "tache": tache,
        "depuis": depuis,
        "file": attente.len(),
        "executions": executions,
        "cron": taches_planifiees(6),
        "gateway": etat_gateway(),
        "logs": derniers_logs(12),
        "jetons": jetons_du_jour(),
        "age_s": age_s,
        "perime": false,
        "approbations": att_3,
        "attention": attente.len(),
        "profils": profils,
        "sessions": sessions_out,
        "ecrit": now_utc_iso(),
    })
}

pub fn run_lecteur(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("");
    match action {
        "etat" => {
            println!("{}", lecteur_etat());
            0
        }
        "sessions" => {
            let Some(mut sessions) = lire_sessions(MAX_SESSIONS) else {
                eprintln!("aucune base lisible");
                return 1;
            };
            marquer_vivantes(&mut sessions, &processus_hermes());
            let vals: Vec<Value> = sessions.into_iter().map(Value::Object).collect();
            println!(
                "{}",
                serde_json::to_string_pretty(&Value::Array(vals)).unwrap_or_default()
            );
            0
        }
        "processus" => {
            println!("{}", json!(processus_hermes()));
            0
        }
        _ => {
            println!("Usage: hermes-lecteur [etat|sessions|processus]");
            0
        }
    }
}

// ── hermes_applet ─────────────────────────────────────────────────────────────

fn lire_etat_fichier() -> Value {
    let fichier = chemin_etat();
    if !fichier.exists() {
        return json!({ "present": false });
    }
    let Ok(txt) = fs::read_to_string(&fichier) else {
        return json!({ "present": true, "illisible": true });
    };
    let Ok(Value::Object(mut map)) = serde_json::from_str::<Value>(&txt) else {
        return json!({ "present": true, "illisible": true });
    };
    let age = map
        .get("ecrit")
        .and_then(|v| v.as_str())
        .and_then(parse_utc_iso)
        .map(|t| now_f64() - t);
    map.insert("present".into(), json!(true));
    map.insert(
        "age_s".into(),
        age.map(|a| json!(a.round() as i64)).unwrap_or(Value::Null),
    );
    map.insert(
        "perime".into(),
        json!(age.map(|a| a > DELAI_PERIME).unwrap_or(true)),
    );
    Value::Object(map)
}

fn analyser_hermes() -> Value {
    let mut d = lecteur_etat();
    if !d.get("present").and_then(|v| v.as_bool()).unwrap_or(false) {
        d = lire_etat_fichier();
    }
    if !d.get("present").and_then(|v| v.as_bool()).unwrap_or(false) {
        return json!({
            "etat": "hors_ligne",
            "raison": d.get("raison").and_then(|v| v.as_str()).unwrap_or("état indisponible"),
        });
    }
    if d.get("illisible").and_then(|v| v.as_bool()).unwrap_or(false) {
        return json!({ "etat": "hors_ligne", "raison": "état illisible" });
    }

    let brut = d
        .get("etat")
        .and_then(|v| v.as_str())
        .unwrap_or("repos")
        .to_ascii_lowercase();
    let (mut symbole, mut libelle, mut niveau) = match brut.as_str() {
        "en_cours" => ("…", "en cours", "ok"),
        "attente" => ("!", "attend un accord", "attention"),
        "erreur" => ("!", "erreur", "critique"),
        _ => ("repos", "au repos", "ok"),
    };
    let perime = d.get("perime").and_then(|v| v.as_bool()).unwrap_or(false);
    if perime && brut == "en_cours" {
        libelle = "état périmé";
        niveau = "attention";
    } else if perime {
        libelle = "repos";
        symbole = "";
        niveau = "ok";
    }

    let attente = read_approbations_file();
    if !attente.is_empty() {
        symbole = "!";
        libelle = "accord à donner";
        niveau = "attention";
    }

    let executions: Vec<Value> = d
        .get("executions")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().take(5).cloned().collect())
        .unwrap_or_default();
    let cron: Vec<Value> = d
        .get("cron")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().take(6).cloned().collect())
        .unwrap_or_default();
    let att_3: Vec<Value> = attente.iter().take(3).cloned().collect();
    let attention = d
        .get("attention")
        .and_then(|v| v.as_u64())
        .unwrap_or(attente.len() as u64);

    json!({
        "etat": brut,
        "symbole": symbole,
        "libelle": libelle,
        "niveau": niveau,
        "alerte": matches!(niveau, "attention" | "critique"),
        "tache": d.get("tache").and_then(|v| v.as_str()).unwrap_or(""),
        "depuis": d.get("depuis").cloned().unwrap_or(Value::Null),
        "file": val_i64(d.get("file")),
        "executions": executions,
        "cron": cron,
        "gateway": d.get("gateway").cloned().unwrap_or_else(|| json!({})),
        "logs": d.get("logs").cloned().unwrap_or_else(|| json!([])),
        "jetons": d.get("jetons").cloned().unwrap_or_else(|| json!({})),
        "approbations": att_3,
        "attention": attention,
        "sessions": d.get("sessions").cloned().unwrap_or_else(|| json!([])),
        "profils": d.get("profils").cloned().unwrap_or_else(|| json!([])),
        "source": d.get("source").and_then(|v| v.as_str()).unwrap_or(""),
        "age_s": d.get("age_s").cloned().unwrap_or(Value::Null),
        "perime": perime,
        "present": true,
    })
}

fn presenter_hermes(mut a: Value) -> Value {
    let etat = a.get("etat").and_then(|v| v.as_str()).unwrap_or("");
    if etat == "hors_ligne" {
        return json!({
            "ok": true,
            "compact": { "valeur": "", "libelle": "", "alerte": false },
            "detail": { "hermes": a },
            "applet": "hermes",
            "icone": "rocket",
            "alerte": false,
        });
    }

    let has_app = a
        .get("approbations")
        .and_then(|v| v.as_array())
        .map(|arr| !arr.is_empty())
        .unwrap_or(false);
    let file_n = a.get("file").and_then(|v| v.as_i64()).unwrap_or(0);
    let mut alerte = a.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);

    let (valeur, libelle) = if has_app {
        alerte = true;
        if let Some(m) = a.as_object_mut() {
            m.insert("alerte".into(), json!(true));
        }
        ("!".to_string(), "accord à donner".to_string())
    } else if etat == "attente" {
        ("!".to_string(), "accord".to_string())
    } else if etat == "erreur" {
        ("!".to_string(), "erreur".to_string())
    } else if etat == "en_cours" {
        let prof_len = a
            .get("profils")
            .and_then(|v| v.as_array())
            .map(|p| p.len())
            .unwrap_or(0);
        if prof_len > 1 {
            (prof_len.to_string(), format!("{} sessions", prof_len))
        } else {
            let t: String = a
                .get("tache")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .chars()
                .take(24)
                .collect();
            (
                "…".to_string(),
                if t.is_empty() {
                    "en cours".to_string()
                } else {
                    t
                },
            )
        }
    } else if file_n > 0 {
        (file_n.to_string(), "en file".to_string())
    } else {
        (
            String::new(),
            a.get("libelle")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
        )
    };

    json!({
        "ok": true,
        "compact": { "valeur": valeur, "libelle": libelle, "alerte": alerte },
        "detail": { "hermes": a },
        "applet": "hermes",
        "icone": "rocket",
        "alerte": alerte,
    })
}

pub fn run_applet(args: &[String]) -> i32 {
    if let Some(cmd) = args.first().map(|s| s.as_str()) {
        match cmd {
            "--exemple" => {
                let exemple = json!({
                    "etat": "en_cours",
                    "tache": "veille des prix — 4 boutiques",
                    "depuis": "2026-11-06T20:42:00Z",
                    "file": 2,
                    "executions": [
                        {"nom": "revue des commits", "debut": "2026-11-06T20:12:00Z", "duree_s": 42, "resultat": "ok", "modele": "deepseek"},
                        {"nom": "sauvegarde du portable", "debut": "2026-11-06T19:40:00Z", "duree_s": 130, "resultat": "echec", "modele": "—"},
                    ],
                    "cron": [
                        {"nom": "revue hebdo", "prochaine": "2026-11-08T09:00:00Z", "dernier": "ok", "quand": "2026-11-01T09:00:00Z"},
                        {"nom": "veille prix", "prochaine": "2026-11-06T21:00:00Z", "dernier": "ok", "quand": "2026-11-06T20:00:00Z"},
                    ],
                    "jetons": {"jour": 12345, "tache": 1234},
                    "ecrit": now_utc_iso(),
                });
                let f = chemin_etat();
                let _ = write_json_atomic(&f, &exemple, 0o644);
                println!("{}", f.display());
                return 0;
            }
            "gateway-restart" | "gateway-start" | "gateway-stop" => {
                let action = cmd.split('-').nth(1).unwrap_or("restart");
                let res = run_cmd("systemctl", &["--user", action, "hermes-gateway.service"]);
                let (ok, code, out) = match res {
                    Some(o) => {
                        let s = format!(
                            "{}{}",
                            String::from_utf8_lossy(&o.stdout),
                            String::from_utf8_lossy(&o.stderr)
                        )
                        .trim()
                        .to_string();
                        (o.status.success(), o.status.code().unwrap_or(1), s)
                    }
                    None => (false, 1, "systemctl introuvable".to_string()),
                };
                println!("{}", json!({ "ok": ok, "action": action, "output": out }));
                return code;
            }
            "cron-tick" | "doctor" => {
                let sub = if cmd == "cron-tick" { "tick" } else { "doctor" };
                let res = run_cmd("hermes", &["cron", sub]);
                let (ok, code, out) = match res {
                    Some(o) => {
                        let s = format!(
                            "{}{}",
                            String::from_utf8_lossy(&o.stdout),
                            String::from_utf8_lossy(&o.stderr)
                        )
                        .trim()
                        .to_string();
                        (o.status.success(), o.status.code().unwrap_or(1), s)
                    }
                    None => (false, 1, "hermes introuvable".to_string()),
                };
                println!("{}", json!({ "ok": ok, "action": cmd, "output": out }));
                return code;
            }
            "quick-prompt" if args.len() > 1 => {
                let prompt = &args[1];
                let _ = Command::new("hermes")
                    .args(["-z", prompt])
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
                println!("{}", json!({ "ok": true, "action": "quick-prompt", "prompt": prompt }));
                return 0;
            }
            _ => {}
        }
    }

    let a = analyser_hermes();
    println!("{}", presenter_hermes(a));
    0
}

// ── hermes_publier ────────────────────────────────────────────────────────────

fn lire_etat_brut() -> Map<String, Value> {
    read_json_value(&chemin_etat())
        .as_object()
        .cloned()
        .unwrap_or_else(|| {
            json!({ "etat": "repos", "executions": [], "cron": [], "jetons": {} })
                .as_object()
                .unwrap()
                .clone()
        })
}

fn ecrire_etat(mut d: Map<String, Value>) {
    d.insert("ecrit".into(), json!(now_utc_iso()));
    let _ = write_json_atomic(&chemin_etat(), &Value::Object(d), 0o644);
}

fn arg_val<'a>(args: &'a [String], nom: &str) -> Option<&'a str> {
    for i in 0..args.len() {
        if args[i] == nom && i + 1 < args.len() {
            return Some(args[i + 1].as_str());
        }
    }
    None
}

fn parse_int_f(s: &str, defaut: i64) -> i64 {
    s.parse::<f64>().map(|f| f as i64).unwrap_or(defaut)
}

pub fn run_publier(args: &[String]) -> i32 {
    let Some(cmd) = args.first().map(|s| s.as_str()) else {
        println!("Usage: hermes-publier <debut|fin|etat|cron|jetons|battement|lire> ...");
        return 0;
    };
    let rest = &args[1..];
    let lock_target = qs_runtime_dir().join("hermes");

    let (msg, code): (String, i32) = match cmd {
        "debut" => {
            if rest.is_empty() {
                ("debut : il manque le libellé de la tâche".into(), 2)
            } else {
                let _lock = FileLock::acquire(&lock_target);
                let mut d = lire_etat_brut();
                let label = rest.join(" ");
                d.insert("etat".into(), json!("en_cours"));
                d.insert("tache".into(), json!(label));
                d.insert("depuis".into(), json!(now_utc_iso()));
                ecrire_etat(d);
                (format!("tâche publiée : {}", label), 0)
            }
        }
        "fin" => {
            let res = rest.first().map(|s| s.as_str()).unwrap_or("");
            if !matches!(res, "ok" | "echec") {
                ("fin : attendu « ok » ou « echec »".into(), 2)
            } else {
                let duree = arg_val(rest, "--duree")
                    .map(|s| parse_int_f(s, 0))
                    .unwrap_or(0);
                let modele = arg_val(rest, "--modele").unwrap_or("—");
                let motif = arg_val(rest, "--motif").unwrap_or("");
                let tache_next = arg_val(rest, "--tache").unwrap_or("");
                let _lock = FileLock::acquire(&lock_target);
                let mut d = lire_etat_brut();
                let mut execs = d
                    .get("executions")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default();
                let nom = d
                    .get("tache")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("tâche")
                    .to_string();
                let debut = d
                    .get("depuis")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .unwrap_or_else(now_utc_iso);
                execs.insert(
                    0,
                    json!({
                        "nom": nom,
                        "debut": debut,
                        "duree_s": duree,
                        "resultat": res,
                        "modele": modele,
                        "motif": motif,
                    }),
                );
                execs.truncate(MAX_EXECUTIONS);
                d.insert("executions".into(), Value::Array(execs));
                d.insert(
                    "etat".into(),
                    json!(if res == "echec" { "erreur" } else { "repos" }),
                );
                d.insert("tache".into(), json!(tache_next));
                d.remove("depuis");
                ecrire_etat(d);
                (format!("tâche terminée : {}", res), 0)
            }
        }
        "etat" => {
            let st = rest.first().map(|s| s.as_str()).unwrap_or("");
            if !matches!(st, "repos" | "en_cours" | "attente" | "erreur") {
                ("etat : attendu parmi repos, en_cours, attente, erreur".into(), 2)
            } else {
                let _lock = FileLock::acquire(&lock_target);
                let mut d = lire_etat_brut();
                if d.get("etat").and_then(|v| v.as_str()) != Some(st) {
                    d.insert("depuis".into(), json!(now_utc_iso()));
                }
                d.insert("etat".into(), json!(st));
                if let Some(t) = arg_val(rest, "--tache") {
                    d.insert("tache".into(), json!(t));
                }
                if let Some(f) = arg_val(rest, "--file") {
                    d.insert("file".into(), json!(parse_int_f(f, 0)));
                }
                ecrire_etat(d);
                (format!("état publié : {}", st), 0)
            }
        }
        "cron" => {
            if rest.is_empty() {
                ("cron : il manque le nom de la tâche".into(), 2)
            } else {
                let nom = &rest[0];
                let _lock = FileLock::acquire(&lock_target);
                let mut d = lire_etat_brut();
                let mut entrees: Vec<Value> = d
                    .get("cron")
                    .and_then(|v| v.as_array())
                    .cloned()
                    .unwrap_or_default()
                    .into_iter()
                    .filter(|c| c.get("nom").and_then(|v| v.as_str()) != Some(nom.as_str()))
                    .collect();
                let quand = arg_val(rest, "--quand")
                    .map(|s| s.to_string())
                    .unwrap_or_else(now_utc_iso);
                entrees.insert(
                    0,
                    json!({
                        "nom": nom,
                        "prochaine": arg_val(rest, "--prochain").unwrap_or(""),
                        "dernier": arg_val(rest, "--dernier").unwrap_or("ok"),
                        "quand": quand,
                    }),
                );
                entrees.truncate(MAX_CRON);
                d.insert("cron".into(), Value::Array(entrees));
                ecrire_etat(d);
                (format!("planification publiée : {}", nom), 0)
            }
        }
        "jetons" => {
            let _lock = FileLock::acquire(&lock_target);
            let mut d = lire_etat_brut();
            let mut jetons = d
                .get("jetons")
                .and_then(|v| v.as_object())
                .cloned()
                .unwrap_or_default();
            if let Some(j) = arg_val(rest, "--jour") {
                jetons.insert("jour".into(), json!(parse_int_f(j, 0)));
            }
            if let Some(t) = arg_val(rest, "--tache") {
                jetons.insert("tache".into(), json!(parse_int_f(t, 0)));
            }
            d.insert("jetons".into(), Value::Object(jetons.clone()));
            ecrire_etat(d);
            (format!("jetons : {}", Value::Object(jetons)), 0)
        }
        "battement" => {
            let _lock = FileLock::acquire(&lock_target);
            ecrire_etat(lire_etat_brut());
            ("horodatage rafraîchi".into(), 0)
        }
        "lire" => {
            println!(
                "{}",
                serde_json::to_string_pretty(&Value::Object(lire_etat_brut())).unwrap_or_default()
            );
            (String::new(), 0)
        }
        _ => ("commande inconnue".into(), 2),
    };

    if !msg.is_empty() {
        if code == 0 {
            println!("{}", msg);
        } else {
            eprintln!("{}", msg);
        }
    }
    code
}

// ── hermes_approbations ───────────────────────────────────────────────────────

struct AppState {
    attente: HashMap<String, Value>,
    verdicts: HashMap<String, Value>,
    notifs: HashMap<String, String>,
}

fn publier_approbations(state: &Arc<Mutex<AppState>>) {
    let liste: Vec<Value> = {
        let st = state.lock().unwrap();
        st.attente.values().cloned().collect()
    };
    let _ = write_json_atomic(
        &chemin_approbations(),
        &json!({ "approbations": liste, "ecrit": now_utc_iso() }),
        0o644,
    );
}

fn short_hex_id() -> String {
    let bytes = fs::read("/dev/urandom").unwrap_or_else(|_| vec![1, 2, 3, 4]);
    let mut s = String::new();
    for b in bytes.iter().take(4) {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

fn spawn_toast(state: Arc<Mutex<AppState>>, entree: Value) {
    if !which_exists("notify-send") {
        return;
    }
    thread::spawn(move || {
        let id = entree
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let titre = entree
            .get("titre")
            .and_then(|v| v.as_str())
            .unwrap_or("approbation");
        let detail = entree.get("detail").and_then(|v| v.as_str()).unwrap_or("");
        let Ok(mut child) = Command::new("notify-send")
            .args([
                "-p",
                "--wait",
                "-a",
                "Hermes",
                "-u",
                "normal",
                "-t",
                "120000",
                "--action=accorder=Accorder",
                "--action=refuser=Refuser",
                &format!("Accord demandé : {}", titre),
                &format!("{}\nClique sur la fusée pour le détail.", detail),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
        else {
            return;
        };
        if let Some(stdout) = child.stdout.take() {
            let mut reader = BufReader::new(stdout);
            let mut line1 = String::new();
            if reader.read_line(&mut line1).is_ok() {
                let nid = line1.trim().to_string();
                if !nid.is_empty() && nid.chars().all(|c| c.is_ascii_digit()) {
                    state.lock().unwrap().notifs.insert(id.clone(), nid);
                }
            }
            let mut line2 = String::new();
            if reader.read_line(&mut line2).is_ok() {
                let action = line2.trim();
                if matches!(action, "accorder" | "refuser") {
                    let mut st = state.lock().unwrap();
                    if st.attente.contains_key(&id) {
                        st.verdicts.insert(
                            id.clone(),
                            json!({
                                "id": id,
                                "accord": action == "accorder",
                                "motif": "répondu depuis le toast",
                                "par": "inconnu",
                            }),
                        );
                    }
                }
            }
        }
        let _ = child.wait();
    });
}

fn retirer_toast(state: &Arc<Mutex<AppState>>, ident: &str) {
    let notif = state.lock().unwrap().notifs.remove(ident);
    let Some(nid) = notif else {
        return;
    };
    if which_exists("gdbus") {
        let _ = run_cmd(
            "gdbus",
            &[
                "call",
                "--session",
                "--dest",
                "org.freedesktop.Notifications",
                "--object-path",
                "/org/freedesktop/Notifications",
                "--method",
                "org.freedesktop.Notifications.CloseNotification",
                &nid,
            ],
        );
    }
}

fn traiter_client(stream: UnixStream, state: Arc<Mutex<AppState>>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(30)));
    let Ok(reader_stream) = stream.try_clone() else {
        return;
    };
    let mut reader = BufReader::new(reader_stream);
    let mut writer = stream;
    let mut ligne = String::new();
    if reader.read_line(&mut ligne).unwrap_or(0) == 0 {
        return;
    }
    let _ = writer.set_read_timeout(None);
    let Ok(msg) = serde_json::from_str::<Value>(ligne.trim()) else {
        return;
    };
    let role = msg.get("role").and_then(|v| v.as_str()).unwrap_or("");

    match role {
        "demande" => {
            let ident = short_hex_id();
            let delai = val_f64(msg.get("delai"))
                .filter(|&d| d > 0.0)
                .unwrap_or(DELAI_APPROBATION);
            let titre: String = msg
                .get("titre")
                .and_then(|v| v.as_str())
                .unwrap_or("approbation")
                .chars()
                .take(120)
                .collect();
            let detail: String = msg
                .get("detail")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .chars()
                .take(400)
                .collect();
            let entree = json!({
                "id": ident,
                "titre": titre,
                "detail": detail,
                "depuis": now_utc_iso(),
                "expire_s": delai as i64,
            });
            state
                .lock()
                .unwrap()
                .attente
                .insert(ident.clone(), entree.clone());
            publier_approbations(&state);
            spawn_toast(Arc::clone(&state), entree);

            let start = Instant::now();
            let limit = Duration::from_secs_f64(delai);
            let mut verdict = None;
            while start.elapsed() < limit {
                if let Some(v) = state.lock().unwrap().verdicts.remove(&ident) {
                    verdict = Some(v);
                    break;
                }
                thread::sleep(Duration::from_millis(200));
            }
            let out_verdict = verdict.unwrap_or_else(|| {
                json!({ "id": ident, "accord": false, "motif": "délai dépassé" })
            });
            {
                let mut st = state.lock().unwrap();
                st.attente.remove(&ident);
                st.verdicts.remove(&ident);
            }
            retirer_toast(&state, &ident);
            publier_approbations(&state);
            let _ = writeln!(writer, "{}", out_verdict);
            let _ = writer.flush();
        }
        "verdict" => {
            let ident = msg.get("id").and_then(|v| v.as_str()).unwrap_or("");
            if ident.is_empty() {
                return;
            }
            let mut st = state.lock().unwrap();
            if st.attente.contains_key(ident) {
                let par: String = msg
                    .get("par")
                    .and_then(|v| v.as_str())
                    .unwrap_or("inconnu")
                    .chars()
                    .take(24)
                    .collect();
                st.verdicts.insert(
                    ident.to_string(),
                    json!({
                        "id": ident,
                        "accord": msg.get("accord").and_then(|v| v.as_bool()).unwrap_or(false),
                        "motif": msg.get("motif").and_then(|v| v.as_str()).unwrap_or(""),
                        "par": par,
                    }),
                );
            }
        }
        "liste" => {
            let liste: Vec<Value> = state.lock().unwrap().attente.values().cloned().collect();
            let _ = writeln!(writer, "{}", json!({ "approbations": liste }));
            let _ = writer.flush();
        }
        _ => {}
    }
}

fn envoyer_socket(message: &Value, attendre_reponse: bool) -> Option<Value> {
    let sock = chemin_socket();
    if !sock.exists() {
        return None;
    }
    let mut stream = UnixStream::connect(&sock).ok()?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(600)));
    writeln!(stream, "{}", message).ok()?;
    stream.flush().ok()?;
    if !attendre_reponse {
        return Some(json!({ "envoye": true }));
    }
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    if reader.read_line(&mut line).ok()? == 0 {
        return None;
    }
    serde_json::from_str::<Value>(line.trim()).ok()
}

pub fn run_approbations(args: &[String]) -> i32 {
    let Some(cmd) = args.first().map(|s| s.as_str()) else {
        println!("Usage: hermes-approbations <serveur|demander|repondre|liste> ...");
        return 0;
    };
    let rest = &args[1..];
    match cmd {
        "serveur" => {
            let _ = fs::create_dir_all(qs_runtime_dir());
            let sock = chemin_socket();
            if sock.exists() {
                if UnixStream::connect(&sock).is_ok() {
                    eprintln!("hermes_approbations : une instance écoute déjà sur ce socket");
                    return 1;
                }
                let _ = fs::remove_file(&sock);
            }
            let state = Arc::new(Mutex::new(AppState {
                attente: HashMap::new(),
                verdicts: HashMap::new(),
                notifs: HashMap::new(),
            }));
            publier_approbations(&state);

            let Ok(listener) = UnixListener::bind(&sock) else {
                eprintln!("hermes_approbations : impossible d'ouvrir le socket");
                return 1;
            };
            let _ = fs::set_permissions(&sock, fs::Permissions::from_mode(0o600));
            for conn in listener.incoming().flatten() {
                let st = Arc::clone(&state);
                thread::spawn(move || traiter_client(conn, st));
            }
            let _ = fs::remove_file(&sock);
            let _ = fs::remove_file(chemin_approbations());
            0
        }
        "demander" => {
            if rest.is_empty() {
                eprintln!("demander : il manque le titre");
                return 2;
            }
            let titre = &rest[0];
            let detail = arg_val(rest, "--detail").unwrap_or("");
            let delai: f64 = arg_val(rest, "--delai")
                .and_then(|s| s.parse().ok())
                .unwrap_or(DELAI_APPROBATION);
            let Some(rep) = envoyer_socket(
                &json!({ "role": "demande", "titre": titre, "detail": detail, "delai": delai }),
                true,
            ) else {
                eprintln!("aucun démon d'approbation : refus par défaut");
                return 1;
            };
            println!("{}", rep);
            if rep.get("accord").and_then(|v| v.as_bool()).unwrap_or(false) {
                0
            } else {
                1
            }
        }
        "repondre" => {
            if rest.len() < 2 || !matches!(rest[1].as_str(), "oui" | "non") {
                eprintln!("repondre : attendu <id> oui|non [--par <origine>]");
                return 2;
            }
            let accord = rest[1] == "oui";
            let mut origine = "cli".to_string();
            if let Some(p) = arg_val(rest, "--par") {
                let clean: String = p
                    .to_ascii_lowercase()
                    .chars()
                    .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
                    .take(24)
                    .collect();
                if !clean.is_empty() {
                    origine = clean;
                }
            }
            if envoyer_socket(
                &json!({ "role": "verdict", "id": rest[0], "accord": accord, "par": origine }),
                false,
            )
            .is_none()
            {
                eprintln!("aucun démon d'approbation");
                return 1;
            }
            println!(
                "verdict envoyé : {}",
                if accord { "accordé" } else { "refusé" }
            );
            0
        }
        "liste" => {
            match envoyer_socket(&json!({ "role": "liste" }), true) {
                Some(rep) => println!("{}", rep),
                None => println!("{}", json!({ "approbations": [], "hors_ligne": true })),
            }
            0
        }
        _ => 2,
    }
}
