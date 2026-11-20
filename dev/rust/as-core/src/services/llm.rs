use crate::common::contrat::{compact, presenter as applet_presenter, sortir as applet_sortir};
use crate::common::io::{parse_options_arg, read_json_value};
use crate::common::paths::core_dir;
use crate::services::antigravity::antigravity_data;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TTL: i64 = 300;
const COMPTES_TTL: i64 = 60;
const DEEPSEEK_SEUIL_BAS: f64 = 5.0;
const OLLAMA_SEUIL_BAS: f64 = 1.0;
const SEUIL_QUOTA: f64 = 10.0;

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn now_f64() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

// ── llm_contrat ───────────────────────────────────────────────────────────────

fn symbole_devise(devise: &str) -> &'static str {
    match devise.to_ascii_uppercase().as_str() {
        "USD" | "" => "$",
        "CNY" => "¥",
        "EUR" => "€",
        "GBP" => "£",
        _ => "",
    }
}

pub fn montant(valeur: Option<f64>, devise: &str) -> String {
    match valeur {
        Some(v) => format!("{}{:.2}", symbole_devise(devise), v),
        None => "—".to_string(),
    }
}

pub fn mesure(valeur: &str, libelle: &str) -> Value {
    json!({
        "valeur": valeur,
        "libelle": libelle,
        "texte": "",
        "fin": 0,
        "depuis": 0,
        "releve": 0,
    })
}

fn llm_presenter(
    mut donnees: Map<String, Value>,
    fournisseur: &str,
    icone: &str,
    mesures: Vec<Value>,
    alerte: bool,
) -> Map<String, Value> {
    if !donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return donnees;
    }
    donnees.insert("fournisseur".into(), json!(fournisseur));
    donnees.insert("icone".into(), json!(icone));
    donnees.insert("mesures".into(), Value::Array(mesures));
    donnees.insert("alerte".into(), json!(alerte));
    donnees
}

// ── llm_providers ─────────────────────────────────────────────────────────────

fn default_providers() -> Vec<Value> {
    vec![
        json!({
            "id": "deepseek", "label": "DeepSeek", "kind": "balance",
            "base_url": "https://api.deepseek.com", "key": "deepseek.api_key",
            "service": "core/deepseek_service.py", "widget": "deepseek",
            "hint": "sk-…", "summary": "solde de l'API",
        }),
        json!({
            "id": "ollama", "label": "Ollama Cloud", "kind": "balance",
            "base_url": "https://ollama.com", "key": "ollama.api_key",
            "service": "core/ollama_service.py", "widget": "ollama",
            "hint": "clé de ollama.com", "summary": "solde restant et coût des 7 derniers jours",
        }),
        json!({
            "id": "antigravity", "label": "Antigravity (Google AI Pro)", "kind": "quota",
            "base_url": "", "key": "", "service": "core/antigravity_service.py",
            "widget": "antigravity", "hint": "",
            "summary": "quota de l'abonnement, lu dans les logs du CLI — Gemini, Claude et GPT sous le même plafond",
        }),
    ]
}

fn charger_providers() -> HashMap<String, Value> {
    let data = read_json_value(&core_dir().join("llm_providers.json"));
    let items_opt = if let Some(arr) = data.get("providers").and_then(|v| v.as_array()) {
        Some(arr.clone())
    } else {
        data.as_array().cloned()
    };
    let entrees = match items_opt {
        Some(v) if !v.is_empty() => v,
        _ => default_providers(),
    };

    let mut sortie = HashMap::new();
    for entree in entrees {
        if let Some(id) = entree.get("id").and_then(|v| v.as_str()) {
            let tid = id.trim();
            if !tid.is_empty() {
                sortie.insert(tid.to_string(), entree);
            }
        }
    }
    for entree in default_providers() {
        if let Some(id) = entree.get("id").and_then(|v| v.as_str()) {
            sortie.entry(id.to_string()).or_insert(entree);
        }
    }
    sortie
}

