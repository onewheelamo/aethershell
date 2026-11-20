use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, write_json_atomic};
use crate::common::paths::core_dir;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;

const BARRES: &[&str] = &["haut", "bas", "cote-gauche", "cote-droite"];
const ZONES: &[&str] = &["debut", "milieu", "fin"];
const ECHELLE_MIN: i64 = 60;
const ECHELLE_MAX: i64 = 160;

fn all_iles() -> Vec<String> {
    let mut out = Vec::with_capacity(12);
    for b in BARRES {
        for z in ZONES {
            out.push(format!("{b}:{z}"));
        }
    }
    out
}

fn map_ancien(ile: &str) -> String {
    match ile {
        "gauche" | "haut-gauche" => "haut:debut".into(),
        "centre" | "haut-centre" => "haut:milieu".into(),
        "droite" | "haut-droite" => "haut:fin".into(),
        "bas" => "bas:milieu".into(),
        "cote-gauche" => "cote-gauche:milieu".into(),
        "cote-droite" => "cote-droite:milieu".into(),
        other => other.to_string(),
    }
}

fn catalogue_path() -> PathBuf {
    core_dir().join("applets_catalogue.json")
}

fn etat_path() -> PathBuf {
    core_dir().join("bar_applets.json")
}

fn catalogue() -> Vec<Map<String, Value>> {
    let v = read_json_value(&catalogue_path());
    v.get("applets")
        .and_then(|a| a.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_object().cloned())
                .filter(|m| m.get("id").and_then(|s| s.as_str()).map(|s| !s.is_empty()).unwrap_or(false))
                .collect()
        })
        .unwrap_or_default()
}

fn read_etat_raw() -> (Map<String, Value>, Map<String, Value>) {
    let v = read_json_value(&etat_path());
    let mut actifs = v
        .get("actifs")
        .and_then(|a| a.as_object())
        .cloned()
        .unwrap_or_default();
    for val in actifs.values_mut() {
        if let Some(obj) = val.as_object_mut() {
            if let Some(ile) = obj.get("ile").and_then(|s| s.as_str()) {
                let mapped = map_ancien(ile);
                obj.insert("ile".into(), json!(mapped));
            }
        }
    }
    let inactives = v
        .get("options_inactives")
        .and_then(|a| a.as_object())
        .cloned()
        .unwrap_or_default();
    (actifs, inactives)
}

fn save_etat(actifs: &Map<String, Value>, inactives: &Map<String, Value>) {
    let mut charge = Map::new();
    charge.insert("version".into(), json!(1));
    charge.insert("actifs".into(), Value::Object(actifs.clone()));
    if !inactives.is_empty() {
        charge.insert("options_inactives".into(), Value::Object(inactives.clone()));
    }
    let _ = write_json_atomic(&etat_path(), &Value::Object(charge), 0o644);
}

fn entree(
    applet: &Map<String, Value>,
    choix: Option<&Map<String, Value>>,
    inactives: Option<&Map<String, Value>>,
) -> Map<String, Value> {
    let mut e = applet.clone();
    let actif = choix.is_some();
    e.insert("actif".into(), json!(actif));

    let raw_ile = choix
        .and_then(|c| c.get("ile"))
        .and_then(|v| v.as_str())
        .or_else(|| applet.get("ile").and_then(|v| v.as_str()))
        .unwrap_or("haut:fin");
    let mapped = map_ancien(raw_ile);
    let iles = all_iles();
    let ile_ok = if iles.contains(&mapped) { mapped } else { "haut:fin".to_string() };
    e.insert("ile".into(), json!(ile_ok));

    let ordre = choix
        .and_then(|c| c.get("ordre"))
        .and_then(|v| v.as_i64())
        .or_else(|| applet.get("ordre").and_then(|v| v.as_i64()))
        .unwrap_or(100);
    e.insert("ordre".into(), json!(ordre));

    let sc = choix
        .and_then(|c| c.get("text_scale"))
        .and_then(|v| v.as_i64())
        .or_else(|| applet.get("text_scale").and_then(|v| v.as_i64()))
        .unwrap_or(100)
        .clamp(ECHELLE_MIN, ECHELLE_MAX);
    e.insert("text_scale".into(), json!(sc));

    let aid = applet.get("id").and_then(|v| v.as_str()).unwrap_or("");
    let opts = choix
        .and_then(|c| c.get("options"))
        .and_then(|v| v.as_object())
        .cloned()
        .or_else(|| {
            inactives
                .and_then(|inact| inact.get(aid))
                .and_then(|v| v.as_object())
                .cloned()
        })
        .unwrap_or_default();
    e.insert("options".into(), Value::Object(opts));
    e
}

