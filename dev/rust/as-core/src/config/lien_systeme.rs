use crate::common::io::{read_json_value, run_cmd};
use crate::common::paths::{config_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

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

fn data_dir() -> PathBuf {
    env::var("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".local/share"))
}

fn helpers_path() -> PathBuf {
    config_dir().join("xfce4").join("helpers.rc")
}

fn aides_dir() -> PathBuf {
    data_dir().join("xfce4").join("helpers")
}

fn mimeapps_path() -> PathBuf {
    config_dir().join("mimeapps.list")
}

fn desktop_dirs() -> Vec<PathBuf> {
    let h = home_dir();
    vec![
        h.join(".local/share/applications"),
        PathBuf::from("/usr/share/applications"),
        PathBuf::from("/var/lib/flatpak/exports/share/applications"),
        h.join(".local/share/flatpak/exports/share/applications"),
    ]
}

struct RoleDef {
    role: &'static str,
    exo: Option<&'static str>,
    mimes: &'static [&'static str],
    categories: &'static [&'static str],
}

const ROLES: &[RoleDef] = &[
    RoleDef {
        role: "Terminal",
        exo: Some("TerminalEmulator"),
        mimes: &["application/x-terminal-emulator"],
        categories: &["TerminalEmulator"],
    },
    RoleDef {
        role: "Files",
        exo: Some("FileManager"),
        mimes: &["inode/directory"],
        categories: &["FileManager"],
    },
    RoleDef {
        role: "Browser",
        exo: Some("WebBrowser"),
        mimes: &[
            "x-scheme-handler/http",
            "x-scheme-handler/https",
            "text/html",
            "application/xhtml+xml",
        ],
        categories: &["WebBrowser"],
    },
    RoleDef {
        role: "Browser2",
        exo: None,
        mimes: &["x-scheme-handler/http", "x-scheme-handler/https"],
        categories: &["WebBrowser"],
    },
    RoleDef {
        role: "Editor",
        exo: Some("TextEditor"),
        mimes: &["text/plain"],
        categories: &["TextEditor", "Development"],
    },
    RoleDef {
        role: "Video",
        exo: Some("VideoPlayer"),
        mimes: &[
            "video/mp4",
            "video/x-matroska",
            "video/webm",
            "video/quicktime",
        ],
        categories: &["Player", "Video"],
    },
    RoleDef {
        role: "Music",
        exo: Some("AudioPlayer"),
        mimes: &["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav"],
        categories: &["Audio", "Player"],
    },
    RoleDef {
        role: "Images",
        exo: Some("ImageViewer"),
        mimes: &[
            "image/png",
            "image/jpeg",
            "image/webp",
            "image/gif",
            "image/svg+xml",
        ],
        categories: &["Viewer", "Graphics"],
    },
];

fn options_dossier(binaire: &str) -> Option<&'static str> {
    match binaire {
        "ghostty" | "alacritty" | "foot" | "gnome-terminal" | "xfce4-terminal"
        | "terminator" | "tilix" | "kgx" | "ptyxis" => Some("--working-directory=\"$PWD\""),
        "kitty" => Some("--directory=\"$PWD\""),
        "konsole" => Some("--workdir \"$PWD\""),
        "urxvt" => Some("-cd \"$PWD\""),
        "wezterm" => Some("start --cwd \"$PWD\""),
        _ => None,
    }
}

fn sans_instance_unique(binaire: &str) -> &'static str {
    match binaire {
        "ghostty" => "--gtk-single-instance=false",
        "ptyxis" | "kgx" => "--new-window",
        "gnome-terminal" => "--window",
        _ => "",
    }
}