fn provider_base_url(provider_id: &str, defaut: &str) -> String {
    let map = charger_providers();
    let v = map
        .get(provider_id)
        .and_then(|e| e.get("base_url"))
        .and_then(|v| v.as_str())
        .unwrap_or(defaut)
        .trim();
    let s = if v.is_empty() { defaut } else { v };
    s.trim_end_matches('/').to_string()
}

fn provider_ref_cle(provider_id: &str) -> String {
    let map = charger_providers();
    map.get(provider_id)
        .and_then(|e| e.get("key"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string()
}

fn provider_cle(provider_id: &str, env_var: &str) -> String {
    let reference = provider_ref_cle(provider_id);
    if let Some((section, nom)) = reference.split_once('.') {
        if !section.is_empty() && !nom.is_empty() {
            let secrets = read_json_value(&core_dir().join("secrets.json"));
            if let Some(val) = secrets
                .get(section)
                .and_then(|s| s.get(nom))
                .and_then(|v| v.as_str())
            {
                let t = val.trim();
                if !t.is_empty() {
                    return t.to_string();
                }
            }
        }
    }
    if !env_var.is_empty() {
        if let Ok(v) = env::var(env_var) {
            let t = v.trim();
            if !t.is_empty() {
                return t.to_string();
            }
        }
    }
    String::new()
}

fn http_get_json(url: &str, cle: &str) -> Result<Value, String> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(8))
        .build();
    match agent
        .get(url)
        .set("Authorization", &format!("Bearer {}", cle))
        .set("Accept", "application/json")
        .call()
    {
        Ok(resp) => resp
            .into_json::<Value>()
            .map_err(|e| e.to_string().chars().take(120).collect()),
        Err(ureq::Error::Status(code, _)) => Err(match code {
            401 => "clé refusée".to_string(),
            402 => "solde épuisé".to_string(),
            403 => "accès refusé".to_string(),
            429 => "limite d'appels (429)".to_string(),
            _ => format!("HTTP {}", code),
        }),
        Err(ureq::Error::Transport(t)) => Err(format!("réseau : {}", t)),
    }
}

// ── deepseek ──────────────────────────────────────────────────────────────────

fn presenter_deepseek(donnees: Map<String, Value>) -> Map<String, Value> {
    if !donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return donnees;
    }
    let total = donnees.get("total").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let available = donnees
        .get("available")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let currency = donnees
        .get("currency")
        .and_then(|v| v.as_str())
        .unwrap_or("USD");
    let (libelle, alerte) = if !available {
        ("solde épuisé · DeepSeek", true)
    } else if total < DEEPSEEK_SEUIL_BAS {
        ("à recharger · DeepSeek", true)
    } else {
        ("DeepSeek", false)
    };
    let m = vec![mesure(&montant(Some(total), currency), libelle)];
    llm_presenter(donnees, "DeepSeek", "wallet", m, alerte)
}

