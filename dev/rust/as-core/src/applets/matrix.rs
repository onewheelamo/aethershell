use crate::common::io::run_cmd_stdout;
use crate::common::paths::home_dir;
use std::env;
use std::fs;
use std::os::unix::io::AsRawFd;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

const PID_FILE: &str = "/tmp/aether_matrix.pid";
const UNIMATRIX_CMD: &[&str] = &["unimatrix", "-af", "-l", "aAksS", "-s", "96"];

fn which_exists(prog: &str) -> bool {
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            if dir.join(prog).is_file() {
                return true;
            }
        }
    }
    false
}

fn trouver_terminal() -> &'static str {
    for cand in ["ghostty", "kitty", "foot", "alacritty"] {
        if which_exists(cand) {
            return cand;
        }
    }
    "xterm"
}

fn arreter_precedent() {
    if let Ok(txt) = fs::read_to_string(PID_FILE) {
        if let Ok(pid) = txt.trim().parse::<libc::pid_t>() {
            unsafe {
                if libc::killpg(pid, libc::SIGTERM) != 0 {
                    libc::kill(pid, libc::SIGTERM);
                }
            }
        }
    }
    let _ = fs::remove_file(PID_FILE);
}

fn cursor_pos() -> Option<(i32, i32)> {
    let out = run_cmd_stdout("hyprctl", &["cursorpos"])?;
    let (x_s, y_s) = out.trim().split_once(',')?;
    let x = x_s.trim().parse::<i32>().ok()?;
    let y = y_s.trim().parse::<i32>().ok()?;
    Some((x, y))
}

fn sync_winsize(stdout_fd: i32, master_fd: i32) {
    unsafe {
        let mut ws: libc::winsize = std::mem::zeroed();
        if libc::ioctl(stdout_fd, libc::TIOCGWINSZ, &mut ws) == 0 {
            libc::ioctl(master_fd, libc::TIOCSWINSZ, &ws);
        }
    }
}

