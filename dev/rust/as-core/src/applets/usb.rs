use crate::common::contrat::{compact, presenter, sortir};
use crate::common::io::{parse_options_arg, read_json_value};
use crate::common::paths::{core_dir, runtime_dir};
use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::Path;
use std::process::{Command, Stdio};

const SYSTEME: &[&str] = &["/", "/boot", "/boot/efi", "/home", "/var", "/usr", "/etc", "/nix"];
const TAILLE_MIN: u64 = 1024 * 1024;

fn which_exists(prog: &str) -> bool {
    if prog.is_empty() {
        return false;
    }
    if prog.contains('/') {
        return Path::new(prog).is_file();
    }
    if let Some(paths) = env::var_os("PATH") {
        for dir in env::split_paths(&paths) {
            let p = dir.join(prog);
            if p.is_file() {
                return true;
            }
        }
    }
    false
}

fn lire_trim(chemin: &str) -> String {
    fs::read_to_string(chemin)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

fn lire_u64(chemin: &str, defaut: u64) -> u64 {
    lire_trim(chemin).parse::<u64>().unwrap_or(defaut)
}

fn decoder_udev(valeur: &str) -> String {
    if valeur.is_empty() {
        return String::new();
    }
    let bytes = valeur.as_bytes();
    let mut out = String::with_capacity(valeur.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 3 < bytes.len() && bytes[i + 1] == b'x' {
            if let Ok(hex) = std::str::from_utf8(&bytes[i + 2..i + 4]) {
                if let Ok(code) = u8::from_str_radix(hex, 16) {
                    out.push(code as char);
                    i += 4;
                    continue;
                }
            }
        }
        if let Some(ch) = valeur[i..].chars().next() {
            out.push(ch);
            i += ch.len_utf8();
        } else {
            break;
        }
    }
    out
}

fn proprietes_udev(majmin: &str) -> HashMap<String, String> {
    let mut props = HashMap::new();
    let txt = lire_trim(&format!("/run/udev/data/b{}", majmin));
    for ligne in txt.lines() {
        if let Some(rest) = ligne.strip_prefix("E:") {
            if let Some((cle, val)) = rest.split_once('=') {
                if !cle.is_empty() {
                    props.insert(cle.to_string(), val.to_string());
                }
            }
        }
    }
    props
}

fn montages() -> HashMap<(u32, u32), String> {
    let mut trouves = HashMap::new();
    let Ok(txt) = fs::read_to_string("/proc/self/mountinfo") else {
        return trouves;
    };
    for ligne in txt.lines() {
        let morceaux: Vec<&str> = ligne.split_whitespace().collect();
        if morceaux.len() < 5 {
            continue;
        }
        if let Some((maj_s, min_s)) = morceaux[2].split_once(':') {
            if let (Ok(maj), Ok(min)) = (maj_s.parse::<u32>(), min_s.parse::<u32>()) {
                let point = morceaux[4].replace("\\040", " ");
                trouves.insert((maj, min), point);
            }
        }
    }
    trouves
}

fn echanges() -> HashSet<String> {
    let mut trouves = HashSet::new();
    let Ok(txt) = fs::read_to_string("/proc/swaps") else {
        return trouves;
    };
    for ligne in txt.lines().skip(1) {
        let mut morceaux = ligne.split_whitespace();
        if let Some(dev) = morceaux.next() {
            if dev.starts_with("/dev/") {
                if let Ok(real) = fs::canonicalize(dev) {
                    if let Some(name) = real.file_name().and_then(|s| s.to_str()) {
                        trouves.insert(name.to_string());
                    }
                } else if let Some(name) = dev.rsplit('/').next() {
                    trouves.insert(name.to_string());
                }
            }
        }
    }
    trouves
}

fn majmin(nom: &str) -> Option<(u32, u32)> {
    let meta = fs::metadata(format!("/dev/{}", nom)).ok()?;
    let rdev = meta.rdev();
    Some((libc::major(rdev), libc::minor(rdev)))
}

fn est_disque(nom: &str) -> bool {
    if !(nom.starts_with("sd") || nom.starts_with("mmcblk") || nom.starts_with("sr")) {
        return false;
    }
    Path::new(&format!("/sys/block/{}", nom)).is_dir()
}

fn enfants(nom: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(format!("/sys/block/{}", nom)) {
        for ent in rd.flatten() {
            if let Some(s) = ent.file_name().to_str() {
                if s.starts_with(nom) {
                    out.push(s.to_string());
                }
            }
        }
    }
    out.sort();
    out
}

fn titulaire(nom: &str) -> String {
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(format!("/sys/class/block/{}/holders", nom)) {
        for ent in rd.flatten() {
            if let Some(s) = ent.file_name().to_str() {
                out.push(s.to_string());
            }
        }
    }
    out.sort();
    out.into_iter().next().unwrap_or_default()
}

fn volume(
    nom: &str,
    mounts: &HashMap<(u32, u32), String>,
    swaps: &HashSet<String>,
) -> Value {
    let mm = majmin(nom);
    let props = mm
        .map(|(ma, mi)| proprietes_udev(&format!("{}:{}", ma, mi)))
        .unwrap_or_default();
    let dev = format!("/dev/{}", nom);
    let taille = lire_u64(&format!("/sys/class/block/{}/size", nom), 0) * 512;
    let fs_type = props.get("ID_FS_TYPE").cloned().unwrap_or_default();
    let mut etiquette = decoder_udev(
        props
            .get("ID_FS_LABEL_ENC")
            .or_else(|| props.get("ID_FS_LABEL"))
            .map(|s| s.as_str())
            .unwrap_or(""),
    );
    let chiffre = fs_type == "crypto_LUKS";
    let clair = if chiffre { titulaire(nom) } else { String::new() };
    let mut montage = mm
        .and_then(|k| mounts.get(&k).cloned())
        .unwrap_or_default();
    if !clair.is_empty() {
        let mm_clair = majmin(&clair);
        let props_clair = mm_clair
            .map(|(ma, mi)| proprietes_udev(&format!("{}:{}", ma, mi)))
            .unwrap_or_default();
        if let Some(mc) = mm_clair {
            if let Some(mp) = mounts.get(&mc) {
                if !mp.is_empty() {
                    montage = mp.clone();
                }
            }
        }
        if etiquette.is_empty() {
            etiquette = decoder_udev(
                props_clair
                    .get("ID_FS_LABEL_ENC")
                    .or_else(|| props_clair.get("ID_FS_LABEL"))
                    .map(|s| s.as_str())
                    .unwrap_or(""),
            );
        }
    }
    let echange = swaps.contains(nom) || (!clair.is_empty() && swaps.contains(&clair));
    json!({
        "dev": dev,
        "nom": nom,
        "etiquette": etiquette,
        "fs": fs_type,
        "taille_o": taille,
        "montage": montage,
        "chiffre": chiffre,
        "ouvert": !clair.is_empty(),
        "dev_clair": if clair.is_empty() { String::new() } else { format!("/dev/{}", clair) },
        "echange": echange,
    })
}

fn bus_name(props: &HashMap<String, String>) -> String {
    let bus = props
        .get("ID_BUS")
        .map(|s| s.to_ascii_lowercase())
        .unwrap_or_default();
    if bus == "usb" {
        "usb".to_string()
    } else if bus.is_empty() {
        "?".to_string()
    } else {
        bus
    }
}

fn peripheriques() -> Vec<Value> {
    let mounts = montages();
    let swaps = echanges();
    let mut entrees = Vec::new();
    if let Ok(rd) = fs::read_dir("/sys/block") {
        for ent in rd.flatten() {
            if let Some(s) = ent.file_name().to_str() {
                entrees.push(s.to_string());
            }
        }
    }
    entrees.sort();

    let mut disques = Vec::new();
    for nom in entrees {
        if !est_disque(&nom) {
            continue;
        }
        let mm = majmin(&nom);
        let props = mm
            .map(|(ma, mi)| proprietes_udev(&format!("{}:{}", ma, mi)))
            .unwrap_or_default();
        let optique =
            lire_trim(&format!("/sys/block/{}/device/type", nom)) == "5" || nom.starts_with("sr");
        let amovible = lire_u64(&format!("/sys/block/{}/removable", nom), 0) == 1;
        let bus = bus_name(&props);
        if !(amovible || optique || bus == "usb") {
            continue;
        }
        let volumes: Vec<Value> = enfants(&nom)
            .into_iter()
            .map(|e| volume(&e, &mounts, &swaps))
            .filter(|v| {
                v.get("taille_o").and_then(|x| x.as_u64()).unwrap_or(0) > 0
                    || !v.get("fs").and_then(|x| x.as_str()).unwrap_or("").is_empty()
                    || !v.get("montage").and_then(|x| x.as_str()).unwrap_or("").is_empty()
            })
            .collect();
        let taille = lire_u64(&format!("/sys/block/{}/size", nom), 0) * 512;
        if taille < TAILLE_MIN && volumes.is_empty() {
            continue;
        }
        let modele = decoder_udev(
            props
                .get("ID_MODEL_ENC")
                .or_else(|| props.get("ID_MODEL"))
                .map(|s| s.as_str())
                .unwrap_or(&nom),
        );
        let monte = volumes
            .iter()
            .any(|v| !v.get("montage").and_then(|x| x.as_str()).unwrap_or("").is_empty());
        let systeme = volumes.iter().any(|v| {
            let mp = v.get("montage").and_then(|x| x.as_str()).unwrap_or("");
            SYSTEME.contains(&mp)
        });
        disques.push(json!({
            "nom": nom,
            "modele": modele,
            "bus": bus,
            "amovible": amovible,
            "optique": optique,
            "taille_o": taille,
            "volumes": volumes,
            "monte": monte,
            "systeme": systeme,
        }));
    }
    disques
}

fn vrai_opt(val: Option<&Value>, defaut: bool) -> bool {
    match val {
        None | Some(Value::Null) => defaut,
        Some(Value::Bool(b)) => *b,
        Some(v) => {
            let s = match v.as_str() {
                Some(s) => s.to_string(),
                None => v.to_string(),
            };
            !matches!(s.trim().to_ascii_lowercase().as_str(), "false" | "0" | "non" | "")
        }
    }
}

fn analyser(options: &Map<String, Value>) -> Map<String, Value> {
    let disques = peripheriques();
    let masquer = vrai_opt(options.get("masquer_vide"), true);
    let montes: Vec<&Value> = disques
        .iter()
        .filter(|d| d.get("monte").and_then(|x| x.as_bool()).unwrap_or(false))
        .collect();
    let mut map = Map::new();
    map.insert("ok".to_string(), Value::Bool(true));
    if disques.is_empty() {
        let c = compact(
            if masquer { "" } else { "0" },
            "aucun périphérique",
            false,
            0,
            None,
        );
        map.insert("compact".to_string(), c);
        map.insert("disques".to_string(), Value::Array(vec![]));
        map.insert("vide".to_string(), Value::Bool(true));
        map.insert("masque".to_string(), Value::Bool(masquer));
        return map;
    }
    let valeur = disques.len().to_string();
    let mut libelle = format!(
        "{} périphérique{}",
        disques.len(),
        if disques.len() > 1 { "s" } else { "" }
    );
    if !montes.is_empty() && disques.len() == 1 {
        if let Some(vols) = montes[0].get("volumes").and_then(|v| v.as_array()) {
            if let Some(v0) = vols.first() {
                let etiq = v0.get("etiquette").and_then(|s| s.as_str()).unwrap_or("");
                if !etiq.is_empty() {
                    libelle = etiq.to_string();
                }
            }
        }
    }
    let nb_montes = montes.len();
    map.insert("compact".to_string(), compact(&valeur, &libelle, false, 0, None));
    map.insert("disques".to_string(), Value::Array(disques));
    map.insert("vide".to_string(), Value::Bool(false));
    map.insert("masque".to_string(), Value::Bool(masquer));
    map.insert("montes".to_string(), json!(nb_montes));
    map
}

fn udisks(args: &[&str]) -> (bool, String) {
    if !which_exists("udisksctl") {
        return (false, "udisksctl absent (paquet udisks2)".to_string());
    }
    match Command::new("udisksctl").args(args).output() {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
            if out.status.success() {
                (true, stdout)
            } else {
                let msg = if !stderr.is_empty() {
                    stderr
                } else if !stdout.is_empty() {
                    stdout
                } else {
                    "échec".to_string()
                };
                (false, msg)
            }
        }
        Err(e) => (false, e.to_string()),
    }
}