pub fn deepseek_data(force: bool) -> Value {
    let cache_path = core_dir().join("deepseek_cache.json");
    let cache = read_json_value(&cache_path).as_object().cloned();

    if let Some(mut c) = cache.clone() {
        let ts = c.get("ts").and_then(|v| v.as_i64()).unwrap_or(0);
        if !force && (now_secs() - ts) < TTL {
            c.insert("cached".into(), json!(true));
            c.remove("stale_reason");
            return Value::Object(presenter_deepseek(c));
        }
    }

    let cle = provider_cle("deepseek", "DEEPSEEK_API_KEY");
    if cle.is_empty() {
        if let Some(mut c) = cache {
            c.insert("cached".into(), json!(true));
            return Value::Object(presenter_deepseek(c));
        }
        return json!({
            "ok": false,
            "error": format!("clé absente (core/secrets.json → {})", provider_ref_cle("deepseek")),
        });
    }

    let url = format!(
        "{}/user/balance",
        provider_base_url("deepseek", "https://api.deepseek.com")
    );
    match http_get_json(&url, &cle) {
        Ok(charge) => {
            let soldes = charge
                .get("balance_infos")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();
            let mut retenu: Option<&Value> = None;
            let mut best_bal = f64::NEG_INFINITY;
            for info in &soldes {
                let b = info
                    .get("total_balance")
                    .and_then(|v| {
                        v.as_f64()
                            .or_else(|| v.as_str().and_then(|s| s.parse::<f64>().ok()))
                    })
                    .unwrap_or(0.0);
                if retenu.is_none() || b > best_bal {
                    retenu = Some(info);
                    best_bal = b;
                }
            }
            if let Some(r) = retenu {
                let parse_f = |k: &str| -> f64 {
                    r.get(k)
                        .and_then(|v| {
                            v.as_f64()
                                .or_else(|| v.as_str().and_then(|s| s.parse::<f64>().ok()))
                        })
                        .unwrap_or(0.0)
                };
                let mut map = Map::new();
                map.insert("ok".into(), json!(true));
                map.insert(
                    "currency".into(),
                    json!(r.get("currency").and_then(|v| v.as_str()).unwrap_or("")),
                );
                map.insert("total".into(), json!(round2(parse_f("total_balance"))));
                map.insert("granted".into(), json!(round2(parse_f("granted_balance"))));
                map.insert(
                    "topped_up".into(),
                    json!(round2(parse_f("topped_up_balance"))),
                );
                map.insert(
                    "available".into(),
                    json!(charge
                        .get("is_available")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)),
                );
                map.insert("ts".into(), json!(now_secs()));
                map.insert("cached".into(), json!(false));
                if let Ok(s) = serde_json::to_string(&Value::Object(map.clone())) {
                    let _ = fs::write(&cache_path, format!("{}\n", s));
                }
                return Value::Object(presenter_deepseek(map));
            }
            if let Some(mut c) = cache {
                if c.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                    c.insert("cached".into(), json!(true));
                    c.insert("stale_reason".into(), json!("réponse sans balance_infos"));
                    return Value::Object(presenter_deepseek(c));
                }
            }
            json!({ "ok": false, "error": "réponse sans balance_infos" })
        }
        Err(err) => {
            if let Some(mut c) = cache {
                if c.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                    c.insert("cached".into(), json!(true));
                    c.insert("stale_reason".into(), json!(err));
                    return Value::Object(presenter_deepseek(c));
                }
            }
            json!({ "ok": false, "error": err })
        }
    }
}

pub fn run_deepseek(args: &[String]) -> i32 {
    let force = args.iter().any(|a| a == "--force");
    println!("{}", deepseek_data(force));
    0
}

// ── ollama ────────────────────────────────────────────────────────────────────

fn presenter_ollama(donnees: Map<String, Value>) -> Map<String, Value> {
    if !donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return donnees;
    }
    let total = donnees.get("total").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let (libelle, alerte) = if total <= 0.0 {
        ("crédit épuisé · Ollama Cloud", true)
    } else if total < OLLAMA_SEUIL_BAS {
        ("à recharger · Ollama Cloud", true)
    } else {
        ("Ollama Cloud", false)
    };
    let mut mesures = vec![mesure(&montant(Some(total), "USD"), libelle)];
    if let Some(conso) = donnees.get("usage_7d").and_then(|v| v.as_f64()) {
        mesures.push(mesure(&montant(Some(conso), "USD"), "sur 7 j"));
    }
    llm_presenter(donnees, "Ollama Cloud", "cloud", mesures, alerte)
}

