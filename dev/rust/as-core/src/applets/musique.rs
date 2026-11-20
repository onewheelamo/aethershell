use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{parse_options_arg, run_cmd_stdout};
use serde_json::{json, Map, Value};

const NAVIGATEURS: &[&str] = &[
    "firefox", "zen", "chromium", "chrome", "brave", "vivaldi",
    "opera", "edge", "librewolf", "waterfox",
    "plasma-browser-integration", "browser",
];

fn opt_bool(opts: &Map<String, Value>, key: &str, default: bool) -> bool {
    match opts.get(key) {
        None | Some(Value::Null) => default,
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => !matches!(s.trim().to_ascii_lowercase().as_str(), "false" | "0" | "non" | ""),
        Some(Value::Number(n)) => n.as_i64().unwrap_or(1) != 0,
        _ => default,
    }
}

pub fn run(args: &[String]) -> i32 {
    let opts = parse_options_arg(args);
    let ignorer_nav = opt_bool(&opts, "ignorer_navigateurs", true);

    let raw = run_cmd_stdout(
        "playerctl",
        &["-a", "metadata", "--format", "{{status}}\t{{title}}\t{{artist}}\t{{playerName}}"],
    )
    .unwrap_or_default();

    let mut lignes: Vec<(String, String, String, String)> = Vec::new();
    for line in raw.lines() {
        let cols: Vec<&str> = line.split('\t').collect();
        if cols.len() < 3 { continue; }
        let statut = cols[0].trim().to_string();
        let titre = cols[1].trim().to_string();
        let artiste = cols[2].trim().to_string();
        let lecteur = cols.get(3).map(|s| s.trim()).unwrap_or("").to_string();
        if titre.is_empty() { continue; }
        let low = lecteur.to_ascii_lowercase();
        if ignorer_nav && NAVIGATEURS.iter().any(|n| low.contains(n)) {
            continue;
        }
        lignes.push((statut, titre, artiste, lecteur));
    }

    if lignes.is_empty() {
        let mut m = Map::new();
        m.insert("ok".into(), json!(true));
        m.insert("lecteur".into(), json!(""));
        let presented = presenter(m, "musique", "music", Some(compact("", "", false, 0, None)), None, None, None, None);
        return sortir(&presented);
    }

    let chosen = lignes
        .iter()
        .find(|l| l.0.eq_ignore_ascii_case("playing"))
        .unwrap_or(&lignes[0]);
    let en_pause = !chosen.0.eq_ignore_ascii_case("playing");

    let comp = compact(&chosen.1, &chosen.2, false, 0, None);
    let mut m = Map::new();
    m.insert("ok".into(), json!(true));
    m.insert("en_pause".into(), json!(en_pause));
    m.insert("lecteur".into(), json!(chosen.3));
    m.insert("statut".into(), json!(chosen.0));
    let presented = presenter(m, "musique", "music", Some(comp), None, None, None, None);
    sortir(&presented)
}