fn dev_effectif(dev: &str) -> String {
    let nom = Path::new(dev)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    let clair = if nom.is_empty() {
        String::new()
    } else {
        titulaire(nom)
    };
    if clair.is_empty() {
        dev.to_string()
    } else {
        format!("/dev/{}", clair)
    }
}

fn monter(dev: &str) -> (bool, String) {
    let eff = dev_effectif(dev);
    udisks(&["mount", "-b", &eff])
}

fn demonter(dev: &str) -> (bool, String) {
    let eff = dev_effectif(dev);
    udisks(&["unmount", "-b", &eff])
}

fn gestionnaire() -> String {
    let apps = read_json_value(&core_dir().join("app_vars.json"));
    let configure = apps
        .get("Files")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();
    for cand in [
        configure.as_str(),
        "thunar",
        "nemo",
        "nautilus",
        "dolphin",
        "pcmanfm",
    ] {
        if !cand.is_empty() && which_exists(cand) {
            return cand.to_string();
        }
    }
    "xdg-open".to_string()
}

fn ouvrir(chemin: &str) -> (bool, String) {
    if chemin.is_empty() || !Path::new(chemin).is_dir() {
        return (false, "dossier introuvable".to_string());
    }
    let mgr = gestionnaire();
    let res = Command::new(&mgr)
        .arg(chemin)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    match res {
        Ok(_) => (true, format!("{} {}", mgr, chemin)),
        Err(e) => (false, e.to_string()),
    }
}