fn ecrire_lanceur(binaire: &str) -> Option<PathBuf> {
    let arguments = options_dossier(binaire)?;
    let dossier = home_dir().join(".local/bin");
    let _ = fs::create_dir_all(&dossier);
    let chemin = dossier.join(format!("terminal-{}", binaire));
    let extra = sans_instance_unique(binaire);
    let script = format!(
        "#!/bin/sh\n\
# Lanceur généré par core/lien_systeme.py — ne pas éditer à la main.\n\
binaire={binaire}\n\
drapeaux='{extra}'\n\
\n\
if [ -n \"${{1:-}}\" ] && [ -d \"$1\" ]; then\n\
    cd \"$1\" || true\n\
    shift\n\
    if [ -n \"$LIEN_DRY_RUN\" ]; then\n\
        echo \"$binaire\" $drapeaux {arguments} \"$@\"\n\
        pwd\n\
        exit 0\n\
    fi\n\
    exec \"$binaire\" $drapeaux {arguments} \"$@\"\n\
fi\n\
\n\
if [ -n \"$LIEN_DRY_RUN\" ]; then\n\
    echo \"$binaire\" $drapeaux \"$@\"\n\
    exit 0\n\
fi\n\
exec \"$binaire\" $drapeaux \"$@\"\n"
    );
    if fs::write(&chemin, script).is_ok() {
        let _ = fs::set_permissions(&chemin, fs::Permissions::from_mode(0o755));
        return Some(chemin);
    }
    None
}

struct DesktopEntry {
    id: String,
    nom: String,
    exec: String,
    categories: Vec<String>,
}

fn lire_desktop(chemin: &Path) -> Option<DesktopEntry> {
    let texte = fs::read_to_string(chemin).ok()?;
    let (_, rest) = texte.split_once("[Desktop Entry]")?;
    let corps = rest.split("\n[").next().unwrap_or(rest);
    let mut champs: HashMap<String, String> = HashMap::new();
    for ligne in corps.lines() {
        let trimmed = ligne.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        if let Some((cle, val)) = ligne.split_once('=') {
            champs
                .entry(cle.trim().to_string())
                .or_insert_with(|| val.trim().to_string());
        }
    }
    if champs
        .get("NoDisplay")
        .map(|s| s.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
        || champs
            .get("Hidden")
            .map(|s| s.eq_ignore_ascii_case("true"))
            .unwrap_or(false)
    {
        return None;
    }
    if champs.get("Type").map(|s| s.as_str()).unwrap_or("Application") != "Application" {
        return None;
    }
    let id = chemin.file_name()?.to_str()?.to_string();
    let nom = champs.get("Name").cloned().unwrap_or_default();
    let exec = champs.get("Exec").cloned().unwrap_or_default();
    let categories = champs
        .get("Categories")
        .map(|s| s.split(';').filter(|c| !c.is_empty()).map(|c| c.to_string()).collect())
        .unwrap_or_default();
    Some(DesktopEntry {
        id,
        nom,
        exec,
        categories,
    })
}

fn tous_desktop() -> Vec<DesktopEntry> {
    let mut vus = Vec::new();
    for dossier in desktop_dirs() {
        if !dossier.is_dir() {
            continue;
        }
        let Ok(rd) = fs::read_dir(&dossier) else {
            continue;
        };
        let mut paths: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().and_then(|s| s.to_str()) == Some("desktop"))
            .collect();
        paths.sort();
        for p in paths {
            if let Some(e) = lire_desktop(&p) {
                vus.push(e);
            }
        }
    }
    vus
}

fn exec_basename(exec: &str) -> String {
    let re = Regex::new(r"[\s/]").unwrap();
    let clean = exec.replace('"', "");
    let first = re.split(clean.trim()).next().unwrap_or("");
    Path::new(first)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string()
}

