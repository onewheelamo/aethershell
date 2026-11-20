use crate::common::contrat::sortir;
use crate::common::io::{read_json_value, write_json_atomic};
use crate::common::paths::core_dir;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_ENTRIES: usize = 25;

fn history_file() -> PathBuf {
    core_dir().join("launch_history.json")
}

fn load() -> Vec<Value> {
    match read_json_value(&history_file()) {
        Value::Array(arr) => arr,
        _ => vec![],
    }
}

fn save(entries: &[Value]) {
    let _ = write_json_atomic(&history_file(), entries, 0o644);
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("");
    match action {
        "add" if args.len() >= 3 => {
            let name = &args[1];
            let cmd = &args[2];
            let icon = args.get(3).map(|s| s.as_str()).unwrap_or("");
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs() as i64)
                .unwrap_or(0);
            let mut entries: Vec<Value> = load()
                .into_iter()
                .filter(|e| e.get("exec").and_then(|v| v.as_str()) != Some(cmd.as_str()))
                .collect();
            entries.insert(
                0,
                json!({
                    "name": name,
                    "exec": cmd,
                    "icon": icon,
                    "t": now,
                }),
            );
            entries.truncate(MAX_ENTRIES);
            save(&entries);
            0
        }
        "clear" => {
            save(&[]);
            0
        }
        "list" => sortir(&Value::Array(load())),
        _ => 1,
    }
}