fn verrouiller(dev: &str) -> (bool, String) {
    let nom = Path::new(dev)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    let clair = if nom.is_empty() {
        String::new()
    } else {
        titulaire(nom)
    };
    if !clair.is_empty() {
        if let Some(mm_clair) = majmin(&clair) {
            if montages().contains_key(&mm_clair) {
                let target = format!("/dev/{}", clair);
                let (ok, msg) = udisks(&["unmount", "-b", &target]);
                if !ok {
                    return (false, msg);
                }
            }
        }
    }
    udisks(&["lock", "-b", dev])
}

fn deverrouiller(dev: &str, phrase_in: &str, fichier_phrase: &str) -> (bool, String) {
    let mut phrase = phrase_in.to_string();
    if !fichier_phrase.is_empty() {
        let res = fs::read_to_string(fichier_phrase);
        let _ = fs::remove_file(fichier_phrase);
        match res {
            Ok(txt) => phrase = txt.trim_end_matches(&['\r', '\n'][..]).to_string(),
            Err(e) => return (false, e.to_string()),
        }
    }
    if phrase.is_empty() {
        return (false, "phrase absente".to_string());
    }
    if !which_exists("udisksctl") {
        return (false, "udisksctl absent (paquet udisks2)".to_string());
    }
    let chemin = runtime_dir().join(format!("quickshell-luks-{}", std::process::id()));
    let write_res = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&chemin)
        .and_then(|mut f| f.write_all(phrase.as_bytes()));
    if let Err(e) = write_res {
        let _ = fs::remove_file(&chemin);
        return (false, e.to_string());
    }
    let chemin_str = chemin.to_string_lossy().to_string();
    let res = udisks(&["unlock", "-b", dev, "--key-file", &chemin_str]);
    let _ = fs::remove_file(&chemin);
    res
}