fn etat_complet() -> Value {
    let (actifs, inactives) = read_etat_raw();
    let arr: Vec<Value> = catalogue()
        .iter()
        .map(|a| {
            let aid = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let ch = actifs.get(aid).and_then(|v| v.as_object());
            Value::Object(entree(a, ch, Some(&inactives)))
        })
        .collect();
    Value::Array(arr)
}

fn resoudre(ile_filter: Option<&str>) -> Value {
    let (actifs, _) = read_etat_raw();
    let iles = all_iles();
    let mut list: Vec<Map<String, Value>> = catalogue()
        .iter()
        .filter(|a| !a.get("fixe").and_then(|v| v.as_bool()).unwrap_or(false))
        .filter_map(|a| {
            let aid = a.get("id").and_then(|v| v.as_str())?;
            let ch = actifs.get(aid)?.as_object()?;
            Some(entree(a, Some(ch), None))
        })
        .collect();
    if let Some(f) = ile_filter {
        list.retain(|a| a.get("ile").and_then(|v| v.as_str()) == Some(f));
    }
    list.sort_by(|a, b| {
        let ia = iles
            .iter()
            .position(|x| Some(x.as_str()) == a.get("ile").and_then(|v| v.as_str()))
            .unwrap_or(99);
        let ib = iles
            .iter()
            .position(|x| Some(x.as_str()) == b.get("ile").and_then(|v| v.as_str()))
            .unwrap_or(99);
        let oa = a.get("ordre").and_then(|v| v.as_i64()).unwrap_or(100);
        let ob = b.get("ordre").and_then(|v| v.as_i64()).unwrap_or(100);
        let ida = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
        let idb = b.get("id").and_then(|v| v.as_str()).unwrap_or("");
        ia.cmp(&ib).then_with(|| oa.cmp(&ob)).then_with(|| ida.cmp(idb))
    });
    Value::Array(list.into_iter().map(Value::Object).collect())
}

fn allumer_barre(ile: &str) {
    let barre = ile.split(':').next().unwrap_or("");
    let cle = match barre {
        "bas" => "bar_bottom",
        "cote-gauche" => "bar_left",
        "cote-droite" => "bar_right",
        _ => return,
    };
    let style_p = core_dir().join("style_vars.json");
    let mut style = match read_json_value(&style_p) {
        Value::Object(m) => m,
        _ => Map::new(),
    };
    if style.get(cle).and_then(|v| v.as_bool()) == Some(true) {
        return;
    }
    style.insert(cle.into(), json!(true));
    let _ = write_json_atomic(&style_p, &Value::Object(style), 0o644);
}

fn find_cat(aid: &str) -> Result<Map<String, Value>, i32> {
    catalogue()
        .into_iter()
        .find(|a| a.get("id").and_then(|v| v.as_str()) == Some(aid))
        .ok_or_else(|| {
            eprintln!("applet inconnu : {aid}");
            1
        })
}

fn activer(aid: &str, ile_opt: Option<&str>) -> Result<(), i32> {
    let cat = find_cat(aid)?;
    let (mut actifs, mut inactives) = read_etat_raw();
    let cur = actifs.get(aid).and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let raw_ile = ile_opt
        .or_else(|| cur.get("ile").and_then(|v| v.as_str()))
        .or_else(|| cat.get("ile").and_then(|v| v.as_str()))
        .unwrap_or("droite");
    let ile = map_ancien(raw_ile);
    if !all_iles().contains(&ile) {
        eprintln!("îlot inconnu : {ile}");
        return Err(1);
    }
    allumer_barre(&ile);
    let ordre = cur
        .get("ordre")
        .and_then(|v| v.as_i64())
        .or_else(|| cat.get("ordre").and_then(|v| v.as_i64()))
        .unwrap_or(100);
    let sc = cur
        .get("text_scale")
        .and_then(|v| v.as_i64())
        .or_else(|| cat.get("text_scale").and_then(|v| v.as_i64()))
        .unwrap_or(100);
    let opts = cur
        .get("options")
        .cloned()
        .or_else(|| inactives.remove(aid))
        .unwrap_or_else(|| json!({}));
    actifs.insert(
        aid.into(),
        json!({
            "ile": ile,
            "ordre": ordre,
            "text_scale": sc,
            "options": opts,
        }),
    );
    save_etat(&actifs, &inactives);
    Ok(())
}

