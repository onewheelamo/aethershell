use crate::common::io::{read_json_value, run_cmd, run_cmd_stdout, write_json_atomic};
use crate::common::paths::{cache_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// ── maj_shell ─────────────────────────────────────────────────────────────────

const DEPOT: &str = "onewheelamo/aethershell";
const BRANCHE: &str = "master";
const INTERVALLE_MIN: i64 = 280;
const ESSAI_APRES_ECHEC_MIN: i64 = 10;

fn now_f64() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn format_local_iso_secs(epoch: f64) -> String {
    if epoch <= 0.0 {
        return String::new();
    }
    unsafe {
        let secs = epoch as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&secs, &mut tm);
        let offset = tm.tm_gmtoff;
        let sign = if offset >= 0 { '+' } else { '-' };
        let abs_off = offset.abs();
        let oh = abs_off / 3600;
        let om = (abs_off % 3600) / 60;
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}{}{:02}:{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec,
            sign,
            oh,
            om
        )
    }
}

fn version_locale() -> (String, String, String, String) {
    let fichier = core_dir().join("version.json");
    if fichier.is_file() {
        let donnee = read_json_value(&fichier);
        if let Some(m) = donnee.as_object() {
            let v = m.get("version").and_then(|x| x.as_str()).unwrap_or("");
            let t = m.get("tag").and_then(|x| x.as_str()).unwrap_or("");
            let c = m.get("commit").and_then(|x| x.as_str()).unwrap_or("");
            if !v.is_empty() || !t.is_empty() {
                return (
                    v.to_string(),
                    t.to_string(),
                    c.to_string(),
                    "déploiement".to_string(),
                );
            }
        }
    }

    if let Some(depot) = core_dir().parent().and_then(|p| p.parent()) {
        if depot.join(".git").exists() {
            let depot_s = depot.to_string_lossy().to_string();
            let git = |args: &[&str]| -> String {
                let mut full = vec!["-C", &depot_s];
                full.extend_from_slice(args);
                run_cmd_stdout("git", &full)
                    .map(|s| s.trim().to_string())
                    .unwrap_or_default()
            };
            return (
                git(&["describe", "--tags", "--always", "--dirty"]),
                git(&["describe", "--tags", "--abbrev=0"]),
                git(&["rev-parse", "--short", "HEAD"]),
                "dépôt".to_string(),
            );
        }
    }

    (
        String::new(),
        String::new(),
        String::new(),
        "absente".to_string(),
    )
}

fn interroger_github() -> (Option<String>, Option<String>) {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(8))
        .build();
    let urls = [
        format!("https://api.github.com/repos/{}/releases/latest", DEPOT),
        format!("https://api.github.com/repos/{}/tags?per_page=1", DEPOT),
    ];
    let mut dernier = "GitHub n'a pas répondu".to_string();
    let mut introuvable = 0;

    for url in &urls {
        match agent
            .get(url)
            .set("User-Agent", "aethershell-maj")
            .set("Accept", "application/vnd.github+json")
            .call()
        {
            Ok(resp) => match resp.into_json::<Value>() {
                Ok(donnee) => {
                    let tag = if let Some(obj) = donnee.as_object() {
                        obj.get("tag_name")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string()
                    } else if let Some(arr) = donnee.as_array() {
                        arr.first()
                            .and_then(|o| o.get("name"))
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string()
                    } else {
                        String::new()
                    };
                    if !tag.is_empty() {
                        return (Some(tag), None);
                    }
                    dernier = "aucune release ni tag publié".to_string();
                }
                Err(_) => return (None, Some("réponse GitHub illisible".to_string())),
            },
            Err(ureq::Error::Status(404, _)) => {
                introuvable += 1;
                dernier = if introuvable == 1 {
                    "aucune release ni tag publié".to_string()
                } else {
                    "dépôt introuvable ou privé (404 sur la release et les tags)".to_string()
                };
            }
            Err(ureq::Error::Status(code, _)) => {
                return (None, Some(format!("GitHub a répondu {}", code)));
            }
            Err(ureq::Error::Transport(_)) => {
                return (None, Some("réseau indisponible (URLError)".to_string()));
            }
        }
    }
    (None, Some(dernier))
}

fn numeros_version(version: &str) -> Option<(u64, u64, u64, u64)> {
    let re = Regex::new(r"(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?").unwrap();
    let cap = re.captures(version)?;
    let a = cap[1].parse().ok()?;
    let b = cap[2].parse().ok()?;
    let c = cap[3].parse().ok()?;
    let d = cap.get(4).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
    Some((a, b, c, d))
}

