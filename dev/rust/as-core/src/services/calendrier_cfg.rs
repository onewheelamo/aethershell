use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{read_json_value, write_private_json};
use crate::common::paths::core_dir;
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const JOURS: &[&str] = &["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."];
const MOIS: &[&str] = &[
    "janv.", "févr.", "mars", "avr.", "mai", "juin",
    "juil.", "août", "sept.", "oct.", "nov.", "déc.",
];

const CHAMPS: &[&str] = &["url", "user", "app_password"];

fn secrets_path() -> PathBuf {
    core_dir().join("secrets.json")
}

fn lire_nc() -> Map<String, Value> {
    let data = read_json_value(&secrets_path());
    data.get("nextcloud")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default()
}

fn ecrire_nc(nc: Map<String, Value>) {
    let p = secrets_path();
    let mut data = match read_json_value(&p) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    data.insert("nextcloud".into(), Value::Object(nc));
    let _ = write_private_json(&p, &Value::Object(data));
}

pub fn etat() -> Value {
    let nc = lire_nc();
    let url = nc.get("url").and_then(|v| v.as_str()).unwrap_or("");
    let user = nc.get("user").and_then(|v| v.as_str()).unwrap_or("");
    let mdp = nc.get("app_password").and_then(|v| v.as_str()).unwrap_or("");
    let fin: String = if mdp.chars().count() >= 8 {
        let chars: Vec<char> = mdp.chars().collect();
        chars[chars.len() - 4..].iter().collect()
    } else {
        String::new()
    };
    json!({
        "ok": true,
        "url": url,
        "user": user,
        "mot_de_passe_present": !mdp.is_empty(),
        "mot_de_passe_fin": fin,
        "complet": !url.is_empty() && !user.is_empty() && !mdp.is_empty(),
    })
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.trim()).unwrap_or("etat");
    match action {
        "etat" => sortir(&etat()),
        "definir" if args.len() >= 3 => {
            let champ = args[1].trim();
            if !CHAMPS.contains(&champ) {
                sortir(&json!({ "ok": false, "erreur": "champ inconnu" }));
                return 1;
            }
            let mut val = args[2].trim().to_string();
            if champ == "url" {
                val = val.trim_end_matches('/').to_string();
            }
            let mut nc = lire_nc();
            if val.is_empty() {
                nc.remove(champ);
            } else {
                nc.insert(champ.into(), json!(val));
            }
            ecrire_nc(nc);
            sortir(&etat())
        }
        "oublier" if args.len() >= 2 => {
            let mut nc = lire_nc();
            nc.remove(args[1].trim());
            ecrire_nc(nc);
            sortir(&etat())
        }
        _ => {
            sortir(&json!({ "ok": false, "erreur": "usage" }));
            1
        }
    }
}

pub fn run_applet(_args: &[String]) -> i32 {
    let now_dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now_dur.as_secs() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&secs, &mut tm) };
    // tm_wday: 0 = Sun -> 6 = dim., 1..6 = mon..sat -> 0..5
    let wday = if tm.tm_wday == 0 { 6 } else { (tm.tm_wday - 1) as usize };
    let mon = (tm.tm_mon as usize).min(11);
    let mday = tm.tm_mday;
    let valeur = format!("{} {} {}", JOURS[wday], mday, MOIS[mon]);
    let court = format!("{:02}/{:02}", mday, mon + 1);

    let mut comp = compact(&valeur, "", false, 0, None);
    if let Value::Object(ref mut cm) = comp {
        cm.insert("court".into(), json!(court));
    }
    let mut m = Map::new();
    m.insert("ok".into(), json!(true));
    m.insert("ts".into(), json!(now_dur.as_secs_f64()));
    m.insert("date".into(), json!(valeur));
    m.insert("genre".into(), json!(""));
    let out = presenter(m, "calendrier", "calendar", Some(comp), None, None, None, Some("date"));
    sortir(&out)
}