pub fn ollama_data(force: bool) -> Value {
    let cache_path = core_dir().join("ollama_cache.json");
    let cache = read_json_value(&cache_path).as_object().cloned();

    if let Some(mut c) = cache.clone() {
        let ts = c.get("ts").and_then(|v| v.as_i64()).unwrap_or(0);
        if !force && (now_secs() - ts) < TTL {
            c.insert("cached".into(), json!(true));
            c.remove("stale_reason");
            return Value::Object(presenter_ollama(c));
        }
    }

    let cle = provider_cle("ollama", "OLLAMA_API_KEY");
    if cle.is_empty() {
        if let Some(mut c) = cache {
            c.insert("cached".into(), json!(true));
            return Value::Object(presenter_ollama(c));
        }
        return json!({
            "ok": false,
            "provider": "ollama",
            "error": format!("clé absente (core/secrets.json → {})", provider_ref_cle("ollama")),
        });
    }

    let api_base = format!("{}/api", provider_base_url("ollama", "https://ollama.com"));
    match http_get_json(&format!("{}/balance", api_base), &cle) {
        Ok(charge) => {
            let inclus_bloc = charge.get("included").cloned().unwrap_or_else(|| json!({}));
            let achat_bloc = charge.get("purchased").cloned().unwrap_or_else(|| json!({}));
            let num = |v: Option<&Value>| -> Option<f64> {
                v.and_then(|x| {
                    x.as_f64()
                        .or_else(|| x.as_str().and_then(|s| s.parse::<f64>().ok()))
                })
            };
            let inclus = num(inclus_bloc.get("balance_usd")).unwrap_or(0.0);
            let achat = num(achat_bloc.get("balance_usd")).unwrap_or(0.0);
            let enveloppe = num(inclus_bloc.get("allowance_usd"));
            let reset_at = inclus_bloc
                .get("period")
                .and_then(|p| p.get("until"))
                .cloned()
                .unwrap_or(Value::Null);

            let mut fenetres = Map::new();
            for nom in ["session", "weekly"] {
                if let Some(bloc) = inclus_bloc.get(nom).and_then(|b| b.as_object()) {
                    if let Some(pct) = num(bloc.get("remaining_percent")) {
                        fenetres.insert(
                            nom.to_string(),
                            json!({
                                "percent": pct.round() as i64,
                                "resets_at": bloc.get("resets_at").cloned().unwrap_or(Value::Null),
                            }),
                        );
                    }
                }
            }

            let mut map = Map::new();
            map.insert("ok".into(), json!(true));
            map.insert("provider".into(), json!("ollama"));
            map.insert("currency".into(), json!("USD"));
            map.insert("total".into(), json!(round2(inclus + achat)));
            map.insert("included".into(), json!(round2(inclus)));
            map.insert(
                "allowance".into(),
                enveloppe.map(|e| json!(round2(e))).unwrap_or(Value::Null),
            );
            map.insert("purchased".into(), json!(round2(achat)));
            map.insert("reset_at".into(), reset_at);
            map.insert(
                "windows".into(),
                if fenetres.is_empty() {
                    Value::Null
                } else {
                    Value::Object(fenetres)
                },
            );

            match http_get_json(&format!("{}/usage?range=7d", api_base), &cle) {
                Ok(u) => {
                    let totaux = u.get("totals").cloned().unwrap_or_else(|| json!({}));
                    let usage_usd = num(totaux.get("usage_usd")).unwrap_or(0.0);
                    let req_cnt = totaux
                        .get("request_count")
                        .and_then(|v| v.as_i64())
                        .unwrap_or(0);
                    map.insert("usage_7d".into(), json!(round2(usage_usd)));
                    map.insert("requests_7d".into(), json!(req_cnt));
                    map.insert("usage_error".into(), Value::Null);
                }
                Err(e) => {
                    map.insert("usage_7d".into(), Value::Null);
                    map.insert("requests_7d".into(), Value::Null);
                    map.insert("usage_error".into(), json!(e));
                }
            }
            map.insert("ts".into(), json!(now_secs()));
            map.insert("cached".into(), json!(false));
            if let Ok(s) = serde_json::to_string(&Value::Object(map.clone())) {
                let _ = fs::write(&cache_path, format!("{}\n", s));
            }
            Value::Object(presenter_ollama(map))
        }
        Err(err) => {
            if let Some(mut c) = cache {
                if c.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
                    c.insert("cached".into(), json!(true));
                    c.insert("stale_reason".into(), json!(err));
                    return Value::Object(presenter_ollama(c));
                }
            }
            json!({ "ok": false, "provider": "ollama", "error": err })
        }
    }
}

pub fn run_ollama(args: &[String]) -> i32 {
    let force = args.iter().any(|a| a == "--force");
    println!("{}", ollama_data(force));
    0
}