pub fn run_maj_shell(args: &[String]) -> i32 {
    let lien = format!(
        "https://raw.githubusercontent.com/{}/{}/install.sh",
        DEPOT, BRANCHE
    );
    let commande = format!("curl -fsSL {} | bash", lien);

    if args.iter().any(|a| a == "--lien") {
        println!("{}", commande);
        return 0;
    }

    let force = args.iter().any(|a| a == "--force");
    let texte = args.iter().any(|a| a == "--texte");
    let mut intervalle = INTERVALLE_MIN;
    for i in 0..args.len() {
        if args[i] == "--intervalle" && i + 1 < args.len() {
            if let Ok(v) = args[i + 1].parse::<i64>() {
                intervalle = v.max(1);
            }
        } else if let Some(v) = args[i].strip_prefix("--intervalle=") {
            if let Ok(n) = v.parse::<i64>() {
                intervalle = n.max(1);
            }
        }
    }

    let (loc_ver, loc_tag, loc_commit, loc_orig) = version_locale();
    let cache_path = cache_dir().join("quickshell").join("maj_shell.json");
    let cache = read_json_value(&cache_path);
    let maintenant = now_f64();

    let mut verifie_le = cache.get("verifie_le").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let echec_le = cache.get("echec_le").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let mut distante = cache
        .get("distante")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let mut erreur = cache
        .get("erreur")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let frais = verifie_le > 0.0 && (maintenant - verifie_le) < (intervalle * 60) as f64;
    let recent_echec =
        echec_le > 0.0 && (maintenant - echec_le) < (ESSAI_APRES_ECHEC_MIN * 60) as f64;

    if force || !(frais || recent_echec) {
        let (tag_opt, msg_opt) = interroger_github();
        if let Some(tag) = tag_opt {
            distante = tag;
            erreur.clear();
            verifie_le = maintenant;
            let _ = write_json_atomic(
                &cache_path,
                &json!({ "verifie_le": verifie_le, "distante": distante }),
                0o644,
            );
        } else {
            erreur = msg_opt.unwrap_or_else(|| "GitHub n'a pas répondu".to_string());
            let _ = write_json_atomic(
                &cache_path,
                &json!({
                    "verifie_le": verifie_le,
                    "distante": distante,
                    "erreur": erreur,
                    "echec_le": maintenant,
                }),
                0o644,
            );
        }
    }

    let locale_txt = if !loc_ver.is_empty() {
        loc_ver.clone()
    } else {
        loc_tag.clone()
    };
    let num_locale = numeros_version(if !loc_tag.is_empty() {
        &loc_tag
    } else {
        &locale_txt
    });
    let num_distante = numeros_version(&distante);

    let (etat, detail) = if distante.is_empty() {
        (
            "inconnu",
            if erreur.is_empty() {
                "version publiée inconnue".to_string()
            } else {
                erreur.clone()
            },
        )
    } else if num_locale.is_none() {
        (
            "inconnu",
            "version locale illisible — relance l'installateur pour la réécrire".to_string(),
        )
    } else if num_distante.is_none() {
        ("inconnu", format!("tag publié illisible ({})", distante))
    } else if num_distante > num_locale {
        ("disponible", format!("{} est publiée sur GitHub", distante))
    } else {
        let mut d = "tu as la dernière version publiée".to_string();
        if num_distante < num_locale {
            d.push_str(" (ton clone est en avance sur le dernier tag)");
        }
        ("a_jour", d)
    };

    let verif_str = format_local_iso_secs(verifie_le);
    let il_y_a_min = if verifie_le > 0.0 {
        Some(((maintenant - verifie_le) / 60.0).round() as i64)
    } else {
        None
    };

    if texte {
        let marque = match etat {
            "a_jour" => "✓",
            "disponible" => "↑",
            _ => "?",
        };
        let loc_aff = if locale_txt.is_empty() {
            "version inconnue"
        } else {
            &locale_txt
        };
        println!("{} {} — {}", marque, loc_aff, detail);
        if !distante.is_empty() {
            println!("  publiée : {}", distante);
        }
        if !verif_str.is_empty() {
            println!("  vérifié  : {} (toutes les {} min)", verif_str, intervalle);
        }
        println!("  installer / mettre à jour : {}", commande);
        return 0;
    }

    println!(
        "{}",
        json!({
            "etat": etat,
            "locale": locale_txt,
            "locale_tag": loc_tag,
            "commit": loc_commit,
            "origine": loc_orig,
            "distante": distante,
            "detail": detail,
            "erreur": erreur,
            "verifie_le": verif_str,
            "il_y_a_min": il_y_a_min,
            "intervalle_min": intervalle,
            "commande": commande,
            "lien": lien,
        })
    );
    0
}

// ── deps_install ──────────────────────────────────────────────────────────────

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

