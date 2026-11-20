use crate::common::io::{read_json_value, run_cmd, run_cmd_stdout};
use crate::common::paths::{cache_dir, core_dir, home_dir, runtime_dir};
use regex::Regex;
use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Map, Value};
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const LIMITE_DEFAUT: usize = 8;
const INDEX_FICHIERS_TTL: f64 = 300.0;
const LIGNES_APERCU: usize = 46;
const COLONNES_APERCU: usize = 104;

struct PrefixDef {
    sym: &'static str,
    kind: &'static str,
    libelle: &'static str,
    exemple: &'static str,
    phrase: &'static str,
}

const PREFIXES: &[PrefixDef] = &[
    PrefixDef {
        sym: ">",
        kind: "commande",
        libelle: "Commande shell",
        exemple: "> nmcli device status",
        phrase: "Le reste de la requête part tel quel dans un shell.",
    },
    PrefixDef {
        sym: "=",
        kind: "calc",
        libelle: "Calcul",
        exemple: "= 15% de 80",
        phrase: "Arithmétique, pourcentages, parenthèses. Entrée copie le résultat.",
    },
    PrefixDef {
        sym: "/",
        kind: "fichiers",
        libelle: "Fichiers",
        exemple: "/ rapport",
        phrase: "Cherche un nom de fichier sous ~ (respecte les .gitignore).",
    },
    PrefixDef {
        sym: ":",
        kind: "contenu",
        libelle: "Dans les fichiers",
        exemple: ": TODO",
        phrase: "Cherche le texte à l'intérieur des fichiers sous ~.",
    },
    PrefixDef {
        sym: "\"",
        kind: "presse",
        libelle: "Presse-papiers",
        exemple: "\" http",
        phrase: "Historique cliphist. Entrée copie l'entrée.",
    },
    PrefixDef {
        sym: ";",
        kind: "emoji",
        libelle: "Émoji",
        exemple: "; coeur",
        phrase: "Cherche un émoji par nom ou mot-clé. Entrée le copie.",
    },
    PrefixDef {
        sym: "~",
        kind: "unites",
        libelle: "Unités",
        exemple: "~ 12 km en mi",
        phrase: "Longueurs, masses, températures, volumes, durées, données.",
    },
    PrefixDef {
        sym: "$",
        kind: "devises",
        libelle: "Devises",
        exemple: "$ 100 usd en eur",
        phrase: "Taux du jour (BCE), mis en cache 24 h.",
    },
    PrefixDef {
        sym: "%",
        kind: "processus",
        libelle: "Processus",
        exemple: "% firefox",
        phrase: "Triés par CPU. Entrée envoie SIGTERM.",
    },
    PrefixDef {
        sym: "*",
        kind: "signets",
        libelle: "Signets",
        exemple: "* doc python",
        phrase: "Signets de Firefox (profil le plus récent).",
    },
    PrefixDef {
        sym: "?",
        kind: "aide",
        libelle: "Aide",
        exemple: "?",
        phrase: "Cette liste, directement dans le launcher.",
    },
];

fn now_f64() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn which_path(prog: &str) -> Option<String> {
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            let p = dir.join(prog);
            if p.is_file() {
                return Some(p.to_string_lossy().to_string());
            }
        }
    }
    None
}

fn qs_cache_dir() -> PathBuf {
    cache_dir().join("quickshell")
}

fn presse_cache_dir() -> PathBuf {
    runtime_dir().join("quickshell").join("vignettes")
}

fn presse_epingles_file() -> PathBuf {
    qs_cache_dir().join("presse_epingles.json")
}

fn resultat(
    kind: &str,
    name: &str,
    detail: &str,
    icon: &str,
    tag: &str,
    action: Option<&str>,
    arg: Option<&str>,
) -> Value {
    let mut m = Map::new();
    m.insert("kind".into(), json!(kind));
    m.insert("name".into(), json!(name));
    m.insert("detail".into(), json!(detail));
    m.insert("icon".into(), json!(icon));
    m.insert("tag".into(), json!(tag));
    if let Some(a) = action {
        m.insert("action".into(), json!(a));
        m.insert("arg".into(), json!(arg.unwrap_or("")));
    }
    Value::Object(m)
}

fn nombre_fr(x: f64) -> String {
    let is_int = (x - x.round()).abs() < 1e-12 && x.abs() < 1e15;
    let formatted = if is_int {
        format!("{}", x.round() as i64)
    } else {
        let s = format!("{:.6}", x);
        let s = s.trim_end_matches('0').trim_end_matches('.');
        s.to_string()
    };
    let (neg, rest) = if let Some(r) = formatted.strip_prefix('-') {
        ("-", r)
    } else {
        ("", formatted.as_str())
    };
    let (int_p, dec_p) = match rest.split_once('.') {
        Some((i, d)) => (i, Some(d)),
        None => (rest, None),
    };
    let mut grouped = String::new();
    for (idx, ch) in int_p.chars().rev().enumerate() {
        if idx > 0 && idx % 3 == 0 {
            grouped.push('\u{202f}');
        }
        grouped.push(ch);
    }
    let int_out: String = grouped.chars().rev().collect();
    match dec_p {
        Some(d) => format!("{}{},{}", neg, int_out, d),
        None => format!("{}{}", neg, int_out),
    }
}

fn score_str(q_in: &str, texte_in: &str) -> f64 {
    let q: Vec<char> = q_in.to_lowercase().chars().collect();
    let t_str = texte_in.to_lowercase();
    if q.is_empty() {
        return 0.0;
    }
    if let Some(idx) = t_str.find(&q_in.to_lowercase()) {
        return 100.0 - (idx as f64) - (t_str.len() as f64) / 100.0;
    }
    let t: Vec<char> = t_str.chars().collect();
    let mut j = 0usize;
    let mut points = 0i32;
    let mut dernier: isize = -2;
    for (i, &c) in t.iter().enumerate() {
        if j < q.len() && c == q[j] {
            points += 1;
            if i as isize == dernier + 1 {
                points += 1;
            }
            if i == 0 || matches!(t[i - 1], ' ' | '-' | '_' | '/' | '.') {
                points += 2;
            }
            dernier = i as isize;
            j += 1;
        }
    }
    if j == q.len() {
        points as f64
    } else {
        0.0
    }
}

// ── calcul ────────────────────────────────────────────────────────────────────