fn desactiver(aid: &str) {
    let (mut actifs, mut inactives) = read_etat_raw();
    if let Some(Value::Object(prev)) = actifs.remove(aid) {
        if let Some(opts) = prev.get("options") {
            if opts.as_object().map(|m| !m.is_empty()).unwrap_or(false) {
                inactives.insert(aid.into(), opts.clone());
            }
        }
    }
    save_etat(&actifs, &inactives);
}

fn deplacer_vers(aid: &str, raw_ile: &str, idx_opt: Option<&str>) -> Result<(), i32> {
    let cat = find_cat(aid)?;
    let ile = map_ancien(raw_ile);
    if !all_iles().contains(&ile) {
        eprintln!("emplacement inconnu : {ile}");
        return Err(1);
    }
    allumer_barre(&ile);
    let (mut actifs, mut inactives) = read_etat_raw();
    if !actifs.contains_key(aid) {
        let opts = inactives.remove(aid).unwrap_or_else(|| json!({}));
        actifs.insert(
            aid.into(),
            json!({
                "ile": ile,
                "ordre": cat.get("ordre").and_then(|v| v.as_i64()).unwrap_or(100),
                "text_scale": cat.get("text_scale").and_then(|v| v.as_i64()).unwrap_or(100),
                "options": opts,
            }),
        );
    } else if let Some(Value::Object(obj)) = actifs.get_mut(aid) {
        obj.insert("ile".into(), json!(ile));
    }

    let mut voisins: Vec<(i64, String)> = actifs
        .iter()
        .filter(|(k, _)| k.as_str() != aid)
        .filter_map(|(k, v)| {
            let o = v.as_object()?;
            let vi = map_ancien(o.get("ile").and_then(|x| x.as_str()).unwrap_or(""));
            if vi == ile {
                Some((o.get("ordre").and_then(|x| x.as_i64()).unwrap_or(100), k.clone()))
            } else {
                None
            }
        })
        .collect();
    voisins.sort();
    let mut ids: Vec<String> = voisins.into_iter().map(|(_, k)| k).collect();
    let pos = idx_opt
        .and_then(|s| s.parse::<usize>().ok())
        .map(|p| p.min(ids.len()))
        .unwrap_or(ids.len());
    ids.insert(pos, aid.to_string());
    for (n, k) in ids.into_iter().enumerate() {
        if let Some(Value::Object(obj)) = actifs.get_mut(&k) {
            obj.insert("ordre".into(), json!((n as i64 + 1) * 10));
        }
    }
    save_etat(&actifs, &inactives);
    Ok(())
}

fn reinitialiser() {
    let defauts = [
        "workspaces", "minimise", "horloge", "calendrier",
        "notifications", "presse-papiers", "maj", "systray",
        "reseau", "luminosite", "batterie", "volume", "alimentation",
    ];
    let cat_map: HashMap<String, Map<String, Value>> = catalogue()
        .into_iter()
        .filter_map(|a| Some((a.get("id")?.as_str()?.to_string(), a)))
        .collect();
    let (_, inactives) = read_etat_raw();
    let mut actifs = Map::new();
    for aid in defauts {
        let Some(a) = cat_map.get(aid) else { continue };
        let ile = map_ancien(a.get("ile").and_then(|v| v.as_str()).unwrap_or("haut:fin"));
        actifs.insert(
            aid.into(),
            json!({
                "ile": ile,
                "ordre": a.get("ordre").and_then(|v| v.as_i64()).unwrap_or(100),
                "text_scale": a.get("text_scale").and_then(|v| v.as_i64()).unwrap_or(100),
                "options": {},
            }),
        );
    }
    save_etat(&actifs, &inactives);
}

