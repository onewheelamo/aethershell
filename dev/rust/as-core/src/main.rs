#![recursion_limit = "256"]

mod applets;
mod common;
mod config;
mod daemon;
mod launcher;
mod services;
mod wallfx;

use std::env;
use std::process;

fn normalize_subcmd(s: &str) -> &str {
    let base = s.rsplit('/').next().unwrap_or(s);
    match base {
        "metriques_daemon.py" => "daemon",
        "systeme_applet.py" => "systeme",
        "reseau_applet.py" => "reseau",
        "indicateurs_service.py" => "indicateurs",
        "live_activity_probe.py" => "live-activity",
        "system_service.py" => "system-service",
        "nuit_service.py" => "nuit",
        "bluetooth_service.py" => "bluetooth",
        "workspace_service.py" => "workspace",
        "bar_applets.py" => "bar-applets",
        "config_manager.py" => "config",
        "themes_scan.py" => "themes-scan",
        "theme_manager.py" => "theme-manager",
        "installer_theme_couleur.py" => "installer-theme-couleur",
        "terminal_theme.py" => "terminal-theme",
        "icones_manager.py" => "icones",
        "lien_systeme.py" => "lien-systeme",
        "greeter_manager.py" => "greeter",
        "app_index.py" => "app-index",
        "app_classes.py" => "app-classes",
        "launch_history.py" => "launch-history",
        "launcher_service.py" => "launcher",
        "lister_fichiers.py" => "lister-fichiers",
        "disques_applet.py" => "disques",
        "usb_applet.py" => "usb",
        "presse_papiers_applet.py" => "presse-papiers",
        "musique_applet.py" => "musique",
        "todo_applet.py" => "todo",
        "todo_worker.py" => "todo-worker",
        "notif_history.py" => "notif-history",
        "notif_target.py" => "notif-target",
        "tray_apps.py" => "tray-apps",
        "tray_watchdog.py" => "tray-watchdog",
        "matrix_wallpaper.py" => "matrix",
        "wifi_qr_scan.py" => "wifi-qr",
        "maj_shell.py" => "maj-shell",
        "deps_install.py" => "deps-install",
        "weather_service.py" => "weather",
        "meteo_applet.py" => "meteo",
        "nextcloud_service.py" => "nextcloud",
        "calendrier_config.py" => "calendrier-config",
        "calendrier_applet.py" => "calendrier",
        "planka_service.py" => "planka",
        "planka_worker.py" => "planka-worker",
        "homelab_applet.py" => "homelab",
        "flotte_applet.py" => "flotte",
        "comptes_applet.py" => "comptes",
        "deepseek_service.py" => "deepseek",
        "ollama_service.py" => "ollama",
        "antigravity_service.py" => "antigravity",
        "hermes_applet.py" => "hermes",
        "hermes_lecteur.py" => "hermes-lecteur",
        "hermes_approbations.py" => "hermes-approbations",
        "hermes_publier.py" => "hermes-publier",
        _ => s,
    }
}

