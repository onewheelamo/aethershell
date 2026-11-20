use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{read_json_value, run_cmd, run_cmd_stdout};
use crate::common::paths::cache_dir;
use serde_json::{json, Map, Value};
use std::io::Write;
use std::process::{Command, Stdio};

const APERCU: usize = 72;

fn entrees(limite: usize) -> Vec<(String, String)> {
    let Some(out) = run_cmd_stdout("cliphist", &["list"]) else {
        return vec![];
    };
    let mut res = Vec::new();
    for line in out.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let Some((ident, text)) = line.split_once('\t') else {
            continue;
        };
        let clean = text.replace('\n', " ").trim().to_string();
        if clean.is_empty() {
            continue;
        }
        res.push((ident.trim().to_string(), clean));
        if limite > 0 && res.len() >= limite {
            break;
        }
    }
    res
}

fn decrire(paires: &[(String, String)]) -> Vec<Value> {
    paires
        .iter()
        .map(|(ident, texte)| {
            let chars: Vec<char> = texte.chars().collect();
            let apercu = if chars.len() > APERCU {
                let mut s: String = chars[..APERCU - 1].iter().collect();
                s.push('…');
                s
            } else {
                texte.clone()
            };
            json!({
                "id": ident,
                "apercu": apercu,
                "longueur": chars.len(),
            })
        })
        .collect()
}

fn copier(ident: &str) -> bool {
    let Some(out) = run_cmd("cliphist", &["decode", ident]) else {
        return false;
    };
    if !out.status.success() {
        return false;
    }
    let Ok(mut child) = Command::new("wl-copy")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    else {
        return false;
    };
    if let Some(mut sin) = child.stdin.take() {
        let _ = sin.write_all(&out.stdout);
    }
    child.wait().map(|s| s.success()).unwrap_or(false)
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.trim()).unwrap_or("");
    if action == "liste" {
        let limite = args.get(1).and_then(|s| s.parse::<usize>().ok()).unwrap_or(40);
        let toutes = entrees(0);
        let page = &toutes[..toutes.len().min(limite)];
        return sortir(&json!({
            "ok": true,
            "total": toutes.len(),
            "entrees": decrire(page),
        }));
    }
    if action == "copier" && args.len() > 1 {
        let ok = copier(&args[1]);
        sortir(&json!({ "ok": ok }));
        return if ok { 0 } else { 1 };
    }
    if action == "vider" {
        let _ = run_cmd("cliphist", &["wipe"]);
        return sortir(&json!({ "ok": true }));
    }

    let toutes = entrees(0);
    let ep_path = cache_dir().join("quickshell").join("presse_epingles.json");
    let epingles = match read_json_value(&ep_path) {
        Value::Object(m) => m.len(),
        _ => 0,
    };
    let valeur = if epingles > 0 {
        format!("{} + {}", toutes.len(), epingles)
    } else {
        toutes.len().to_string()
    };

    let page = &toutes[..toutes.len().min(40)];
    let comp = compact(&valeur, "presse-papiers", false, 0, None);
    let mut m = Map::new();
    m.insert("ok".into(), json!(true));
    m.insert("detail".into(), json!({ "entrees": decrire(page) }));
    let presented = presenter(m, "presse-papiers", "selection", Some(comp), None, None, Some(false), None);
    sortir(&presented)
}