fn pkg_for_bin<'a>(distro: &str, bin: &'a str) -> &'a str {
    match (distro, bin) {
        ("arch", "wpctl") => "wireplumber",
        ("arch", "nmcli") => "networkmanager",
        ("arch", "magick") => "imagemagick",
        ("arch", "inotifywait") => "inotify-tools",
        ("arch", "notify-send") => "libnotify",
        ("arch", "pactl") => "libpulse",
        ("arch", "powerprofilesctl") => "power-profiles-daemon",
        ("arch", "monitor-sensor") => "iio-sensor-proxy",
        ("arch", "cc") => "gcc",
        ("arch", "wl-copy") => "wl-clipboard",
        ("arch", "bluetoothctl") => "bluez-utils",
        ("arch", "udisksctl") => "udisks2",
        ("arch", "zbarcam") => "zbar",
        ("arch", "matugen") => "matugen-bin",
        ("arch", "unimatrix") => "unimatrix-git",

        ("fedora", "wpctl") => "wireplumber",
        ("fedora", "nmcli") => "NetworkManager",
        ("fedora", "powerprofilesctl") => "power-profiles-daemon",
        ("fedora", "monitor-sensor") => "iio-sensor-proxy",
        ("fedora", "magick") => "ImageMagick",
        ("fedora", "inotifywait") => "inotify-tools",
        ("fedora", "notify-send") => "libnotify",
        ("fedora", "pactl") => "pulseaudio-utils",
        ("fedora", "cc") => "gcc",
        ("fedora", "wl-copy") => "wl-clipboard",
        ("fedora", "bluetoothctl") => "bluez",
        ("fedora", "udisksctl") => "udisks2",
        ("fedora", "zbarcam") => "zbar",

        ("debian", "wpctl") => "wireplumber",
        ("debian", "nmcli") => "network-manager",
        ("debian", "powerprofilesctl") => "power-profiles-daemon",
        ("debian", "monitor-sensor") => "iio-sensor-proxy",
        ("debian", "magick") => "imagemagick",
        ("debian", "inotifywait") => "inotify-tools",
        ("debian", "notify-send") => "libnotify-bin",
        ("debian", "pactl") => "pulseaudio-utils",
        ("debian", "cc") => "gcc",
        ("debian", "wl-copy") => "wl-clipboard",
        ("debian", "bluetoothctl") => "bluez",
        ("debian", "udisksctl") => "udisks2",
        ("debian", "zbarcam") => "zbar-tools",
        _ => bin,
    }
}

fn is_aur_pkg(p: &str) -> bool {
    matches!(
        p,
        "quickshell" | "matugen-bin" | "awww" | "hyprshot" | "hyprsunset" | "unimatrix-git"
    )
}

fn distribution() -> String {
    let Ok(texte) = fs::read_to_string("/etc/os-release") else {
        return "inconnue".to_string();
    };
    let mut ident = String::new();
    let mut id_like = String::new();
    for ligne in texte.lines() {
        if let Some((k, v)) = ligne.split_once('=') {
            let clean = v.trim().trim_matches('"').to_ascii_lowercase();
            match k.trim() {
                "ID" => ident = clean,
                "ID_LIKE" => id_like = clean,
                _ => {}
            }
        }
    }
    if matches!(ident.as_str(), "arch" | "fedora") {
        return ident;
    }
    if matches!(
        ident.as_str(),
        "debian" | "ubuntu" | "linuxmint" | "pop" | "elementary" | "zorin" | "kali"
    ) {
        return "debian".to_string();
    }
    if id_like.contains("arch") {
        return "arch".to_string();
    }
    if id_like.contains("fedora") || matches!(ident.as_str(), "rhel" | "centos") {
        return "fedora".to_string();
    }
    if id_like.contains("debian") || id_like.contains("ubuntu") {
        return "debian".to_string();
    }
    if ident.is_empty() {
        "inconnue".to_string()
    } else {
        ident
    }
}

fn forme_poste() -> &'static str {
    if let Ok(rd) = fs::read_dir("/sys/class/power_supply") {
        if rd
            .flatten()
            .any(|e| e.file_name().to_str().map(|s| s.starts_with("BAT")).unwrap_or(false))
        {
            return "laptop";
        }
    }
    if let Ok(ct) = fs::read_to_string("/sys/class/dmi/id/chassis_type") {
        if matches!(ct.trim(), "8" | "9" | "10" | "14" | "30" | "31" | "32") {
            return "laptop";
        }
    }
    "desktop"
}