fn main() {
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_DFL); }
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: as-core <sous-commande> [args...]");
        process::exit(2);
    }
    let subcmd = normalize_subcmd(args[1].as_str());
    let rest = &args[2..];

    let code = match subcmd {
        "ping" => {
            println!("{{\"ok\":true,\"version\":\"{}\"}}", env!("CARGO_PKG_VERSION"));
            0
        }
        // Lot 1 — Démon & sondes temps réel
        "daemon" | "metriques-daemon" => daemon::run_daemon(rest),
        "systeme" => daemon::systeme::run(rest),
        "reseau" => daemon::reseau::run(rest),
        "indicateurs" => daemon::indicateurs::run(),
        "live-activity" => daemon::live_activity::run(rest),
        "system-service" => daemon::system_service::run(rest),
        "nuit" => daemon::nuit::run(rest),
        "bluetooth" => daemon::bluetooth::run(rest),
        "workspace" => daemon::workspace::run(),
        "workspace-float-toggle" => daemon::workspace::run_float_toggle(),
        // Lot 2 — Registre d'applets, thèmes & configuration
        "bar-applets" => config::bar_applets::run(rest),
        "config" => config::config_mgr::run(rest),
        "themes-scan" => config::themes::run_scan(rest),
        "theme-manager" => config::themes::run_manager(rest),
        "installer-theme-couleur" => config::themes::run_installer(rest),
        "terminal-theme" => config::terminal_theme::run_terminal_theme(rest),
        "sync-apps-theme" => config::terminal_theme::run_sync_apps(),
        "icones" => config::icones::run(rest),
        "lien-systeme" => config::lien_systeme::run(rest),
        "greeter" => config::greeter::run(rest),
        "first-run" => config::first_run::run(rest),
        "quick-notes" => config::quick_tools::run_quick_notes(rest),
        "wallpaper-list" => config::quick_tools::run_wallpaper_list(),
        "wl-copy" => config::quick_tools::run_wl_copy(rest),
        // Lot 3 — Lanceur Spotlight & Index
        "app-index" => launcher::app_index::run_index(rest),
        "app-classes" => launcher::app_index::run_classes(rest),
        "launch-history" => launcher::history::run(rest),
        "launcher" => launcher::service::run(rest),
        "texte-doc" => launcher::service::run_texte_doc(rest),
        "lister-fichiers" => launcher::files::run(rest),
        // Lot 4 — Applets locaux & Notifications
        "disques" => applets::disques::run(rest),
        "usb" => applets::usb::run(rest),
        "presse-papiers" => applets::presse_papiers::run(rest),
        "musique" => applets::musique::run(rest),
        "todo" => applets::todo::run(rest),
        "todo-worker" => applets::todo::run_worker(rest),
        "notif-history" => applets::notif::run_history(rest),
        "notif-target" => applets::notif::run_target(rest),
        "tray-apps" => applets::tray::run_apps(rest),
        "tray-watchdog" => applets::tray::run_watchdog(rest),
        "matrix" => applets::matrix::run(rest),
        "wifi-qr" => applets::wifi_qr::run(rest),
        "maj-shell" => applets::system_tools::run_maj_shell(rest),
        "deps-install" => applets::system_tools::run_deps_install(rest),
        // Lot 5 — Connecteurs & Services HTTP/API
        "weather" => services::weather::run_weather(rest),
        "meteo" => services::weather::run_meteo(rest),
        "nextcloud" => services::nextcloud::run(rest),
        "calendrier-config" => services::calendrier_cfg::run(rest),
        "calendrier" => services::calendrier_cfg::run_applet(rest),
        "planka" => services::planka::run(rest),
        "planka-worker" => services::planka::run_worker(rest),
        "homelab" => services::homelab::run(rest),
        "flotte" => services::flotte::run(rest),
        "comptes" => services::llm::run_comptes(rest),
        "deepseek" => services::llm::run_deepseek(rest),
        "ollama" => services::llm::run_ollama(rest),
        "antigravity" => services::antigravity::run(rest),
        "hermes" => services::hermes::run_applet(rest),
        "hermes-lecteur" => services::hermes::run_lecteur(rest),
        "hermes-approbations" => services::hermes::run_approbations(rest),
        "hermes-publier" => services::hermes::run_publier(rest),
        // Lot 6 — WallFX / Profondeur / Parallaxe
        "wallfx" => wallfx::wallfx_maps::run(rest),
        "depth-mask" => wallfx::depth_mask::run(rest),
        "parallaxe" => wallfx::parallaxe::run(rest),
        "masque-peinture" => wallfx::masque_peinture::run(rest),
        _ => {
            eprintln!("as-core: sous-commande inconnue: {subcmd}");
            2
        }
    };
    process::exit(code);
}
