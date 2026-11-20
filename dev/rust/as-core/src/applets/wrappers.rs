use crate::common::io::run_cmd;
use crate::common::paths::core_dir;

pub fn delegate(script: &str, args: &[String]) -> i32 {
    let py = core_dir().join(script);
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