fn resoudre<'a>(
    nom_in: &str,
    categories: &[&str],
    entrees: &'a [DesktopEntry],
) -> Option<&'a DesktopEntry> {
    let nom = nom_in.trim().to_ascii_lowercase();
    if nom.is_empty() {
        return None;
    }
    let mut cands: Vec<&DesktopEntry> = Vec::new();
    for e in entrees {
        let eb = exec_basename(&e.exec).to_ascii_lowercase();
        let ident = e.id.to_ascii_lowercase();
        let ident_stem = ident.strip_suffix(".desktop").unwrap_or(&ident);
        if nom == eb
            || nom == ident_stem
            || ident_stem.ends_with(&format!(".{}", nom))
            || ident_stem.ends_with(&format!("-{}", nom))
        {
            cands.push(e);
        }
    }
    if cands.is_empty() {
        for e in entrees {
            if nom == e.nom.to_ascii_lowercase() {
                cands.push(e);
            }
        }
    }
    if cands.is_empty() && nom.len() >= 4 {
        for e in entrees {
            let ident = e.id.to_ascii_lowercase();
            let ident_stem = ident.strip_suffix(".desktop").unwrap_or(&ident);
            let last_seg = ident_stem.rsplit('.').next().unwrap_or(ident_stem);
            if ident_stem.starts_with(&nom) || last_seg.starts_with(&nom) {
                cands.push(e);
            }
        }
    }
    if cands.is_empty() {
        return None;
    }
    for e in &cands {
        if e.categories.iter().any(|c| categories.contains(&c.as_str())) {
            return Some(e);
        }
    }
    Some(cands[0])
}

struct AideInfo {
    nom: String,
    categorie: String,
    icone: String,
    binaire: String,
}

fn construire(
    apps: &Value,
    entrees: &[DesktopEntry],
    creer_lanceurs: bool,
) -> (
    HashMap<String, String>,
    HashMap<String, String>,
    HashMap<String, AideInfo>,
    HashMap<String, String>,
) {
    let mut helpers = HashMap::new();
    let mut mimes = HashMap::new();
    let mut aides = HashMap::new();
    let mut binaires = HashMap::new();

    for regle in ROLES {
        let Some(nom) = apps.get(regle.role).and_then(|v| v.as_str()) else {
            continue;
        };
        if nom.is_empty() {
            continue;
        }
        let Some(entree) = resoudre(nom, regle.categories, entrees) else {
            continue;
        };
        if let Some(exo) = regle.exo {
            let mut binaire = exec_basename(&entree.exec);
            let stem = Path::new(&entree.id)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            let mut ident = if binaire.is_empty() {
                stem.clone()
            } else {
                binaire.clone()
            };
            if regle.role == "Terminal" {
                let lanceur = if creer_lanceurs {
                    ecrire_lanceur(&binaire)
                } else {
                    options_dossier(&binaire)
                        .map(|_| home_dir().join(".local/bin").join(format!("terminal-{}", binaire)))
                };
                if let Some(lp) = lanceur {
                    ident = lp
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or(&ident)
                        .to_string();
                    binaire = lp.to_string_lossy().to_string();
                    aides.remove(&ident);
                    binaires.insert(exo.to_string(), binaire);
                    helpers.insert(exo.to_string(), ident);
                    for mime in regle.mimes {
                        mimes.entry((*mime).to_string()).or_insert_with(|| entree.id.clone());
                    }
                    continue;
                }
            }
            binaires.insert(exo.to_string(), binaire.clone());
            helpers.insert(exo.to_string(), ident.clone());
            aides.insert(
                ident.clone(),
                AideInfo {
                    nom: if entree.nom.is_empty() {
                        ident
                    } else {
                        entree.nom.clone()
                    },
                    categorie: regle.categories[0].to_string(),
                    icone: stem,
                    binaire,
                },
            );
        }
        for mime in regle.mimes {
            mimes
                .entry((*mime).to_string())
                .or_insert_with(|| entree.id.clone());
        }
    }
    (helpers, mimes, aides, binaires)
}