// ── comptes_applet ────────────────────────────────────────────────────────────

fn pourcentage(texte: &str) -> f64 {
    texte
        .replace('%', "")
        .replace(',', ".")
        .trim()
        .parse::<f64>()
        .unwrap_or(1000.0)
}

fn libelle_ligne(ligne: &Value, nom: &str) -> String {
    let base = ligne.get("nom").and_then(|v| v.as_str()).unwrap_or(nom);
    let tranche = ligne
        .get("tranche")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if tranche.is_empty() {
        base.to_string()
    } else {
        format!("{} {}", base, tranche)
    }
}

fn valeur_service(nom: &str, s: &Value) -> Option<(String, String, bool)> {
    if !s.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return None;
    }
    if let Some(lignes) = s.get("lignes").and_then(|v| v.as_array()) {
        if !lignes.is_empty() {
            let pire = lignes
                .iter()
                .min_by(|a, b| {
                    let pa = pourcentage(a.get("valeur").and_then(|v| v.as_str()).unwrap_or(""));
                    let pb = pourcentage(b.get("valeur").and_then(|v| v.as_str()).unwrap_or(""));
                    pa.partial_cmp(&pb).unwrap_or(std::cmp::Ordering::Equal)
                })
                .unwrap();
            let texte = pire
                .get("valeur")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            if !texte.is_empty() {
                let alerte = pire
                    .get("alerte")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                return Some((texte, libelle_ligne(pire, nom), alerte));
            }
        }
    }
    if let Some(mesures) = s.get("mesures").and_then(|v| v.as_array()) {
        if let Some(m0) = mesures.first() {
            let texte = m0
                .get("valeur")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim()
                .to_string();
            if !texte.is_empty() {
                let four = s
                    .get("fournisseur")
                    .and_then(|v| v.as_str())
                    .unwrap_or(nom)
                    .to_string();
                let alerte = s.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
                return Some((texte, four, alerte));
            }
        }
    }
    None
}

fn choisir(services: &HashMap<&str, Value>) -> (String, String, bool) {
    let mut quotas: Vec<(f64, String, String)> = Vec::new();
    let mut soldes: Vec<(String, String, bool)> = Vec::new();
    for (&nom, s) in services {
        if !s.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            continue;
        }
        if let Some(lignes) = s.get("lignes").and_then(|v| v.as_array()) {
            for ligne in lignes {
                let val_s = ligne
                    .get("valeur")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                quotas.push((pourcentage(&val_s), val_s, libelle_ligne(ligne, nom)));
            }
        }
        if let Some(mesures) = s.get("mesures").and_then(|v| v.as_array()) {
            if let Some(m) = mesures.first() {
                let val_s = m
                    .get("valeur")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .trim()
                    .to_string();
                let four = s
                    .get("fournisseur")
                    .and_then(|v| v.as_str())
                    .unwrap_or(nom)
                    .to_string();
                let alerte = s.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
                soldes.push((val_s, four, alerte));
            }
        }
    }

    if let Some(q) = quotas
        .iter()
        .filter(|q| q.0 <= SEUIL_QUOTA)
        .min_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal))
    {
        return (q.1.clone(), q.2.clone(), true);
    }
    for (val, lib, alerte) in &soldes {
        if *alerte && !val.is_empty() {
            return (val.clone(), lib.clone(), true);
        }
    }
    if let Some(q) = quotas
        .iter()
        .min_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal))
    {
        return (q.1.clone(), q.2.clone(), false);
    }
    for (val, lib, _) in &soldes {
        if !val.is_empty() {
            return (val.clone(), lib.clone(), false);
        }
    }
    ("—".to_string(), String::new(), false)
}