struct ExprParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> ExprParser<'a> {
    fn parse_expr(&mut self) -> Result<f64, ()> {
        let mut val = self.parse_term()?;
        while self.pos < self.bytes.len() {
            match self.bytes[self.pos] {
                b'+' => {
                    self.pos += 1;
                    val += self.parse_term()?;
                }
                b'-' => {
                    self.pos += 1;
                    val -= self.parse_term()?;
                }
                _ => break,
            }
        }
        Ok(val)
    }

    fn parse_term(&mut self) -> Result<f64, ()> {
        let mut val = self.parse_pow()?;
        while self.pos < self.bytes.len() {
            if self.bytes[self.pos..].starts_with(b"//") {
                self.pos += 2;
                let rhs = self.parse_pow()?;
                if rhs == 0.0 {
                    return Err(());
                }
                val = (val / rhs).floor();
            } else if self.bytes[self.pos..].starts_with(b"**") {
                break;
            } else {
                match self.bytes[self.pos] {
                    b'*' => {
                        self.pos += 1;
                        val *= self.parse_pow()?;
                    }
                    b'/' => {
                        self.pos += 1;
                        let rhs = self.parse_pow()?;
                        if rhs == 0.0 {
                            return Err(());
                        }
                        val /= rhs;
                    }
                    b'%' => {
                        self.pos += 1;
                        let rhs = self.parse_pow()?;
                        if rhs == 0.0 {
                            return Err(());
                        }
                        val %= rhs;
                    }
                    _ => break,
                }
            }
        }
        Ok(val)
    }

    fn parse_pow(&mut self) -> Result<f64, ()> {
        let base = self.parse_unary()?;
        if self.bytes[self.pos..].starts_with(b"**") {
            self.pos += 2;
            let exp = self.parse_pow()?;
            if exp.abs() > 256.0 {
                return Err(());
            }
            return Ok(base.powf(exp));
        }
        Ok(base)
    }

    fn parse_unary(&mut self) -> Result<f64, ()> {
        if self.pos < self.bytes.len() {
            match self.bytes[self.pos] {
                b'+' => {
                    self.pos += 1;
                    return self.parse_unary();
                }
                b'-' => {
                    self.pos += 1;
                    return Ok(-self.parse_unary()?);
                }
                _ => {}
            }
        }
        self.parse_primary()
    }

    fn parse_primary(&mut self) -> Result<f64, ()> {
        if self.pos < self.bytes.len() && self.bytes[self.pos] == b'(' {
            self.pos += 1;
            let val = self.parse_expr()?;
            if self.pos >= self.bytes.len() || self.bytes[self.pos] != b')' {
                return Err(());
            }
            self.pos += 1;
            return Ok(val);
        }
        let start = self.pos;
        let mut saw_dot = false;
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            if b.is_ascii_digit() {
                self.pos += 1;
            } else if b == b'.' && !saw_dot {
                saw_dot = true;
                self.pos += 1;
            } else {
                break;
            }
        }
        if self.pos == start {
            return Err(());
        }
        std::str::from_utf8(&self.bytes[start..self.pos])
            .ok()
            .and_then(|s| s.parse::<f64>().ok())
            .ok_or(())
    }
}

fn calcul(texte: &str) -> Vec<Value> {
    let mut brut = texte.trim().trim_start_matches('=').trim().to_string();
    if brut.is_empty() {
        return vec![];
    }
    let pct_re = Regex::new(r"^([\d.,\s+\-*/()]+?)\s*%\s*(?:de|of)\s*([\d.,\s+\-*/()]+)$").unwrap();
    if let Some(cap) = pct_re.captures(&brut) {
        brut = format!("({})*({})/100", &cap[1], &cap[2]);
    }
    let expr = brut
        .replace(',', ".")
        .replace('×', "*")
        .replace('÷', "/")
        .replace('^', "**")
        .replace('x', "*")
        .replace(' ', "");
    let valid_re = Regex::new(r"^[0-9.+\-*/%()]*$").unwrap();
    if expr.is_empty() || !valid_re.is_match(&expr) {
        return vec![];
    }
    let mut parser = ExprParser {
        bytes: expr.as_bytes(),
        pos: 0,
    };
    let Ok(val) = parser.parse_expr() else {
        return vec![];
    };
    if parser.pos != parser.bytes.len() || val.is_nan() || val.is_infinite() {
        return vec![];
    }
    let tv = nombre_fr(val);
    let detail = brut.replace('*', " × ").replace('/', " ÷ ");
    vec![resultat(
        "calc",
        &tv,
        &detail,
        "",
        "calcul",
        Some("copy"),
        Some(&tv),
    )]
}

// ── unités ────────────────────────────────────────────────────────────────────

fn unite_info(u: &str) -> Option<(&'static str, f64)> {
    match u {
        "mm" => Some(("long", 0.001)),
        "cm" => Some(("long", 0.01)),
        "m" => Some(("long", 1.0)),
        "km" => Some(("long", 1000.0)),
        "in" => Some(("long", 0.0254)),
        "ft" => Some(("long", 0.3048)),
        "yd" => Some(("long", 0.9144)),
        "mi" => Some(("long", 1609.344)),
        "nm" => Some(("long", 1852.0)),
        "mg" => Some(("masse", 1e-6)),
        "g" => Some(("masse", 0.001)),
        "kg" => Some(("masse", 1.0)),
        "t" => Some(("masse", 1000.0)),
        "oz" => Some(("masse", 0.0283495)),
        "lb" => Some(("masse", 0.453592)),
        "ml" => Some(("vol", 0.001)),
        "cl" => Some(("vol", 0.01)),
        "l" => Some(("vol", 1.0)),
        "gal" => Some(("vol", 3.785412)),
        "pinte" => Some(("vol", 0.473176)),
        "s" => Some(("temps", 1.0)),
        "min" => Some(("temps", 60.0)),
        "h" => Some(("temps", 3600.0)),
        "jour" => Some(("temps", 86400.0)),
        "semaine" => Some(("temps", 604800.0)),
        "ko" => Some(("donnees", 1e3)),
        "mo" => Some(("donnees", 1e6)),
        "go" => Some(("donnees", 1e9)),
        "to" => Some(("donnees", 1e12)),
        "kio" => Some(("donnees", 1024.0)),
        "mio" => Some(("donnees", 1048576.0)),
        "gio" => Some(("donnees", 1073741824.0)),
        _ => None,
    }
}

fn alias_unite(u: &str) -> &str {
    match u {
        "metre" | "metres" | "mètre" | "mètres" => "m",
        "kilometre" | "kilomètres" | "kilometres" => "km",
        "mile" | "miles" => "mi",
        "pied" | "pieds" => "ft",
        "pouce" | "pouces" => "in",
        "gramme" | "grammes" => "g",
        "kilo" | "kilos" => "kg",
        "livre" | "livres" => "lb",
        "litre" | "litres" => "l",
        "heure" | "heures" => "h",
        "minutes" => "min",
        "secondes" => "s",
        "jours" => "jour",
        "gigaoctet" | "gigaoctets" => "go",
        "megaoctet" | "megaoctets" => "mo",
        other => other,
    }
}

fn temp_code(u: &str) -> Option<&'static str> {
    match u {
        "c" | "°c" | "celsius" => Some("c"),
        "f" | "°f" | "fahrenheit" => Some("f"),
        "k" | "kelvin" => Some("k"),
        _ => None,
    }
}

