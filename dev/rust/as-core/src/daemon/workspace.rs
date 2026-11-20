use crate::common::contrat::sortir;
use crate::common::io::{run_cmd, run_cmd_stdout};
use serde_json::{json, Value};
use std::collections::BTreeMap;

const PERMANENT: &[(i64, &str)] = &[
    (1, "一"),
    (2, "二"),
    (3, "三"),
    (4, "四"),
    (5, "五"),
];

pub fn run() -> i32 {
    let res = (|| -> Result<Value, String> {
        let ws_raw = run_cmd_stdout("hyprctl", &["workspaces", "-j"])
            .ok_or_else(|| "hyprctl workspaces failed".to_string())?;
        let data: Vec<Value> = serde_json::from_str(&ws_raw).map_err(|e| e.to_string())?;

        let act_raw = run_cmd_stdout("hyprctl", &["activeworkspace", "-j"])
            .ok_or_else(|| "hyprctl activeworkspace failed".to_string())?;
        let act: Value = serde_json::from_str(&act_raw).map_err(|e| e.to_string())?;
        let active_id = act.get("id").and_then(|v| v.as_i64()).unwrap_or(1);

        let mut ws_map: BTreeMap<i64, Value> = BTreeMap::new();
        for &(id, name) in PERMANENT {
            ws_map.insert(
                id,
                json!({
                    "id": id,
                    "name": name,
                    "windows": 0,
                    "persistent": true,
                    "active": id == active_id,
                }),
            );
        }

        for ws in data {
            let wid = ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
            if wid <= 0 {
                continue;
            }
            let wins = ws.get("windows").and_then(|v| v.as_i64()).unwrap_or(0);
            if let Some(entry) = ws_map.get_mut(&wid) {
                if let Some(obj) = entry.as_object_mut() {
                    obj.insert("windows".into(), json!(wins));
                }
            } else {
                let name = ws
                    .get("name")
                    .and_then(|v| v.as_str())
                    .filter(|s| !s.is_empty())
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| wid.to_string());
                ws_map.insert(
                    wid,
                    json!({
                        "id": wid,
                        "name": name,
                        "windows": wins,
                        "persistent": false,
                        "active": wid == active_id,
                    }),
                );
            }
        }

        let ordered: Vec<Value> = ws_map.values().cloned().collect();
        let ids: Vec<i64> = ws_map.keys().copied().collect();
        Ok(json!({
            "workspaces": ids,
            "details": ordered,
            "active": active_id,
        }))
    })();

    match res {
        Ok(v) => sortir(&v),
        Err(e) => {
            let fallback: Vec<Value> = PERMANENT
                .iter()
                .map(|&(id, name)| {
                    json!({
                        "id": id,
                        "name": name,
                        "windows": 0,
                        "persistent": true,
                        "active": id == 1,
                    })
                })
                .collect();
            sortir(&json!({
                "error": e,
                "workspaces": [1, 2, 3, 4, 5],
                "details": fallback,
                "active": 1,
            }))
        }
    }
}

pub fn run_float_toggle() -> i32 {
    let Some(ws_raw) = run_cmd_stdout("hyprctl", &["-j", "activeworkspace"]) else {
        return 1;
    };
    let Ok(ws) = serde_json::from_str::<Value>(&ws_raw) else {
        return 1;
    };
    let Some(ws_id) = ws.get("id").and_then(|v| v.as_i64()) else {
        return 0;
    };
    let Some(clients_raw) = run_cmd_stdout("hyprctl", &["-j", "clients"]) else {
        return 1;
    };
    let Ok(clients) = serde_json::from_str::<Vec<Value>>(&clients_raw) else {
        return 1;
    };

    let in_ws: Vec<&Value> = clients
        .iter()
        .filter(|c| {
            c.get("workspace").and_then(|w| w.get("id")).and_then(|v| v.as_i64()) == Some(ws_id)
                && c.get("mapped").and_then(|v| v.as_bool()).unwrap_or(true)
                && !c.get("hidden").and_then(|v| v.as_bool()).unwrap_or(false)
                && c.get("address").and_then(|v| v.as_str()).is_some()
        })
        .collect();

    if in_ws.is_empty() {
        return 0;
    }

    let want_float = in_ws
        .iter()
        .any(|c| !c.get("floating").and_then(|v| v.as_bool()).unwrap_or(false));

    let cmds: Vec<String> = in_ws
        .iter()
        .filter(|c| c.get("floating").and_then(|v| v.as_bool()).unwrap_or(false) != want_float)
        .filter_map(|c| c.get("address").and_then(|v| v.as_str()))
        .map(|addr| format!("hl.dispatch(hl.dsp.window.float({{ action = \"toggle\", window = \"address:{addr}\" }}))"))
        .collect();

    if !cmds.is_empty() {
        let lua = cmds.join("; ");
        let _ = run_cmd("hyprctl", &["eval", &lua]);
    }
    0
}
