use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, run_cmd, write_json_atomic, write_private_json};
use crate::common::paths::core_dir;
use serde_json::{json, Map, Value};
use std::fs;
use std::path::PathBuf;

const DEFAULT_ILOT_ORDER: &[&str] = &[
    "horloge", "workspaces", "systray", "luminosite", "batterie", "minimise",
    "volume", "reseau", "notifications", "maj", "todo", "meteo",
    "presse-papiers", "usb", "systeme", "comptes",
];

fn style_path() -> PathBuf {
    core_dir().join("style_vars.json")
}

fn secrets_path() -> PathBuf {
    core_dir().join("secrets.json")
}

fn widgets_path() -> PathBuf {
    core_dir().join("widgets.json")
}

fn read_style() -> Map<String, Value> {
    match read_json_value(&style_path()) {
        Value::Object(m) => m,
        _ => Map::new(),
    }
}

fn delegate_py_config(args: &[String]) -> i32 {
    let py = core_dir().join("config_manager.py");
    let mut all = vec![py.to_string_lossy().to_string()];
    all.extend(args.iter().cloned());
    let refs: Vec<&str> = all.iter().map(|s| s.as_str()).collect();
    match run_cmd("python3", &refs) {
        Some(o) => {
            print!("{}", String::from_utf8_lossy(&o.stdout));
            eprint!("{}", String::from_utf8_lossy(&o.stderr));
            o.status.code().unwrap_or(0)
        }
        None => 1,
    }
}

fn full_state_via_py() -> i32 {
    delegate_py_config(&["state".to_string()])
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("state");
    match action {
        "panel_section" if args.len() >= 3 => {
            let mut data = read_style();
            let mut secs = data
                .get("panel_sections")
                .and_then(|v| v.as_object())
                .cloned()
                .unwrap_or_default();
            let open = matches!(args[2].to_ascii_lowercase().as_str(), "true" | "1" | "yes" | "on");
            secs.insert(args[1].clone(), json!(open));
            data.insert("panel_sections".into(), Value::Object(secs));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            full_state_via_py()
        }
        "complete_first_run" => {
            let mut data = read_style();
            data.insert("first_run_done".into(), json!(true));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            full_state_via_py()
        }
        "widget_list" => {
            let w = read_json_value(&widgets_path());
            let arr = if w.is_array() { w } else { json!([]) };
            sortir(&arr)
        }
        "api_key_set_file" if args.len() >= 2 => {
            let tmp_path = PathBuf::from(&args[1]);
            let payload = read_json_value(&tmp_path);
            let _ = fs::remove_file(&tmp_path);
            if let Value::Object(m) = payload {
                let sec = m.get("section").and_then(|v| v.as_str()).unwrap_or("").trim();
                let nom = m.get("nom").and_then(|v| v.as_str()).unwrap_or("").trim();
                let val = m.get("valeur").and_then(|v| v.as_str()).unwrap_or("").trim();
                if !sec.is_empty() && !nom.is_empty() {
                    let sp = secrets_path();
                    let mut secrets = match read_json_value(&sp) {
                        Value::Object(sm) => sm,
                        _ => Map::new(),
                    };
                    let mut sec_obj = secrets
                        .get(sec)
                        .and_then(|v| v.as_object())
                        .cloned()
                        .unwrap_or_default();
                    if val.is_empty() {
                        sec_obj.remove(nom);
                    } else {
                        sec_obj.insert(nom.into(), json!(val));
                    }
                    secrets.insert(sec.into(), Value::Object(sec_obj));
                    let _ = write_private_json(&sp, &Value::Object(secrets));
                }
            }
            full_state_via_py()
        }
        "ilot_applet_move_to" if args.len() >= 3 => {
            let aid = args[1].trim().to_string();
            let raw_c = args[2].trim().to_ascii_lowercase();
            let corner = match raw_c.as_str() {
                "top-left" | "top-right" | "bottom-left" | "bottom-right" => raw_c,
                _ => String::new(),
            };
            let idx_target = args.get(3).and_then(|s| s.parse::<isize>().ok());

            let mut data = read_style();
            let mut order: Vec<String> = data
                .get("ilot_applets_order")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|x| x.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            if order.is_empty() {
                order = DEFAULT_ILOT_ORDER.iter().map(|s| s.to_string()).collect();
            } else {
                for &d in DEFAULT_ILOT_ORDER {
                    if !order.iter().any(|x| x == d) {
                        order.push(d.to_string());
                    }
                }
            }
            if !aid.is_empty() && !order.contains(&aid) {
                order.push(aid.clone());
            }

            let mut corners = data
                .get("ilot_applets_corner")
                .and_then(|v| v.as_object())
                .cloned()
                .unwrap_or_default();
            if corner.is_empty() {
                corners.remove(&aid);
            } else {
                corners.insert(aid.clone(), json!(corner));
            }

            let mut modes = data
                .get("ilot_applets_mode")
                .and_then(|v| v.as_object())
                .cloned()
                .unwrap_or_default();
            let def_exp = ["systray", "minimise", "luminosite", "batterie"];
            let cur_mode = modes
                .get(&aid)
                .and_then(|v| v.as_str())
                .unwrap_or(if def_exp.contains(&aid.as_str()) { "expanded" } else { "off" });
            if cur_mode == "off" {
                modes.insert(aid.clone(), json!("both"));
            }

            if let Some(pos_cur) = order.iter().position(|x| x == &aid) {
                order.remove(pos_cur);
                let groupe_positions: Vec<usize> = order
                    .iter()
                    .enumerate()
                    .filter(|(_, x)| {
                        corners.get(x.as_str()).and_then(|v| v.as_str()).unwrap_or("") == corner
                    })
                    .map(|(i, _)| i)
                    .collect();
                let insert_pos = match idx_target {
                    None => groupe_positions.last().map(|&p| p + 1).unwrap_or(order.len()),
                    Some(idx) if (idx as usize) >= groupe_positions.len() => {
                        groupe_positions.last().map(|&p| p + 1).unwrap_or(order.len())
                    }
                    Some(idx) if idx <= 0 => groupe_positions.first().copied().unwrap_or(0),
                    Some(idx) => groupe_positions[idx as usize],
                };
                order.insert(insert_pos, aid);
            }

            data.insert("ilot_applets_order".into(), json!(order));
            data.insert("ilot_applets_corner".into(), Value::Object(corners));
            data.insert("ilot_applets_mode".into(), Value::Object(modes));
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            full_state_via_py()
        }
        "ilot_applets_reset" => {
            let mut data = read_style();
            data.remove("ilot_applets_order");
            data.remove("ilot_applets_corner");
            data.remove("ilot_applets_mode");
            let _ = write_json_atomic(&style_path(), &Value::Object(data), 0o644);
            full_state_via_py()
        }
        _ => delegate_py_config(args),
    }
}