fn unites(texte: &str) -> Vec<Value> {
    let t = texte.trim().trim_start_matches('~').trim().to_ascii_lowercase();
    let re = Regex::new(r"^(-?[\d.,]+)\s*([a-zé°]+)\s*(?:en|->|>|vers)\s*([a-zé°]+)$").unwrap();
    let Some(cap) = re.captures(&t) else {
        return vec![];
    };
    let Ok(valeur) = cap[1].replace(',', ".").parse::<f64>() else {
        return vec![];
    };
    let de = alias_unite(cap[2].trim());
    let vers = alias_unite(cap[3].trim());

    let (sortie, unite) = if let (Some(td), Some(tv)) = (temp_code(de), temp_code(vers)) {
        let celsius = match td {
            "c" => valeur,
            "f" => (valeur - 32.0) * 5.0 / 9.0,
            _ => valeur - 273.15,
        };
        let out = match tv {
            "c" => celsius,
            "f" => celsius * 9.0 / 5.0 + 32.0,
            _ => celsius + 273.15,
        };
        let u = match tv {
            "c" => "°C",
            "f" => "°F",
            _ => "K",
        };
        (out, u)
    } else {
        let (Some((fam1, fac1)), Some((fam2, fac2))) = (unite_info(de), unite_info(vers)) else {
            return vec![];
        };
        if fam1 != fam2 {
            return vec![];
        }
        let s = ((valeur * fac1 / fac2) * 10000.0).round() / 10000.0;
        (s, vers)
    };
    let ts = format!("{} {}", nombre_fr(sortie), unite);
    vec![resultat(
        "unite",
        &ts,
        &format!("{} {}", nombre_fr(valeur), de),
        "",
        "unité",
        Some("copy"),
        Some(&ts),
    )]
}

// ── devises ───────────────────────────────────────────────────────────────────

fn sigle_devise(s: &str) -> String {
    match s {
        "€" | "eur" => "EUR".to_string(),
        "$" | "usd" => "USD".to_string(),
        "£" | "gbp" => "GBP".to_string(),
        "¥" | "jpy" => "JPY".to_string(),
        "chf" => "CHF".to_string(),
        "cad" => "CAD".to_string(),
        "aud" => "AUD".to_string(),
        "sek" => "SEK".to_string(),
        "nok" => "NOK".to_string(),
        "pln" => "PLN".to_string(),
        "cny" => "CNY".to_string(),
        other => other.to_ascii_uppercase(),
    }
}

fn taux_devises() -> Option<(Map<String, Value>, String, bool)> {
    let fichier = qs_cache_dir().join("devises.json");
    if fichier.exists() {
        if let Ok(meta) = fichier.metadata() {
            if let Ok(mtime) = meta.modified() {
                if let Ok(age) = SystemTime::now().duration_since(mtime) {
                    if age.as_secs() < 86400 {
                        let d = read_json_value(&fichier);
                        if let Some(rates) = d.get("rates").and_then(|v| v.as_object()) {
                            let date = d
                                .get("date")
                                .and_then(|v| v.as_str())
                                .unwrap_or("")
                                .to_string();
                            return Some((rates.clone(), date, true));
                        }
                    }
                }
            }
        }
    }

    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(5))
        .build();
    if let Ok(resp) = agent.get("https://api.frankfurter.app/latest?from=EUR").call() {
        if let Ok(d) = resp.into_json::<Value>() {
            if let Some(rates) = d.get("rates").and_then(|v| v.as_object()) {
                let _ = fs::create_dir_all(qs_cache_dir());
                if let Ok(s) = serde_json::to_string(&d) {
                    let _ = fs::write(&fichier, s);
                }
                let date = d
                    .get("date")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                return Some((rates.clone(), date, false));
            }
        }
    }

    if fichier.exists() {
        let d = read_json_value(&fichier);
        if let Some(rates) = d.get("rates").and_then(|v| v.as_object()) {
            let date = d
                .get("date")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            return Some((rates.clone(), date, true));
        }
    }
    None
}

fn devises(texte: &str) -> Vec<Value> {
    let t = texte.trim().trim_start_matches('$').trim().to_ascii_lowercase();
    let re = Regex::new(r"^([\d.,]+)\s*([€$£¥a-z]*)\s*(?:en|->|>|vers)\s*([€$£¥a-z]*)$").unwrap();
    let Some(cap) = re.captures(&t) else {
        return vec![];
    };
    let Ok(valeur) = cap[1].replace(',', ".").parse::<f64>() else {
        return vec![];
    };
    let de_raw = cap[2].trim();
    let de = if de_raw.is_empty() {
        "EUR".to_string()
    } else {
        sigle_devise(de_raw)
    };
    let vers = sigle_devise(cap[3].trim());
    if vers.is_empty() {
        return vec![];
    }

    let Some((taux, date, cache)) = taux_devises() else {
        return vec![resultat(
            "devise",
            "Taux indisponibles",
            "ni cache ni réseau",
            "",
            "devise",
            None,
            None,
        )];
    };

    let facteur = if de == "EUR" {
        1.0
    } else if let Some(r) = taux.get(&de).and_then(|v| v.as_f64()) {
        1.0 / r
    } else {
        return vec![];
    };

    let sortie = if vers == "EUR" {
        valeur * facteur
    } else if let Some(r) = taux.get(&vers).and_then(|v| v.as_f64()) {
        valeur * facteur * r
    } else {
        return vec![];
    };

    let ts = format!("{} {}", nombre_fr((sortie * 100.0).round() / 100.0), vers);
    let detail = format!(
        "{} {} · taux du {}{}",
        nombre_fr(valeur),
        de,
        date,
        if cache { " (cache)" } else { "" }
    );
    vec![resultat(
        "devise",
        &ts,
        &detail,
        "",
        "devise",
        Some("copy"),
        Some(&ts),
    )]
}

// ── fichiers et contenu ───────────────────────────────────────────────────────

fn lister_fichiers_cache(rg: &str) -> Vec<String> {
    let index = qs_cache_dir().join("fichiers_index.txt");
    if index.exists() {
        if let Ok(meta) = index.metadata() {
            if let Ok(mtime) = meta.modified() {
                if let Ok(age) = SystemTime::now().duration_since(mtime) {
                    if age.as_secs_f64() < INDEX_FICHIERS_TTL {
                        if let Ok(txt) = fs::read_to_string(&index) {
                            return txt.lines().map(|l| l.to_string()).collect();
                        }
                    }
                }
            }
        }
    }
    let home_s = home_dir().to_string_lossy().to_string();
    let sortie = run_cmd_stdout(rg, &["--files", &home_s]).unwrap_or_default();
    if !sortie.is_empty() {
        let _ = fs::create_dir_all(qs_cache_dir());
        let tmp = qs_cache_dir().join(format!("fichiers_index.{}.tmp", std::process::id()));
        if fs::write(&tmp, &sortie).is_ok() {
            let _ = fs::rename(&tmp, &index);
        }
    }
    sortie.lines().map(|l| l.to_string()).collect()
}