fn chemin_disque(nom_disque: &str) -> String {
    let target = format!("/dev/{}", nom_disque);
    let (ok, sortie) = udisks(&["info", "-b", &target]);
    if !ok {
        return String::new();
    }
    for ligne in sortie.lines() {
        let t = ligne.trim();
        if let Some(rest) = t.strip_prefix("Drive:") {
            return rest.trim().trim_matches('\'').to_string();
        }
    }
    String::new()
}

fn retirer(nom_disque: &str) -> (bool, String) {
    let target = format!("/dev/{}", nom_disque);
    let (ok, message) = udisks(&["power-off", "-b", &target, "--no-user-interaction"]);
    if ok {
        return (
            true,
            if message.is_empty() {
                "retiré".to_string()
            } else {
                message
            },
        );
    }
    let low = message.to_ascii_lowercase();
    if low.contains("mount") || low.contains("monté") {
        return (false, message);
    }
    let chemin = chemin_disque(nom_disque);
    if !chemin.is_empty() && which_exists("gdbus") {
        match Command::new("gdbus")
            .args([
                "call",
                "--system",
                "--dest",
                "org.freedesktop.UDisks2",
                "--object-path",
                &chemin,
                "--method",
                "org.freedesktop.UDisks2.Drive.Eject",
                "{}",
            ])
            .output()
        {
            Ok(out) => {
                if out.status.success() {
                    return (true, "éjecté".to_string());
                }
                let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
                return (false, if err.is_empty() { message } else { err });
            }
            Err(e) => return (false, e.to_string()),
        }
    }
    (false, message)
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("");
    if action == "ouvrir" && args.len() > 1 {
        let (ok, message) = ouvrir(&args[1]);
        println!("{}", json!({ "ok": ok, "message": message }));
        return if ok { 0 } else { 1 };
    }
    if matches!(
        action,
        "monter" | "demonter" | "verrouiller" | "deverrouiller" | "retirer"
    ) && args.len() > 1
    {
        let cible = &args[1];
        let (ok, message) = match action {
            "monter" => monter(cible),
            "demonter" => demonter(cible),
            "verrouiller" => verrouiller(cible),
            "deverrouiller" => {
                let mut fichier_phrase = "";
                let mut phrase = "";
                for i in 0..args.len() {
                    if args[i] == "--fichier-phrase" && i + 1 < args.len() {
                        fichier_phrase = &args[i + 1];
                    } else if args[i] == "--phrase" && i + 1 < args.len() {
                        phrase = &args[i + 1];
                    }
                }
                if phrase.is_empty() && fichier_phrase.is_empty() {
                    println!("{}", json!({ "ok": false, "erreur": "phrase absente" }));
                    return 2;
                }
                deverrouiller(cible, phrase, fichier_phrase)
            }
            _ => retirer(cible),
        };
        println!("{}", json!({ "ok": ok, "message": message }));
        return if ok { 0 } else { 1 };
    }

    let options = parse_options_arg(args);
    let donnees = analyser(&options);
    let cmp = donnees.get("compact").cloned().unwrap_or(Value::Null);
    let out = presenter(donnees, "usb", "usb", Some(cmp), None, None, None, None);
    sortir(&out)
}