fn ecrire_atomique(chemin: &Path, contenu: &str) {
    if let Some(p) = chemin.parent() {
        let _ = fs::create_dir_all(p);
    }
    let name = chemin
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("tmp");
    let tmp = chemin.with_file_name(format!(".{}.aethershell.tmp", name));
    if fs::write(&tmp, contenu).is_ok() {
        let _ = fs::rename(&tmp, chemin);
    }
}

fn ecrire_helpers(helpers: &HashMap<String, String>) {
    let hp = helpers_path();
    let mut lignes = Vec::new();
    if let Ok(txt) = fs::read_to_string(&hp) {
        for l in txt.lines() {
            if !l.trim().is_empty() {
                let k = l.split('=').next().unwrap_or("").trim();
                if !helpers.contains_key(k) {
                    lignes.push(l.to_string());
                }
            }
        }
    }
    for (k, v) in helpers {
        lignes.push(format!("{}={}", k, v));
    }
    ecrire_atomique(&hp, &(lignes.join("\n") + "\n"));
}

fn ecrire_aides(aides: &HashMap<String, AideInfo>) {
    let ad = aides_dir();
    let _ = fs::create_dir_all(&ad);
    for (ident, aide) in aides {
        let contenu = format!(
            "[Desktop Entry]\nVersion=1.0\nEncoding=UTF-8\nType=X-XFCE-Helper\nName={}\nIcon={}\nX-XFCE-Category={}\nX-XFCE-Binaries={};\n",
            aide.nom, aide.icone, aide.categorie, aide.binaire
        );
        ecrire_atomique(&ad.join(format!("{}.rc", ident)), &contenu);
    }
}

fn ecrire_mimeapps(mimes: &HashMap<String, String>) {
    let mp = mimeapps_path();
    let mut sections: HashMap<String, Vec<String>> = HashMap::new();
    let mut ordre: Vec<String> = Vec::new();
    let mut preambule: Vec<String> = Vec::new();
    let mut courant: Option<String> = None;

    if let Ok(txt) = fs::read_to_string(&mp) {
        for ligne in txt.lines() {
            let t = ligne.trim();
            if t.starts_with('[') && t.ends_with(']') {
                let sec = t[1..t.len() - 1].to_string();
                if !sections.contains_key(&sec) {
                    ordre.push(sec.clone());
                    sections.insert(sec.clone(), vec![]);
                }
                courant = Some(sec);
            } else if let Some(c) = &courant {
                if !t.is_empty() {
                    sections.get_mut(c).unwrap().push(ligne.to_string());
                }
            } else {
                preambule.push(ligne.to_string());
            }
        }
    }

    let cible = "Default Applications".to_string();
    if !sections.contains_key(&cible) {
        ordre.insert(0, cible.clone());
        sections.insert(cible.clone(), vec![]);
    }
    let mut restantes: Vec<String> = sections[&cible]
        .iter()
        .filter(|l| {
            let k = l.split('=').next().unwrap_or("").trim();
            !mimes.contains_key(k)
        })
        .cloned()
        .collect();
    for (mime, ident) in mimes {
        restantes.push(format!("{}={}", mime, ident));
    }
    sections.insert(cible, restantes);

    let mut sortie = preambule;
    for nom in ordre {
        sortie.push(format!("[{}]", nom));
        if let Some(lines) = sections.get(&nom) {
            sortie.extend(lines.clone());
        }
        sortie.push(String::new());
    }
    let out = sortie.join("\n").trim_end_matches('\n').to_string() + "\n";
    ecrire_atomique(&mp, &out);
}