fn fichiers(texte: &str, limite: usize) -> Vec<Value> {
    let q = texte.trim().trim_start_matches('/').trim();
    if q.is_empty() {
        return vec![];
    }
    let Some(rg) = which_path("rg") else {
        return vec![resultat(
            "fichier",
            "ripgrep absent",
            "pacman -S ripgrep",
            "",
            "fichier",
            None,
            None,
        )];
    };
    let home_s = home_dir().to_string_lossy().to_string();
    let home_prefix = format!("{}/", home_s);
    let mut tries: Vec<(f64, usize, String, String)> = Vec::new();

    for chemin in lister_fichiers_cache(&rg) {
        if chemin.is_empty() {
            continue;
        }
        let nom = Path::new(&chemin)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        let tige = Path::new(&nom)
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(&nom);
        let rel = chemin.strip_prefix(&home_s).unwrap_or(&chemin);
        let s = score_str(q, tige).max(score_str(q, rel) - 20.0);
        if s > 0.0 {
            let depth = chemin.matches('/').count();
            tries.push((s, depth, chemin, nom));
        }
    }
    tries.sort_by(|a, b| {
        b.0.partial_cmp(&a.0)
            .unwrap_or(Ordering::Equal)
            .then_with(|| a.1.cmp(&b.1))
            .then_with(|| a.2.cmp(&b.2))
    });
    tries.truncate(limite);
    tries
        .into_iter()
        .map(|(_, _, chemin, nom)| {
            let disp = chemin.replace(&home_prefix, "~/");
            resultat("fichier", &nom, &disp, "", "fichier", Some("open"), Some(&chemin))
        })
        .collect()
}

fn shlex_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}

fn contenu(texte: &str, limite: usize) -> (Vec<Value>, bool) {
    let q = texte.trim().trim_start_matches(':').trim();
    if q.chars().count() < 2 {
        return (vec![], false);
    }
    let Some(rg) = which_path("rg") else {
        return (vec![], false);
    };

    let globs_exclus = [
        "!**/site-packages/**",
        "!**/dist-info/**",
        "!**/node_modules/**",
        "!**/.git/**",
        "!**/__pycache__/**",
        "!**/.cache/**",
        "!**/.venv/**",
        "!**/venv/**",
        "!**/.cargo/**",
        "!**/.rustup/**",
        "!**/wordlists/**",
        "!*.lock",
        "!pnpm-lock.yaml",
    ];
    let exclus_str: String = globs_exclus
        .iter()
        .map(|g| format!("-g {}", shlex_quote(g)))
        .collect::<Vec<_>>()
        .join(" ");
    let home_s = home_dir().to_string_lossy().to_string();
    let base = format!(
        "{} -n --no-heading --max-count 1 -i -F {} {}",
        shlex_quote(&rg),
        shlex_quote(q),
        exclus_str
    );

    let pre_py = core_dir().join("texte_doc.py");
    let commande = if pre_py.is_file() {
        let doc_globs = "-g '*.pdf' -g '*.docx' -g '*.odt' -g '*.odp'";
        let pre_opt = format!(
            "--pre {} --pre-glob '*.pdf' --pre-glob '*.docx' --pre-glob '*.odt' --pre-glob '*.odp'",
            shlex_quote(&pre_py.to_string_lossy())
        );
        format!(
            "{{ {} {} {} {} 2>/dev/null | head -c 300000 ; echo '' ; {} -g '!*.pdf' -g '!*.docx' -g '!*.odt' -g '!*.odp' {} 2>/dev/null | head -c 300000 ; }}",
            base, doc_globs, pre_opt, shlex_quote(&home_s), base, shlex_quote(&home_s)
        )
    } else {
        format!(
            "{} -g '!*.pdf' -g '!*.docx' -g '!*.odt' -g '!*.odp' {} 2>/dev/null | head -c 300000",
            base,
            shlex_quote(&home_s)
        )
    };

    let sortie = run_cmd_stdout("sh", &["-c", &commande]).unwrap_or_default();
    let exclus_re = Regex::new(
        r"/(site-packages|dist-info|node_modules|\.git|__pycache__|\.cache|\.venv|venv|\.local/share|\.cargo|\.rustup|build|target|wordlists?|\.[a-z]*-cache)/",
    )
    .unwrap();

    let mut trouves: HashMap<String, (String, String)> = HashMap::new();
    for ligne in sortie.lines() {
        let parts: Vec<&str> = ligne.splitn(3, ':').collect();
        if parts.len() < 3 {
            continue;
        }
        let (chemin, num, extrait) = (parts[0], parts[1], parts[2]);
        if trouves.contains_key(chemin) || exclus_re.is_match(chemin) {
            continue;
        }
        trouves.insert(chemin.to_string(), (num.to_string(), extrait.to_string()));
    }

    let mut items: Vec<(usize, usize, String, String, String)> = trouves
        .into_iter()
        .map(|(chemin, (num, extrait))| {
            let ext = Path::new(&chemin)
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| format!(".{}", s.to_ascii_lowercase()))
                .unwrap_or_default();
            let is_doc = matches!(
                ext.as_str(),
                ".pdf" | ".docx" | ".odt" | ".odp" | ".xlsx" | ".pptx" | ".doc"
            );
            (
                if is_doc { 0 } else { 1 },
                chemin.matches('/').count(),
                chemin,
                num,
                extrait,
            )
        })
        .collect();
    items.sort_by(|a, b| (a.0, a.1, &a.2).cmp(&(b.0, b.1, &b.2)));
    items.truncate(limite);

    let home_prefix = format!("{}/", home_s);
    let out = items
        .into_iter()
        .map(|(_, _, chemin, num, extrait)| {
            let ext = Path::new(&chemin)
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| format!(".{}", s.to_ascii_lowercase()))
                .unwrap_or_default();
            let etiquette = match ext.as_str() {
                ".pdf" => "pdf",
                ".docx" => "docx",
                ".odt" => "odt",
                ".odp" => "odp",
                ".xlsx" => "xlsx",
                ".pptx" => "pptx",
                ".doc" => "doc",
                _ => "ligne",
            };
            let court = chemin.replace(&home_prefix, "~/");
            let empl = if etiquette != "ligne" {
                court
            } else {
                format!("{}:{}", court, num)
            };
            let ext_short: String = extrait.trim().chars().take(90).collect();
            let nom = Path::new(&chemin)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("");
            resultat(
                "contenu",
                nom,
                &format!("{} · {}", empl, ext_short),
                "",
                etiquette,
                Some("open"),
                Some(&chemin),
            )
        })
        .collect();

    (out, false)
}

// ── presse-papiers ────────────────────────────────────────────────────────────

fn octets_cmd(prog: &str, args: &[&str], max_bytes: usize) -> Vec<u8> {
    let Ok(out) = Command::new(prog).args(args).output() else {
        return vec![];
    };
    if out.stdout.len() > max_bytes {
        out.stdout[..max_bytes].to_vec()
    } else {
        out.stdout
    }
}

fn type_entree(ident: &str) -> &'static str {
    let tete = octets_cmd("cliphist", &["decode", ident], 16);
    if tete.is_empty() {
        return "vide";
    }
    if tete.starts_with(b"\x89PNG")
        || tete.starts_with(b"\xff\xd8")
        || tete.starts_with(b"GIF8")
        || tete.starts_with(b"RIFF")
    {
        return "image";
    }
    if tete.contains(&0) {
        return "binaire";
    }
    let Ok(texte) = std::str::from_utf8(&tete) else {
        return "binaire";
    };
    if texte.starts_with("http://") || texte.starts_with("https://") {
        "lien"
    } else {
        "texte"
    }
}

