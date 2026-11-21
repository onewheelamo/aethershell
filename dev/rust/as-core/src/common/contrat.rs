use serde_json::{json, Map, Value};
use std::io::{self, Write};

pub fn compact(valeur: &str, libelle: &str, alerte: bool, fin: i64, barres: Option<Vec<Value>>) -> Value {
    let mut obj = Map::new();
    obj.insert("valeur".into(), json!(valeur));
    obj.insert("libelle".into(), json!(libelle));
    obj.insert("alerte".into(), json!(alerte));
    obj.insert("fin".into(), json!(fin));
    if let Some(b) = barres {
        if !b.is_empty() {
            obj.insert("barres".into(), Value::Array(b));
        }
    }
    Value::Object(obj)
}

#[allow(dead_code)]
pub fn barre(cle: &str, icone: &str, valeur: f64, texte: &str, niveau: &str) -> Value {
    json!({
        "cle": cle,
        "icone": icone,
        "valeur": valeur.clamp(0.0, 100.0).round() as i64,
        "texte": texte,
        "niveau": niveau,
    })
}

#[allow(dead_code)]
pub fn mesure(libelle: &str, valeur: &str, alerte: bool) -> Value {
    json!({
        "libelle": libelle,
        "valeur": valeur,
        "alerte": alerte,
    })
}

#[allow(dead_code)]
pub fn ligne(nom: &str, valeur: &str, action: Option<Value>, alerte: bool) -> Value {
    let mut obj = Map::new();
    obj.insert("nom".into(), json!(nom));
    obj.insert("valeur".into(), json!(valeur));
    obj.insert("alerte".into(), json!(alerte));
    if let Some(a) = action {
        obj.insert("action".into(), a);
    }
    Value::Object(obj)
}

pub fn presenter(
    mut donnees: Map<String, Value>,
    applet: &str,
    icone: &str,
    ligne_compact: Option<Value>,
    mesures: Option<Vec<Value>>,
    lignes: Option<Vec<Value>>,
    alerte: Option<bool>,
    source: Option<&str>,
) -> Value {
    if !donnees.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return Value::Object(donnees);
    }
    let comp = ligne_compact.unwrap_or_else(|| compact("", "", false, 0, None));
    let comp_alerte = comp.get("alerte").and_then(|v| v.as_bool()).unwrap_or(false);
    donnees.insert("applet".into(), json!(applet));
    donnees.insert("icone".into(), json!(icone));
    donnees.insert("compact".into(), comp);
    if let Some(m) = mesures {
        donnees.insert("mesures".into(), Value::Array(m));
    }
    if let Some(l) = lignes {
        donnees.insert("lignes".into(), Value::Array(l));
    }
    if let Some(a) = alerte {
        donnees.insert("alerte".into(), json!(a));
    } else if !donnees.contains_key("alerte") {
        donnees.insert("alerte".into(), json!(comp_alerte));
    }
    if let Some(s) = source {
        donnees.insert("source".into(), json!(s));
    }
    Value::Object(donnees)
}

pub fn sortir(val: &Value) -> i32 {
    if let Ok(line) = serde_json::to_string(val) {
        let mut out = io::stdout().lock();
        let _ = writeln!(out, "{line}");
        let _ = out.flush();
    }
    0
}

#[allow(dead_code)]
pub fn indisponible(applet: &str, message: &str) -> i32 {
    sortir(&json!({
        "ok": false,
        "applet": applet,
        "error": message,
    }))
}