pub fn run(args: &[String]) -> i32 {
    let Some(action) = args.first().map(|s| s.as_str()) else {
        return 2;
    };
    match action {
        "state" => return sortir(&etat_complet()),
        "resoudre" => return sortir(&resoudre(args.get(1).map(|s| s.as_str()))),
        "activer" if args.len() > 1 => {
            if activer(&args[1], args.get(2).map(|s| s.as_str())).is_err() {
                return 1;
            }
        }
        "desactiver" if args.len() > 1 => desactiver(&args[1]),
        "placer" if args.len() > 2 => {
            let ile = map_ancien(&args[2]);
            if !all_iles().contains(&ile) {
                return 1;
            }
            let (mut actifs, inactives) = read_etat_raw();
            if !actifs.contains_key(&args[1]) {
                if activer(&args[1], Some(&ile)).is_err() {
                    return 1;
                }
            } else {
                allumer_barre(&ile);
                if let Some(Value::Object(obj)) = actifs.get_mut(&args[1]) {
                    obj.insert("ile".into(), json!(ile));
                }
                save_etat(&actifs, &inactives);
            }
        }
        "deplacer_vers" if args.len() > 2 => {
            if deplacer_vers(&args[1], &args[2], args.get(3).map(|s| s.as_str())).is_err() {
                return 1;
            }
        }
        "reinitialiser" => reinitialiser(),
        "ordre" if args.len() > 2 => {
            let Ok(ord) = args[2].parse::<i64>() else { return 1; };
            let (mut actifs, inactives) = read_etat_raw();
            if let Some(Value::Object(obj)) = actifs.get_mut(&args[1]) {
                obj.insert("ordre".into(), json!(ord));
                save_etat(&actifs, &inactives);
            } else {
                return 1;
            }
        }
        "echelle" if args.len() > 2 => {
            let Ok(val) = args[2].parse::<i64>() else { return 1; };
            let (mut actifs, inactives) = read_etat_raw();
            if let Some(Value::Object(obj)) = actifs.get_mut(&args[1]) {
                obj.insert("text_scale".into(), json!(val.clamp(ECHELLE_MIN, ECHELLE_MAX)));
                save_etat(&actifs, &inactives);
            } else {
                return 1;
            }
        }
        "monter" | "descendre" if args.len() > 1 => {
            let sens: isize = if action == "monter" { -1 } else { 1 };
            let (mut actifs, inactives) = read_etat_raw();
            let Some(ile) = actifs
                .get(&args[1])
                .and_then(|v| v.get("ile"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
            else {
                return 1;
            };
            let mut voisins: Vec<(i64, String)> = actifs
                .iter()
                .filter_map(|(k, v)| {
                    let o = v.as_object()?;
                    if o.get("ile").and_then(|x| x.as_str()) == Some(ile.as_str()) {
                        Some((o.get("ordre").and_then(|x| x.as_i64()).unwrap_or(100), k.clone()))
                    } else {
                        None
                    }
                })
                .collect();
            voisins.sort();
            let ids: Vec<String> = voisins.into_iter().map(|(_, k)| k).collect();
            if let Some(i) = ids.iter().position(|k| k == &args[1]) {
                let j = i as isize + sens;
                if j >= 0 && (j as usize) < ids.len() {
                    let mut ordres: BTreeMap<String, i64> = ids
                        .iter()
                        .enumerate()
                        .map(|(n, k)| (k.clone(), (n as i64 + 1) * 10))
                        .collect();
                    let ju = j as usize;
                    let oi = ordres[&ids[i]];
                    let oj = ordres[&ids[ju]];
                    ordres.insert(ids[i].clone(), oj);
                    ordres.insert(ids[ju].clone(), oi);
                    for (k, o) in ordres {
                        if let Some(Value::Object(obj)) = actifs.get_mut(&k) {
                            obj.insert("ordre".into(), json!(o));
                        }
                    }
                    save_etat(&actifs, &inactives);
                }
            }
        }
        "option" if args.len() > 3 => {
            if find_cat(&args[1]).is_err() {
                return 1;
            }
            let raw_val = args[3..].join(" ");
            let val: Value = serde_json::from_str(&raw_val).unwrap_or_else(|_| json!(raw_val));
            let (mut actifs, mut inactives) = read_etat_raw();
            if let Some(Value::Object(obj)) = actifs.get_mut(&args[1]) {
                let mut opts = obj
                    .get("options")
                    .and_then(|v| v.as_object())
                    .cloned()
                    .unwrap_or_default();
                opts.insert(args[2].clone(), val);
                obj.insert("options".into(), Value::Object(opts));
            } else {
                let mut opts = inactives
                    .get(&args[1])
                    .and_then(|v| v.as_object())
                    .cloned()
                    .unwrap_or_default();
                opts.insert(args[2].clone(), val);
                inactives.insert(args[1].clone(), Value::Object(opts));
            }
            save_etat(&actifs, &inactives);
        }
        _ => return 2,
    }
    sortir(&etat_complet())
}