fn vignette(ident: &str) -> String {
    let dir = presse_cache_dir();
    let _ = fs::create_dir_all(&dir);
    let chemin = dir.join(format!("{}.png", ident));
    if chemin.exists() && chemin.metadata().map(|m| m.len() > 0).unwrap_or(false) {
        return chemin.to_string_lossy().to_string();
    }
    let brut = octets_cmd("cliphist", &["decode", ident], 4_000_000);
    if brut.is_empty() {
        return String::new();
    }
    let out_arg = format!("png:{}", chemin.display());
    if let Ok(mut child) = Command::new("magick")
        .args(["-", "-thumbnail", "96x96", &out_arg])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(&brut);
        }
        if let Ok(st) = child.wait() {
            if st.success() && chemin.exists() {
                return chemin.to_string_lossy().to_string();
            }
        }
    }
    String::new()
}

fn uri_image(texte: &str) -> Option<String> {
    let trimmed = texte.trim();
    if trimmed.is_empty() {
        return None;
    }
    let lines: Vec<&str> = trimmed.lines().collect();
    let premiere = lines.first()?.trim();
    let chemin = if let Some(rest) = premiere.strip_prefix("file://") {
        rest
    } else if premiere.starts_with("x-special/gnome-copied-files") {
        lines.get(1)?.strip_prefix("file://")?
    } else if premiere.starts_with("x-special/nautilus-clipboard") {
        lines.get(2)?.strip_prefix("file://")?
    } else if premiere.starts_with('/') {
        premiere
    } else {
        return None;
    };
    let c = chemin.trim();
    let low = c.to_ascii_lowercase();
    if !(low.ends_with(".png")
        || low.ends_with(".jpg")
        || low.ends_with(".jpeg")
        || low.ends_with(".webp")
        || low.ends_with(".gif")
        || low.ends_with(".bmp"))
    {
        return None;
    }
    if Path::new(c).is_file() {
        Some(c.to_string())
    } else {
        None
    }
}

fn vignette_fichier(chemin: &str, ident: &str) -> String {
    let dir = presse_cache_dir();
    let _ = fs::create_dir_all(&dir);
    let cible = dir.join(format!("f{}.png", ident));
    if cible.exists() && cible.metadata().map(|m| m.len() > 0).unwrap_or(false) {
        return cible.to_string_lossy().to_string();
    }
    let out_arg = format!("png:{}", cible.display());
    if run_cmd("magick", &[chemin, "-thumbnail", "96x96", &out_arg])
        .map(|o| o.status.success())
        .unwrap_or(false)
        && cible.exists()
    {
        return cible.to_string_lossy().to_string();
    }
    String::new()
}

fn load_epingles() -> Map<String, Value> {
    read_json_value(&presse_epingles_file())
        .as_object()
        .cloned()
        .unwrap_or_default()
}

fn save_epingles(d: &Map<String, Value>) {
    let p = presse_epingles_file();
    if let Some(par) = p.parent() {
        let _ = fs::create_dir_all(par);
    }
    if let Ok(s) = serde_json::to_string_pretty(&Value::Object(d.clone())) {
        let _ = fs::write(p, s);
    }
}

fn presse_epingler(ident: &str, texte: &str) -> String {
    if ident.is_empty() {
        return "identifiant manquant".to_string();
    }
    let brut = octets_cmd("cliphist", &["decode", ident], 4_000_000);
    if brut.is_empty() {
        return "contenu illisible".to_string();
    }
    let mut d = load_epingles();
    let ep_dir = qs_cache_dir().join("epingles");
    let _ = fs::create_dir_all(&ep_dir);
    let orig_path = ep_dir.join(format!("{}.bin", ident));
    let _ = fs::write(&orig_path, &brut);
    let vign = presse_cache_dir().join(format!("{}.png", ident));
    let quand = unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::gmtime_r(&now, &mut tm);
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    };
    let short_txt: String = texte.chars().take(200).collect();
    d.insert(
        ident.to_string(),
        json!({
            "texte": short_txt,
            "type": type_entree(ident),
            "vignette": if vign.exists() { vign.to_string_lossy().to_string() } else { String::new() },
            "original": if orig_path.exists() { orig_path.to_string_lossy().to_string() } else { String::new() },
            "quand": quand,
        }),
    );
    save_epingles(&d);
    format!("épinglé : {}", ident)
}

fn presse_desepingler(ident: &str) -> String {
    let mut d = load_epingles();
    if d.remove(ident).is_some() {
        save_epingles(&d);
        format!("désépinglé : {}", ident)
    } else {
        "cette entrée n'était pas épinglée".to_string()
    }
}

fn presse_supprimer(ident: &str) -> String {
    if ident.is_empty() {
        return "identifiant manquant".to_string();
    }
    let list_out = run_cmd_stdout("cliphist", &["list"]).unwrap_or_default();
    if !list_out
        .lines()
        .any(|l| l.split('\t').next() == Some(ident))
    {
        return format!("entrée {} introuvable", ident);
    }
    let ok = Command::new("cliphist")
        .arg("delete")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .and_then(|mut c| {
            if let Some(mut sin) = c.stdin.take() {
                let _ = writeln!(sin, "{}\t", ident);
            }
            c.wait()
        })
        .map(|s| s.success())
        .unwrap_or(false);

    let mut d = load_epingles();
    if d.remove(ident).is_some() {
        save_epingles(&d);
        let _ = fs::remove_file(presse_cache_dir().join(format!("{}.png", ident)));
        let _ = fs::remove_file(qs_cache_dir().join("epingles").join(format!("{}.bin", ident)));
    }
    if ok {
        format!("entrée {} supprimée", ident)
    } else {
        "suppression refusée".to_string()
    }
}

fn presse_vider() -> String {
    let ok = run_cmd("cliphist", &["wipe"])
        .map(|o| o.status.success())
        .unwrap_or(false);
    save_epingles(&Map::new());
    if let Ok(rd) = fs::read_dir(presse_cache_dir()) {
        for ent in rd.flatten() {
            let p = ent.path();
            if p.extension().and_then(|s| s.to_str()) == Some("png") {
                let _ = fs::remove_file(p);
            }
        }
    }
    if ok {
        "historique vidé".to_string()
    } else {
        "purge refusée".to_string()
    }
}