fn run_screensaver() -> i32 {
    let stdin_fd = std::io::stdin().as_raw_fd();
    let stdout_fd = std::io::stdout().as_raw_fd();
    if unsafe { libc::isatty(stdin_fd) } == 0 {
        let err = Command::new(UNIMATRIX_CMD[0])
            .args(&UNIMATRIX_CMD[1..])
            .exec();
        eprintln!("unimatrix exec failed: {}", err);
        return 1;
    }

    let mut master_fd: libc::c_int = -1;
    let mut slave_fd: libc::c_int = -1;
    if unsafe {
        libc::openpty(
            &mut master_fd,
            &mut slave_fd,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    } != 0
    {
        return 1;
    }
    sync_winsize(stdout_fd, master_fd);

    let mut old_tty: libc::termios = unsafe { std::mem::zeroed() };
    let have_tty = unsafe { libc::tcgetattr(stdin_fd, &mut old_tty) } == 0;

    let mut child = unsafe {
        Command::new(UNIMATRIX_CMD[0])
            .args(&UNIMATRIX_CMD[1..])
            .stdin(Stdio::from_raw_fd_dup(slave_fd))
            .stdout(Stdio::from_raw_fd_dup(slave_fd))
            .stderr(Stdio::from_raw_fd_dup(slave_fd))
            .pre_exec(|| {
                libc::setsid();
                Ok(())
            })
            .spawn()
    };
    unsafe { libc::close(slave_fd) };

    let Ok(mut proc_child) = child else {
        unsafe { libc::close(master_fd) };
        return 1;
    };

    let stop = Arc::new(AtomicBool::new(false));
    let stop_mouse = Arc::clone(&stop);
    let _mouse_thread = thread::spawn(move || {
        thread::sleep(Duration::from_millis(450));
        let Some(initial) = cursor_pos() else {
            return;
        };
        while !stop_mouse.load(Ordering::Relaxed) {
            if let Some(cur) = cursor_pos() {
                if (cur.0 - initial.0).abs() > 2 || (cur.1 - initial.1).abs() > 2 {
                    stop_mouse.store(true, Ordering::Relaxed);
                    break;
                }
            }
            thread::sleep(Duration::from_millis(80));
        }
    });

    if have_tty {
        let mut raw = old_tty;
        unsafe {
            libc::cfmakeraw(&mut raw);
            libc::tcsetattr(stdin_fd, libc::TCSADRAIN, &raw);
        }
    }

    let mut buf = [0u8; 4096];
    let mut key_buf = [0u8; 64];
    while !stop.load(Ordering::Relaxed) {
        if let Ok(Some(_)) = proc_child.try_wait() {
            break;
        }
        sync_winsize(stdout_fd, master_fd);
        let mut fds = [
            libc::pollfd {
                fd: master_fd,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: stdin_fd,
                events: libc::POLLIN,
                revents: 0,
            },
        ];
        let ret = unsafe { libc::poll(fds.as_mut_ptr(), 2, 80) };
        if ret > 0 {
            if fds[0].revents & libc::POLLIN != 0 {
                let n = unsafe { libc::read(master_fd, buf.as_mut_ptr() as *mut _, buf.len()) };
                if n <= 0 {
                    break;
                }
                unsafe {
                    libc::write(stdout_fd, buf.as_ptr() as *const _, n as usize);
                }
            }
            if fds[1].revents & libc::POLLIN != 0 {
                let _ = unsafe {
                    libc::read(stdin_fd, key_buf.as_mut_ptr() as *mut _, key_buf.len())
                };
                stop.store(true, Ordering::Relaxed);
                break;
            }
            if fds[0].revents & (libc::POLLHUP | libc::POLLERR) != 0 {
                break;
            }
        }
    }

    stop.store(true, Ordering::Relaxed);
    if have_tty {
        unsafe {
            libc::tcsetattr(stdin_fd, libc::TCSADRAIN, &old_tty);
        }
    }
    unsafe {
        libc::close(master_fd);
    }
    if proc_child.try_wait().ok().flatten().is_none() {
        let pid = proc_child.id() as libc::pid_t;
        unsafe {
            libc::killpg(pid, libc::SIGTERM);
        }
        let _ = proc_child.kill();
        let _ = proc_child.wait();
    }
    0
}

trait FromRawFdDup {
    unsafe fn from_raw_fd_dup(fd: libc::c_int) -> Self;
}

impl FromRawFdDup for Stdio {
    unsafe fn from_raw_fd_dup(fd: libc::c_int) -> Self {
        use std::os::unix::io::FromRawFd;
        let dup_fd = libc::dup(fd);
        Stdio::from_raw_fd(dup_fd)
    }
}

fn cmd_terminal(ss: bool, inner_cmd: &[String]) -> Vec<String> {
    if which_exists("kitten") {
        let kitty_theme = home_dir().join(".config/kitty/aethershell-theme.conf");
        let mut cmd = vec!["kitten".to_string(), "panel".to_string()];
        if kitty_theme.is_file() {
            cmd.push("--config".to_string());
            cmd.push(kitty_theme.to_string_lossy().to_string());
        }
        if ss {
            cmd.extend([
                "--edge=center".to_string(),
                "--layer=overlay".to_string(),
                "--exclusive-zone=-1".to_string(),
                "--focus-policy=exclusive".to_string(),
                "--grab-keyboard=yes".to_string(),
                "-o".to_string(),
                "window_padding_width=0".to_string(),
                "-o".to_string(),
                "hide_window_decorations=yes".to_string(),
                "--".to_string(),
            ]);
        } else {
            cmd.extend([
                "--edge=background".to_string(),
                "--focus-policy=not-allowed".to_string(),
                "-o".to_string(),
                "window_padding_width=0".to_string(),
                "-o".to_string(),
                "hide_window_decorations=yes".to_string(),
                "--".to_string(),
            ]);
        }
        cmd.extend_from_slice(inner_cmd);
        return cmd;
    }

    let classe = if ss {
        "org.aether.matrix-ss"
    } else {
        "org.aether.matrix-bg"
    };
    let term = trouver_terminal();
    let mut cmd = match term {
        "ghostty" => vec![
            "ghostty".to_string(),
            format!("--class={}", classe),
            "--window-decoration=false".to_string(),
            "-e".to_string(),
        ],
        "kitty" => vec![
            "kitty".to_string(),
            "--class".to_string(),
            classe.to_string(),
            "-o".to_string(),
            "hide_window_decorations=yes".to_string(),
        ],
        "foot" => vec!["foot".to_string(), "--app-id".to_string(), classe.to_string()],
        "alacritty" => vec![
            "alacritty".to_string(),
            "--class".to_string(),
            classe.to_string(),
            "-o".to_string(),
            "window.decorations=\"None\"".to_string(),
            "-e".to_string(),
        ],
        other => vec![other.to_string(), "-e".to_string()],
    };
    cmd.extend_from_slice(inner_cmd);
    cmd
}

fn lancer(ss: bool, delay_min: f64) -> i32 {
    arreter_precedent();
    if delay_min > 0.0 {
        let pid = unsafe { libc::fork() };
        if pid > 0 {
            return 0;
        }
        unsafe {
            libc::setsid();
        }
        let _ = fs::write(PID_FILE, std::process::id().to_string());
        thread::sleep(Duration::from_secs_f64(delay_min * 60.0));
    }

    let inner: Vec<String> = if ss {
        let exe = env::current_exe()
            .ok()
            .and_then(|p| p.to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| Path::new("as-core").to_string_lossy().to_string());
        vec![exe, "matrix".to_string(), "--run-ss".to_string()]
    } else {
        UNIMATRIX_CMD.iter().map(|s| s.to_string()).collect()
    };

    let cmd = cmd_terminal(ss, &inner);
    let spawn_res = unsafe {
        Command::new(&cmd[0])
            .args(&cmd[1..])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .pre_exec(|| {
                libc::setsid();
                Ok(())
            })
            .spawn()
    };
    if let Ok(proc_child) = spawn_res {
        let _ = fs::write(PID_FILE, proc_child.id().to_string());
    }
    0
}

pub fn run(args: &[String]) -> i32 {
    let mut ss = false;
    let mut stop = false;
    let mut run_ss = false;
    let mut delay = 0.0f64;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--ss" => ss = true,
            "--stop" => stop = true,
            "--run-ss" => run_ss = true,
            "--delay" if i + 1 < args.len() => {
                delay = args[i + 1].parse::<f64>().unwrap_or(0.0).max(0.0);
                i += 1;
            }
            s if s.starts_with("--delay=") => {
                delay = s[8..].parse::<f64>().unwrap_or(0.0).max(0.0);
            }
            _ => {}
        }
        i += 1;
    }

    if run_ss {
        return run_screensaver();
    }
    if stop {
        arreter_precedent();
        return 0;
    }
    lancer(ss, delay)
}
