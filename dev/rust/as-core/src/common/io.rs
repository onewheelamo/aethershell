use crate::common::lock::FileLock;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{Map, Value};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

pub fn read_json<T: DeserializeOwned>(path: &Path) -> Option<T> {
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

pub fn read_json_value(path: &Path) -> Value {
    read_json::<Value>(path).unwrap_or_else(|| Value::Object(Map::new()))
}

pub fn write_json_atomic<T: Serialize + ?Sized>(path: &Path, data: &T, mode: u32) -> io::Result<()> {
    let _lock = FileLock::acquire(path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut tmp_os = path.as_os_str().to_os_string();
    tmp_os.push(format!(".tmp.{}", std::process::id()));
    let tmp_path = PathBuf::from(tmp_os);

    let json = serde_json::to_string_pretty(data)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    {
        let mut f = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .mode(mode)
            .open(&tmp_path)?;
        f.write_all(json.as_bytes())?;
        f.write_all(b"\n")?;
        f.sync_all()?;
    }
    fs::rename(&tmp_path, path)?;
    Ok(())
}

pub fn write_private_json<T: Serialize + ?Sized>(path: &Path, data: &T) -> io::Result<()> {
    write_json_atomic(path, data, 0o600)
}

pub fn run_cmd(program: &str, args: &[&str]) -> Option<Output> {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .output()
        .ok()
}

pub fn run_cmd_stdout(program: &str, args: &[&str]) -> Option<String> {
    let out = run_cmd(program, args)?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Extrait `--options={...}` des arguments CLI passés par `Applet.qml`.
pub fn parse_options_arg(args: &[String]) -> Map<String, Value> {
    for (i, arg) in args.iter().enumerate() {
        if let Some(raw) = arg.strip_prefix("--options=") {
            if let Ok(Value::Object(m)) = serde_json::from_str::<Value>(raw) {
                return m;
            }
        } else if arg == "--options" {
            if let Some(raw) = args.get(i + 1) {
                if let Ok(Value::Object(m)) = serde_json::from_str::<Value>(raw) {
                    return m;
                }
            }
        }
    }
    Map::new()
}

/// Active `PR_SET_PDEATHSIG(SIGTERM)` pour éviter tout démon orphelin si Quickshell meurt.
pub fn tie_to_parent_death() {
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }
}