fn survol_lignes(
    services: &HashMap<&str, Value>,
    prefere: &str,
    affiche: (&str, &str),
) -> Vec<Value> {
    let mut lignes = Vec::new();
    for nom in ["deepseek", "ollama", "antigravity"] {
        if nom == prefere || nom == "antigravity" {
            continue;
        }
        if let Some(s) = services.get(nom) {
            if let Some((val, lib, alerte)) = valeur_service(nom, s) {
                if lib == affiche.1 && val == affiche.0 {
                    continue;
                }
                lignes.push(json!({ "nom": lib, "valeur": val, "alerte": alerte }));
            }
        }
    }

    if let Some(ag) = services.get("antigravity") {
        if ag.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
            if let Some(lignes_ag) = ag.get("lignes").and_then(|v| v.as_array()) {
                for l in lignes_ag {
                    let lib = libelle_ligne(l, "antigravity");
                    let val = l
                        .get("valeur")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .trim()
                        .to_string();
                    if lib == affiche.1 && val == affiche.0 {
                        continue;
                    }
                    if lignes
                        .iter()
                        .any(|e| e.get("nom").and_then(|v| v.as_str()) == Some(&lib))
                    {
                        continue;
                    }
                    let alerte = l.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
                    lignes.push(json!({ "nom": lib, "valeur": val, "alerte": alerte }));
                }
            }
        }
    }
    lignes
}

pub fn run_comptes(args: &[String]) -> i32 {
    let force = args.iter().any(|a| a == "--force");
    let options = parse_options_arg(args);
    let prefere = options
        .get("prefere")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();

    let cache_path = core_dir().join("comptes_applet_cache.json");
    if !force {
        let lu = read_json_value(&cache_path);
        if let Some(mut map) = lu.as_object().cloned() {
            let ts = map.get("ts").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let age = now_f64() - ts;
            let cached_pref = map.get("prefere").and_then(|v| v.as_str()).unwrap_or("");
            if (0.0..COMPTES_TTL as f64).contains(&age) && cached_pref == prefere {
                let cmp = map.get("compact").cloned().unwrap_or(Value::Null);
                let alerte = map.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
                let out = applet_presenter(map, "comptes", "wallet", Some(cmp), None, None, Some(alerte), None);
                return applet_sortir(&out);
            }
        }
    }

    let mut services = HashMap::new();
    services.insert("deepseek", deepseek_data(false));
    services.insert("ollama", ollama_data(false));
    services.insert("antigravity", antigravity_data(false));

    let choisi = if matches!(prefere.as_str(), "deepseek" | "ollama" | "antigravity") {
        services
            .get(prefere.as_str())
            .and_then(|s| valeur_service(&prefere, s))
    } else {
        None
    };

    let (valeur, libelle, alerte) = match &choisi {
        Some(c) => c.clone(),
        None => choisir(&services),
    };
    let pref_eff = if choisi.is_some() {
        prefere.as_str()
    } else {
        ""
    };
    let survol = survol_lignes(&services, pref_eff, (&valeur, &libelle));
    let manquants: Vec<&str> = ["deepseek", "ollama", "antigravity"]
        .into_iter()
        .filter(|nom| {
            !services
                .get(nom)
                .and_then(|s| s.get("ok"))
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
        })
        .collect();

    let mut services_ok = Map::new();
    for nom in ["deepseek", "ollama", "antigravity"] {
        let ok = services
            .get(nom)
            .and_then(|s| s.get("ok"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        services_ok.insert(nom.to_string(), json!(ok));
    }

    let cmp = compact(&valeur, &libelle, alerte, 0, None);
    let mut map = Map::new();
    map.insert("ok".into(), json!(true));
    map.insert("ts".into(), json!(now_f64()));
    map.insert("alerte".into(), json!(alerte));
    map.insert("compact".into(), cmp.clone());
    map.insert("survol".into(), Value::Array(survol));
    map.insert("prefere".into(), json!(pref_eff));
    map.insert("services".into(), Value::Object(services_ok));
    if !manquants.is_empty() {
        map.insert(
            "stale_reason".into(),
            json!(format!("sans réponse : {}", manquants.join(", "))),
        );
    }
    if let Ok(s) = serde_json::to_string(&Value::Object(map.clone())) {
        let _ = fs::write(&cache_path, s);
    }
    let out = applet_presenter(map, "comptes", "wallet", Some(cmp), None, None, Some(alerte), None);
    applet_sortir(&out)
}