fn presse(texte: &str, limite: usize) -> Vec<Value> {
    let q = texte.trim().trim_start_matches('"').trim().to_ascii_lowercase();
    let epingles = load_epingles();
    let mut out = Vec::new();

    for (ident, infos) in &epingles {
        let libelle = infos
            .get("texte")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .unwrap_or_else(|| format!("entrée {}", ident));
        if !q.is_empty() && !libelle.to_ascii_lowercase().contains(&q) {
            continue;
        }
        let typ = infos.get("type").and_then(|v| v.as_str()).unwrap_or("");
        let (action, cible) = if typ == "lien" {
            ("open-url", libelle.as_str())
        } else {
            ("copy", ident.as_str())
        };
        let lib_short: String = libelle.chars().take(80).collect();
        let vign = infos.get("vignette").and_then(|v| v.as_str()).unwrap_or("");
        out.push(resultat(
            "presse",
            &lib_short,
            &format!("épinglé · {}", typ),
            vign,
            "presse",
            Some(action),
            Some(cible),
        ));
    }

    let img_re = Regex::new(r"(?i)\b(png|jpeg|jpg|webp|gif)\s+(\d+)x(\d+)").unwrap();
    let list_out = run_cmd_stdout("cliphist", &["list"]).unwrap_or_default();
    for ligne in list_out.lines() {
        let Some((ident, apercu_raw)) = ligne.split_once('\t') else {
            continue;
        };
        if epingles.contains_key(ident) {
            continue;
        }
        let mut apercu = apercu_raw.trim().replace('\n', " ");
        if !q.is_empty() && !apercu.to_ascii_lowercase().contains(&q) {
            continue;
        }
        let mut nature = type_entree(ident);
        let mut vign = if nature == "image" {
            vignette(ident)
        } else {
            String::new()
        };
        if nature == "texte" {
            if let Some(chemin) = uri_image(&apercu) {
                nature = "image (fichier)";
                vign = vignette_fichier(&chemin, ident);
                apercu = Path::new(&chemin)
                    .file_name()
                    .and_then(|s| s.to_str())
                    .unwrap_or(&apercu)
                    .to_string();
            }
        }
        let mut libelle: String = apercu.chars().take(80).collect();
        if libelle.is_empty() {
            libelle = format!("({})", nature);
        }
        if nature == "image" {
            if let Some(cap) = img_re.captures(&apercu) {
                libelle = format!("capture {}×{}", &cap[2], &cap[3]);
            } else {
                libelle = "image copiée".to_string();
            }
        }
        let detail = format!("entrée {} · {}", ident, nature);
        let mut action = "copy";
        let mut cible = ident.to_string();
        if nature == "lien" {
            action = "open-url";
            cible = apercu.split_whitespace().next().unwrap_or("").to_string();
        } else if nature == "texte" {
            let premier = apercu.split_whitespace().next().unwrap_or("");
            if premier.starts_with('/') && Path::new(premier).exists() {
                action = "open-url";
                cible = premier.to_string();
            }
        }
        out.push(resultat(
            "presse",
            &libelle,
            &detail,
            &vign,
            "presse",
            Some(action),
            Some(&cible),
        ));
        if out.len() >= limite {
            break;
        }
    }
    out
}

// ── emoji ─────────────────────────────────────────────────────────────────────

fn fr_en_alias(q: &str) -> Option<&'static str> {
    match q {
        "coeur" | "cœur" | "coeur rouge" => Some("red heart"),
        "amour" => Some("love"),
        "rire" => Some("joy"),
        "sourire" => Some("smile"),
        "clin" => Some("wink"),
        "triste" => Some("sad"),
        "pleure" => Some("cry"),
        "colere" => Some("angry"),
        "fete" => Some("party"),
        "feu" => Some("fire"),
        "eau" => Some("water"),
        "soleil" => Some("sun"),
        "lune" => Some("moon"),
        "etoile" => Some("star"),
        "nuage" => Some("cloud"),
        "pluie" => Some("rain"),
        "neige" => Some("snow"),
        "chat" => Some("cat"),
        "chien" => Some("dog"),
        "souris" => Some("mouse"),
        "oiseau" => Some("bird"),
        "poisson" => Some("fish"),
        "fleur" => Some("flower"),
        "arbre" => Some("tree"),
        "feuille" => Some("leaf"),
        "pomme" => Some("apple"),
        "pain" => Some("bread"),
        "cafe" => Some("coffee"),
        "biere" => Some("beer"),
        "vin" => Some("wine"),
        "pizza" => Some("pizza"),
        "voiture" => Some("car"),
        "velo" => Some("bike"),
        "fusee" => Some("rocket"),
        "avion" => Some("airplane"),
        "maison" => Some("house"),
        "livre" => Some("book"),
        "crayon" => Some("pencil"),
        "musique" => Some("music"),
        "ordinateur" => Some("computer"),
        "telephone" => Some("phone"),
        "horloge" => Some("clock"),
        "cle" => Some("key"),
        "cadeau" => Some("gift"),
        "argent" => Some("money"),
        "outil" => Some("wrench"),
        "coche" => Some("check"),
        "croix" => Some("cross"),
        "attention" => Some("warning"),
        "info" => Some("information"),
        "ok" => Some("ok"),
        "stop" => Some("stop"),
        "fichier" => Some("file"),
        "dossier" => Some("folder"),
        "drapeau" => Some("flag"),
        "pouce" => Some("thumb"),
        _ => None,
    }
}

fn emoji(texte: &str, limite: usize) -> Vec<Value> {
    let q = texte.trim().trim_start_matches(';').trim().to_ascii_lowercase();
    if q.is_empty() {
        return vec![];
    }
    let data = read_json_value(&core_dir().join("emoji.json"));
    let Some(list) = data.as_array() else {
        return vec![];
    };
    let mut variantes = vec![q.as_str()];
    if let Some(en) = fr_en_alias(&q) {
        variantes.push(en);
    }

    let mut tries: Vec<(f64, &Value)> = Vec::new();
    for e in list {
        let nom = e.get("name").and_then(|v| v.as_str()).unwrap_or("");
        let mots: String = e
            .get("keywords")
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .filter_map(|x| x.as_str())
                    .collect::<Vec<_>>()
                    .join(" ")
            })
            .unwrap_or_default();
        let cat = e.get("category").and_then(|v| v.as_str()).unwrap_or("");
        let mut s = 0.0f64;
        for &v in &variantes {
            let mut local = score_str(v, nom)
                .max(score_str(v, &mots) - 10.0)
                .max(score_str(v, cat) - 20.0);
            if local > 0.0 && nom == v {
                local += 60.0;
            } else if local > 0.0 && nom.starts_with(v) {
                local += 20.0;
            }
            if local > s {
                s = local;
            }
        }
        if s > 0.0 {
            tries.push((s - (nom.len() as f64) / 50.0, e));
        }
    }
    tries.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(Ordering::Equal));
    tries.truncate(limite);
    tries
        .into_iter()
        .map(|(_, e)| {
            let em = e.get("emoji").and_then(|v| v.as_str()).unwrap_or("");
            let nom = e.get("name").and_then(|v| v.as_str()).unwrap_or("");
            let cat = e.get("category").and_then(|v| v.as_str()).unwrap_or("");
            resultat(
                "emoji",
                &format!("{}  {}", em, nom),
                cat,
                "",
                "émoji",
                Some("copy"),
                Some(em),
            )
        })
        .collect()
}

// ── processus ─────────────────────────────────────────────────────────────────

fn processus(texte: &str, limite: usize) -> Vec<Value> {
    let q = texte.trim().trim_start_matches('%').trim().to_ascii_lowercase();
    let sortie =
        run_cmd_stdout("ps", &["-eo", "pid,pcpu,pmem,comm,args", "--sort=-pcpu"]).unwrap_or_default();
    let my_pid = std::process::id().to_string();
    let mut out = Vec::new();
    for ligne in sortie.lines().skip(1) {
        let mut it = ligne.split_whitespace();
        let (Some(pid), Some(cpu), Some(mem), Some(comm)) =
            (it.next(), it.next(), it.next(), it.next())
        else {
            continue;
        };
        let rest: String = it.collect::<Vec<_>>().join(" ");
        if comm == "ps" || rest.starts_with("ps -eo") || pid == my_pid {
            continue;
        }
        if !q.is_empty()
            && !comm.to_ascii_lowercase().contains(&q)
            && !rest.to_ascii_lowercase().contains(&q)
        {
            continue;
        }
        let args_short: String = rest.chars().take(70).collect();
        out.push(resultat(
            "processus",
            comm,
            &format!("pid {} · {}% cpu · {}% mem · {}", pid, cpu, mem, args_short),
            "",
            &format!("{}% cpu", cpu),
            Some("kill"),
            Some(pid),
        ));
        if out.len() >= limite {
            break;
        }
    }
    out
}