fn couche_bureau(
    binaires: &HashMap<String, String>,
    mimes: &HashMap<String, String>,
) -> Map<String, Value> {
    let mut faits = Map::new();
    let id_browser = mimes
        .get("x-scheme-handler/https")
        .or_else(|| mimes.get("text/html"));
    if let Some(idb) = id_browser {
        if which_exists("xdg-settings") {
            let ok = run_cmd("xdg-settings", &["set", "default-web-browser", idb])
                .map(|o| o.status.success())
                .unwrap_or(false);
            faits.insert(
                "xdg-settings".into(),
                json!(if ok {
                    format!("navigateur → {}", idb)
                } else {
                    "échec".to_string()
                }),
            );
        }
    }

    if which_exists("kwriteconfig6") {
        let mut cmds: Vec<Vec<&str>> = Vec::new();
        if let Some(term) = binaires.get("TerminalEmulator") {
            cmds.push(vec![
                "--file",
                "kdeglobals",
                "--group",
                "General",
                "--key",
                "TerminalApplication",
                term,
            ]);
        }
        if let Some(idb) = id_browser {
            cmds.push(vec![
                "--file",
                "kdeglobals",
                "--group",
                "General",
                "--key",
                "BrowserApplication",
                idb,
            ]);
        }
        let mut cnt = 0;
        for c in cmds {
            if run_cmd("kwriteconfig6", &c)
                .map(|o| o.status.success())
                .unwrap_or(false)
            {
                cnt += 1;
            }
        }
        faits.insert("kde".into(), json!(cnt));
    }

    if which_exists("gsettings") {
        if let Some(term) = binaires.get("TerminalEmulator") {
            let ok = run_cmd(
                "gsettings",
                &[
                    "get",
                    "org.gnome.desktop.default-applications.terminal",
                    "exec",
                ],
            )
            .map(|o| o.status.success())
            .unwrap_or(false);
            if ok {
                let _ = run_cmd(
                    "gsettings",
                    &[
                        "set",
                        "org.gnome.desktop.default-applications.terminal",
                        "exec",
                        term,
                    ],
                );
                faits.insert("gnome".into(), json!(term));
            }
        }
    }
    faits
}

pub fn run(args: &[String]) -> i32 {
    let app_vars = core_dir().join("app_vars.json");
    let is_etat = args.iter().any(|a| a == "--etat");
    let is_appliquer = args.iter().any(|a| a == "--appliquer");

    if !is_etat && !is_appliquer {
        println!("Usage: lien-systeme [--appliquer | --etat]");
        return 0;
    }

    let entrees = tous_desktop();
    if is_etat {
        let apps = if app_vars.is_file() {
            read_json_value(&app_vars)
        } else {
            json!({})
        };
        let (helpers, mimes, _, _) = construire(&apps, &entrees, false);
        let mut manquants = Vec::new();
        for regle in ROLES {
            if let Some(nom) = apps.get(regle.role).and_then(|v| v.as_str()) {
                if !nom.is_empty() && resoudre(nom, regle.categories, &entrees).is_none() {
                    manquants.push(regle.role);
                }
            }
        }
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({
                "app_vars": apps,
                "helpers": helpers,
                "mimes": mimes,
                "introuvables": manquants,
            }))
            .unwrap_or_default()
        );
        return 0;
    }

    if !app_vars.is_file() {
        eprintln!("app_vars.json introuvable : {}", app_vars.display());
        return 1;
    }
    let apps = read_json_value(&app_vars);
    let (helpers, mimes, aides, binaires) = construire(&apps, &entrees, true);
    ecrire_aides(&aides);
    ecrire_helpers(&helpers);
    ecrire_mimeapps(&mimes);
    let bureaux = couche_bureau(&binaires, &mimes);
    if which_exists("update-desktop-database") {
        let apps_dir = home_dir().join(".local/share/applications");
        let _ = run_cmd(
            "update-desktop-database",
            &["-q", &apps_dir.to_string_lossy()],
        );
    }
    let mut aides_keys: Vec<&String> = aides.keys().collect();
    aides_keys.sort();
    println!(
        "{}",
        json!({
            "ok": true,
            "helpers": helpers,
            "aides": aides_keys,
            "mimes": mimes.len(),
            "bureaux": Value::Object(bureaux),
        })
    );
    0
}
