pub mod bluetooth;
pub mod indicateurs;
pub mod live_activity;
pub mod nuit;
pub mod reseau;
pub mod system_service;
pub mod systeme;
pub mod workspace;

use crate::common::io::tie_to_parent_death;
use serde_json::{json, Map};
use std::io::{self, ErrorKind, Write};
use std::thread;
use std::time::{Duration, Instant};

pub fn run_daemon(args: &[String]) -> i32 {
    tie_to_parent_death();
    let interval_sec = args
        .first()
        .and_then(|s| s.parse::<f64>().ok())
        .map(|v| v.max(1.0))
        .unwrap_or(2.0);
    let interval = Duration::from_secs_f64(interval_sec);
    let empty_opts = Map::new();

    loop {
        let start = Instant::now();
        let sys = systeme::analyser(&empty_opts, true, false);
        let net = reseau::analyser(false);
        let payload = json!({
            "systeme": sys,
            "reseau": net,
        });
        if let Ok(line) = serde_json::to_string(&payload) {
            let mut out = io::stdout().lock();
            if let Err(e) = writeln!(out, "{line}").and_then(|_| out.flush()) {
                if e.kind() == ErrorKind::BrokenPipe {
                    return 0;
                }
                return 1;
            }
        }
        let elapsed = start.elapsed();
        if interval > elapsed + Duration::from_millis(50) {
            thread::sleep(interval - elapsed);
        }
    }
}