// ── signets ───────────────────────────────────────────────────────────────────

fn signets(texte: &str, limite: usize) -> Vec<Value> {
    let q = texte.trim().trim_start_matches('*').trim();
    let racine = home_dir().join(".mozilla/firefox");
    let mut cands: Vec<(SystemTime, PathBuf)> = Vec::new();
    if let Ok(rd) = fs::read_dir(&racine) {
        for ent in rd.flatten() {
            let db = ent.path().join("places.sqlite");
            if db.is_file() {
                let mt = db
                    .metadata()
                    .and_then(|m| m.modified())
                    .unwrap_or(UNIX_EPOCH);
                cands.push((mt, db));
            }
        }
    }
    cands.sort_by(|a, b| b.0.cmp(&a.0));
    let Some((_, base)) = cands.first() else {
        return vec![resultat(
            "signet",
            "Aucun profil Firefox",
            "~/.mozilla absent",
            "",
            "signet",
            None,
            None,
        )];
    };

    let uri = format!("file:{}?mode=ro&immutable=1", base.display());
    let Ok(cx) = Connection::open_with_flags(
        &uri,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_URI,
    ) else {
        return vec![];
    };
    let _ = cx.busy_timeout(Duration::from_secs(2));
    let sql = "SELECT b.title, p.url FROM moz_bookmarks b \
               JOIN moz_places p ON p.id = b.fk \
               WHERE b.type = 1 AND p.url NOT LIKE 'place:%' \
               AND (? = '' OR b.title LIKE ? OR p.url LIKE ?) \
               ORDER BY b.dateAdded DESC LIMIT 60";
    let motif = format!("%{}%", q);
    let Ok(mut stmt) = cx.prepare(sql) else {
        return vec![];
    };
    let Ok(rows) = stmt.query_map([q, &motif, &motif], |r| {
        Ok((
            r.get::<_, Option<String>>(0)?.unwrap_or_default(),
            r.get::<_, Option<String>>(1)?.unwrap_or_default(),
        ))
    }) else {
        return vec![];
    };

    let mut tries: Vec<(f64, String, String)> = Vec::new();
    for (titre, url) in rows.flatten() {
        let s = if q.is_empty() {
            1.0
        } else {
            score_str(q, &titre).max(score_str(q, &url) - 10.0)
        };
        if s > 0.0 {
            let lbl = if titre.is_empty() { url.clone() } else { titre };
            tries.push((s, lbl, url));
        }
    }
    tries.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(Ordering::Equal));
    tries.truncate(limite);
    tries
        .into_iter()
        .map(|(_, titre, url)| {
            resultat(
                "signet",
                &titre,
                &url,
                "",
                "signet",
                Some("open-url"),
                Some(&url),
            )
        })
        .collect()
}

// ── aide ──────────────────────────────────────────────────────────────────────

fn aide() -> Vec<Value> {
    PREFIXES
        .iter()
        .map(|p| {
            resultat(
                "aide",
                &format!("{}  {}", p.sym, p.libelle),
                p.exemple,
                "",
                "aide",
                Some("prefill"),
                Some(p.exemple),
            )
        })
        .collect()
}

fn phrases_aide() -> Vec<Value> {
    PREFIXES
        .iter()
        .map(|p| {
            json!({
                "symbole": p.sym,
                "kind": p.kind,
                "libelle": p.libelle,
                "exemple": p.exemple,
                "phrase": p.phrase,
            })
        })
        .collect()
}

// ── texte_doc & aperçu ────────────────────────────────────────────────────────

fn html_unescape(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
}

fn nettoyer_xml(xml: &str) -> String {
    let s = xml
        .replace("</w:p>", "\n")
        .replace("</text:p>", "\n")
        .replace("</w:tr>", "\n")
        .replace("</text:h>", "\n")
        .replace("<w:tab/>", " ")
        .replace("<text:tab/>", " ");
    let tag_re = Regex::new(r"<[^>]+>").unwrap();
    let ws_re = Regex::new(r"[ \t]+").unwrap();
    let txt = html_unescape(&tag_re.replace_all(&s, " "));
    txt.lines()
        .map(|l| ws_re.replace_all(l, " ").trim().to_string())
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}

fn extraire_texte_doc(chemin: &Path) -> String {
    let ext = chemin
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| format!(".{}", s.to_ascii_lowercase()))
        .unwrap_or_default();
    let c_str = chemin.to_string_lossy().to_string();
    match ext.as_str() {
        ".pdf" => run_cmd_stdout("pdftotext", &["-q", "-layout", &c_str, "-"]).unwrap_or_default(),
        ".docx" => {
            let xml = run_cmd_stdout("unzip", &["-p", &c_str, "word/document.xml"]).unwrap_or_default();
            nettoyer_xml(&xml)
        }
        ".odt" | ".odp" | ".ods" => {
            let xml = run_cmd_stdout("unzip", &["-p", &c_str, "content.xml"]).unwrap_or_default();
            nettoyer_xml(&xml)
        }
        _ => {
            let Ok(mut f) = File::open(chemin) else {
                return String::new();
            };
            let mut debut = vec![0u8; 8192];
            let n = f.read(&mut debut).unwrap_or(0);
            if debut[..n].contains(&0) {
                return String::new();
            }
            fs::read_to_string(chemin).unwrap_or_default()
        }
    }
}

pub fn run_texte_doc(args: &[String]) -> i32 {
    let Some(p) = args.first() else {
        return 2;
    };
    let txt = extraire_texte_doc(Path::new(p));
    print!("{}", txt);
    0
}

fn taille_lisible(mut octets: f64) -> String {
    for unite in ["o", "ko", "Mo", "Go", "To"] {
        if octets < 1024.0 || unite == "To" {
            return if unite == "o" {
                format!("{:.0} {}", octets, unite)
            } else {
                format!("{:.1} {}", octets, unite)
            };
        }
        octets /= 1024.0;
    }
    String::new()
}

fn format_dm_hm(mtime: SystemTime) -> String {
    let secs = mtime
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as libc::time_t)
        .unwrap_or(0);
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&secs, &mut tm);
        format!(
            "{:02}/{:02} {:02}:{:02}",
            tm.tm_mday,
            tm.tm_mon + 1,
            tm.tm_hour,
            tm.tm_min
        )
    }
}