fn binaires_requis(deps_path: &Path, distro: &str) -> Vec<String> {
    let Ok(txt) = fs::read_to_string(deps_path) else {
        return vec![];
    };
    let forme = forme_poste();
    let mut portees = HashSet::new();
    portees.insert("commun");
    portees.insert(distro);
    if forme == "laptop" {
        portees.insert("laptop");
        portees.insert("portable");
    } else {
        portees.insert("desktop");
        portees.insert("fixe");
    }

    let scope_re = Regex::new(r"^#:\s*(\w+)").unwrap();
    let mut courante = String::new();
    let mut gardes = Vec::new();
    for ligne in txt.lines() {
        let t = ligne.trim();
        if t.is_empty() || (t.starts_with('#') && !t.starts_with("#:")) {
            continue;
        }
        if let Some(cap) = scope_re.captures(t) {
            courante = cap[1].to_ascii_lowercase();
            continue;
        }
        if portees.contains(courante.as_str()) {
            if let Some(b) = t.split_whitespace().next() {
                gardes.push(b.to_string());
            }
        }
    }
    gardes
}

fn binaire_present(binaire: &str, distro: &str) -> bool {
    if which_exists(binaire) {
        return true;
    }
    binaire == "magick" && distro == "debian" && which_exists("convert")
}

fn installer_unimatrix_local() -> bool {
    let cible = home_dir().join(".local/bin/unimatrix");
    if let Some(p) = cible.parent() {
        let _ = fs::create_dir_all(p);
    }
    let url = "https://raw.githubusercontent.com/will8211/unimatrix/master/unimatrix.py";
    let cible_s = cible.to_string_lossy().to_string();
    let ok = run_cmd("curl", &["-fsSL", url, "-o", &cible_s])
        .map(|o| o.status.success())
        .unwrap_or(false);
    if !ok {
        return false;
    }
    let _ = fs::set_permissions(&cible, fs::Permissions::from_mode(0o755));
    true
}

pub fn run_deps_install(_args: &[String]) -> i32 {
    let deps_path = core_dir().join("dependencies.txt");
    if !deps_path.is_file() {
        println!("dependencies.txt introuvable : {}", deps_path.display());
        return 2;
    }
    let distro = distribution();
    let mut manquants: Vec<String> = binaires_requis(&deps_path, &distro)
        .into_iter()
        .filter(|b| !binaire_present(b, &distro))
        .collect();
    if manquants.is_empty() {
        println!("tout est installé");
        return 0;
    }
    if distro != "arch" && manquants.iter().any(|b| b == "unimatrix") && installer_unimatrix_local() {
        manquants.retain(|b| b != "unimatrix");
        if manquants.is_empty() {
            println!("installés : unimatrix");
            return 0;
        }
    }

    let mut seen = HashSet::new();
    let mut paquets = Vec::new();
    for b in &manquants {
        let p = pkg_for_bin(&distro, b).to_string();
        if seen.insert(p.clone()) {
            paquets.push(p);
        }
    }

    let mut cmd: Vec<String> = match distro.as_str() {
        "fedora" => vec!["dnf".into(), "install".into(), "-y".into()],
        "debian" => vec!["apt-get".into(), "install".into(), "-y".into()],
        "arch" if paquets.iter().any(|p| is_aur_pkg(p)) => {
            if which_exists("yay") {
                vec!["yay".into(), "-S".into(), "--needed".into(), "--noconfirm".into()]
            } else if which_exists("paru") {
                vec!["paru".into(), "-S".into(), "--needed".into(), "--noconfirm".into()]
            } else {
                vec!["pacman".into(), "-S".into(), "--needed".into(), "--noconfirm".into()]
            }
        }
        _ => vec!["pacman".into(), "-S".into(), "--needed".into(), "--noconfirm".into()],
    };
    cmd.extend(paquets.clone());
    println!("manquants : {}", manquants.join(", "));

    let besoin_pkexec = !matches!(cmd[0].as_str(), "yay" | "paru");
    if besoin_pkexec && !which_exists("pkexec") {
        println!("pkexec absent — à lancer à la main : sudo {}", cmd.join(" "));
        return 2;
    }

    let mut exec_cmd = if besoin_pkexec {
        let mut c = vec!["pkexec".to_string()];
        c.extend(cmd);
        c
    } else {
        cmd
    };
    let prog = exec_cmd.remove(0);
    match Command::new(&prog).args(&exec_cmd).status() {
        Ok(st) if st.success() => {}
        Ok(st) => {
            println!("installation interrompue (code {})", st.code().unwrap_or(1));
            return 1;
        }
        Err(_) => {
            println!("installation interrompue (code 1)");
            return 1;
        }
    }

    let restants: Vec<String> = binaires_requis(&deps_path, &distro)
        .into_iter()
        .filter(|b| !binaire_present(b, &distro))
        .collect();
    if !restants.is_empty() {
        println!("encore absents : {}", restants.join(", "));
        return 1;
    }
    println!("installés : {}", paquets.join(", "));
    0
}