fn apercu(chemin_in: &str) -> Value {
    let exp = if chemin_in == "~" {
        home_dir()
    } else if let Some(rest) = chemin_in.strip_prefix("~/") {
        home_dir().join(rest)
    } else {
        PathBuf::from(chemin_in)
    };
    if !exp.exists() {
        return json!({ "ok": false, "type": "absent", "meta": {}, "texte": "", "message": "fichier absent" });
    }
    let meta_fs = match fs::metadata(&exp) {
        Ok(m) => m,
        Err(e) => {
            return json!({ "ok": false, "type": "illisible", "texte": "", "message": e.to_string() })
        }
    };
    let home_prefix = format!("{}/", home_dir().display());
    let nom = exp
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string();
    let mtime = meta_fs.modified().unwrap_or(UNIX_EPOCH);
    let mut meta = json!({
        "nom": nom,
        "taille": taille_lisible(meta_fs.len() as f64),
        "date": format_dm_hm(mtime),
        "chemin": exp.to_string_lossy().replace(&home_prefix, "~/"),
    });

    if exp.is_dir() {
        let Ok(rd) = fs::read_dir(&exp) else {
            return json!({ "ok": false, "type": "illisible", "texte": "", "message": "dossier illisible" });
        };
        let mut entrees: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
        entrees.sort();
        let total = entrees.len();
        let visibles: Vec<String> = entrees
            .into_iter()
            .take(40)
            .map(|p| {
                let n = p.file_name().and_then(|s| s.to_str()).unwrap_or("");
                if p.is_dir() {
                    format!("{}/", n)
                } else {
                    n.to_string()
                }
            })
            .collect();
        meta.as_object_mut()
            .unwrap()
            .insert("taille".into(), json!(format!("{} entrées", total)));
        return json!({ "ok": true, "type": "dossier", "meta": meta, "texte": visibles.join("\n") });
    }

    let ext = exp
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| format!(".{}", s.to_ascii_lowercase()))
        .unwrap_or_default();

    if matches!(
        ext.as_str(),
        ".png" | ".jpg" | ".jpeg" | ".webp" | ".gif" | ".bmp" | ".svg" | ".avif" | ".ico"
    ) {
        return json!({
            "ok": true,
            "type": "image",
            "meta": meta,
            "url": format!("file://{}", exp.display()),
            "texte": "",
        });
    }

    if matches!(ext.as_str(), ".pdf" | ".docx" | ".odt" | ".odp") {
        let est_pdf = ext == ".pdf";
        let typ = if est_pdf { "pdf" } else { "bureautique" };
        let brut = extraire_texte_doc(&exp);
        let lignes: Vec<String> = brut
            .lines()
            .take(LIGNES_APERCU)
            .map(|l| l.replace('\u{c}', "").chars().take(COLONNES_APERCU).collect())
            .collect();
        let texte = lignes.join("\n");
        if texte.trim().is_empty() {
            return json!({
                "ok": true,
                "type": typ,
                "meta": meta,
                "texte": "",
                "message": if est_pdf { "aucun texte — scan sans couche texte ?" } else { "aucun texte extrait" },
            });
        }
        return json!({ "ok": true, "type": typ, "meta": meta, "texte": texte, "note": "texte extrait" });
    }

    let Ok(mut f) = File::open(&exp) else {
        return json!({ "ok": false, "type": "illisible", "texte": "", "message": "fichier illisible" });
    };
    let mut debut = vec![0u8; 8192];
    let n = f.read(&mut debut).unwrap_or(0);
    if debut[..n].contains(&0) {
        return json!({ "ok": true, "type": "binaire", "meta": meta, "texte": "", "message": "contenu binaire" });
    }
    let tronque_taille = meta_fs.len() > (n as u64) * 2;
    let texte_raw = if tronque_taille {
        let mut rdr = BufReader::new(File::open(&exp).unwrap());
        let mut acc = String::new();
        for _ in 0..LIGNES_APERCU {
            let mut l = String::new();
            if rdr.read_line(&mut l).unwrap_or(0) == 0 {
                break;
            }
            acc.push_str(&l);
        }
        acc
    } else {
        String::from_utf8_lossy(&debut[..n]).to_string()
    };
    let all_lines: Vec<&str> = texte_raw.lines().collect();
    let lignes: Vec<String> = all_lines
        .iter()
        .take(LIGNES_APERCU)
        .map(|l| l.chars().take(COLONNES_APERCU).collect())
        .collect();
    json!({
        "ok": true,
        "type": "texte",
        "meta": meta,
        "texte": lignes.join("\n"),
        "tronque": tronque_taille || all_lines.len() > LIGNES_APERCU,
    })
}

// ── dispatch ──────────────────────────────────────────────────────────────────

fn traiter(requete: &str, limite: usize) -> Value {
    if requete.trim().is_empty() {
        return json!({ "ok": true, "prefix": "", "kind": "", "results": [] });
    }
    let sym = requete.chars().next().unwrap();
    let sym_s = sym.to_string();
    let body = &requete[sym.len_utf8()..];

    let Some(pdef) = PREFIXES.iter().find(|p| p.sym == sym_s) else {
        return json!({ "ok": true, "prefix": "", "kind": "", "results": [] });
    };
    if pdef.kind == "commande" {
        return json!({ "ok": true, "prefix": sym_s, "kind": "commande", "results": [], "qml": true });
    }

    let (mut res, interrompu) = match pdef.kind {
        "calc" => (calcul(body), false),
        "fichiers" => (fichiers(body, limite), false),
        "contenu" => contenu(body, limite),
        "presse" => (presse(body, limite), false),
        "emoji" => (emoji(body, limite), false),
        "unites" => (unites(body), false),
        "devises" => (devises(body), false),
        "processus" => (processus(body, limite), false),
        "signets" => (signets(body, limite), false),
        "aide" => (aide(), false),
        _ => (vec![], false),
    };

    for r in &mut res {
        if let Some(m) = r.as_object_mut() {
            m.entry("sym".to_string()).or_insert_with(|| json!(sym_s));
        }
    }

    json!({
        "ok": true,
        "prefix": sym_s,
        "kind": pdef.kind,
        "results": res,
        "interrompu": interrompu,
    })
}

pub fn run(args: &[String]) -> i32 {
    let mut requete = String::new();
    let mut limite = LIMITE_DEFAUT;
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--supprimer" if i + 1 < args.len() => {
                println!("{}", presse_supprimer(&args[i + 1]));
                return 0;
            }
            "--vider" => {
                println!("{}", presse_vider());
                return 0;
            }
            "--epingler" if i + 1 < args.len() => {
                println!("{}", presse_epingler(&args[i + 1], ""));
                return 0;
            }
            "--desepingler" if i + 1 < args.len() => {
                println!("{}", presse_desepingler(&args[i + 1]));
                return 0;
            }
            "--query" if i + 1 < args.len() => {
                requete = args[i + 1].clone();
                i += 2;
                continue;
            }
            "--limit" if i + 1 < args.len() => {
                if let Ok(v) = args[i + 1].parse::<usize>() {
                    limite = v.clamp(1, 20);
                }
                i += 2;
                continue;
            }
            "--apercu" if i + 1 < args.len() => {
                println!("{}", apercu(&args[i + 1]));
                return 0;
            }
            "--aide" => {
                println!("{}", json!({ "ok": true, "prefixes": phrases_aide() }));
                return 0;
            }
            other => {
                requete = other.to_string();
            }
        }
        i += 1;
    }

    println!("{}", traiter(&requete, limite));
    0
}
