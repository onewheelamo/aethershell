use crate::common::io::{read_json_value, run_cmd};
use crate::common::paths::{config_dir, core_dir, home_dir};
use regex::Regex;
use serde_json::{Map, Value};
use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::Path;

const BEGIN_MARK: &str = "/* BEGIN aethershell-theme */";
const END_MARK: &str = "/* END aethershell-theme */";

fn is_dark(hex_c: &str) -> bool {
    let h = hex_c.trim().trim_start_matches('#');
    if h.len() != 6 {
        return true;
    }
    let r = u8::from_str_radix(&h[0..2], 16).unwrap_or(30) as f64 / 255.0;
    let g = u8::from_str_radix(&h[2..4], 16).unwrap_or(30) as f64 / 255.0;
    let b = u8::from_str_radix(&h[4..6], 16).unwrap_or(46) as f64 / 255.0;
    (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
}

fn contrast_fg(bg_hex: &str) -> &'static str {
    if !is_dark(bg_hex) { "#11111b" } else { "#ffffff" }
}

fn upsert_marked_block(path: &Path, block: &str) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let existing = fs::read_to_string(path).unwrap_or_default();
    let wrapped = format!("{BEGIN_MARK}\n{}\n{END_MARK}\n", block.trim_end());
    let pat = format!(r"(?s){}.*?{}\n?", regex::escape(BEGIN_MARK), regex::escape(END_MARK));
    let updated = if let Ok(re) = Regex::new(&pat) {
        if re.is_match(&existing) {
            re.replace(&existing, wrapped.as_str()).to_string()
        } else {
            let sep = if !existing.is_empty() && !existing.ends_with('\n') { "\n" } else { "" };
            format!("{existing}{sep}{wrapped}")
        }
    } else {
        existing.clone()
    };
    if updated != existing {
        let _ = fs::write(path, updated);
    }
}

fn active_palette() -> Option<Map<String, Value>> {
    let sp = core_dir().join("style_vars.json");
    let data = read_json_value(&sp);
    let active = data.get("active_theme").and_then(|v| v.as_str()).unwrap_or("dynamic");
    let palettes = data.get("palette").and_then(|v| v.as_object())?;
    palettes
        .get(active)
        .or_else(|| palettes.get("dynamic"))
        .and_then(|v| v.as_object())
        .cloned()
}

pub fn run_sync_apps() -> i32 {
    let Some(p) = active_palette() else { return 0; };
    let get = |k: &str, def: &str| -> String {
        p.get(k).and_then(|v| v.as_str()).unwrap_or(def).to_string()
    };
    let bg = get("bg", "#1e1e2e");
    let fg = get("fg", "#cdd6f4");
    let accent = get("accent", "#b4befe");
    let surface = get("surface", "#313244");
    let surface_var = get("surface_variant", "#45475a");
    let accent_muted = get("accent_muted", "#89b4fa");
    let error = get("error", "#f38ba8");
    let warn = get("warn", "#fab387");
    let success = get("success", "#a6e3a1");
    let accent_fg = contrast_fg(&accent);

    let css = format!(
        "@define-color accent_color {accent};\n\
@define-color accent_bg_color {accent};\n\
@define-color accent_fg_color {accent_fg};\n\
@define-color window_bg_color {bg};\n\
@define-color window_fg_color {fg};\n\
@define-color view_bg_color {bg};\n\
@define-color view_fg_color {fg};\n\
@define-color headerbar_bg_color {surface};\n\
@define-color headerbar_fg_color {fg};\n\
@define-color card_bg_color {surface};\n\
@define-color card_fg_color {fg};\n\
@define-color dialog_bg_color {surface};\n\
@define-color dialog_fg_color {fg};\n\
@define-color popover_bg_color {surface_var};\n\
@define-color popover_fg_color {fg};\n\
@define-color sidebar_bg_color {surface};\n\
@define-color sidebar_fg_color {fg};\n\
@define-color destructive_color {error};\n\
@define-color warning_color {warn};\n\
@define-color success_color {success};"
    );

    let cfg = config_dir();
    for ver in ["gtk-3.0", "gtk-4.0"] {
        upsert_marked_block(&cfg.join(ver).join("gtk.css"), &css);
    }

    let scheme = if is_dark(&bg) { "prefer-dark" } else { "prefer-light" };
    let _ = run_cmd("gsettings", &["set", "org.gnome.desktop.interface", "color-scheme", scheme]);

    let active_colors = [
        fg.as_str(), surface.as_str(), surface_var.as_str(), surface_var.as_str(),
        bg.as_str(), bg.as_str(), fg.as_str(), fg.as_str(), fg.as_str(),
        bg.as_str(), bg.as_str(), bg.as_str(), accent.as_str(), accent_fg,
        accent_muted.as_str(), accent_muted.as_str(), surface.as_str(), fg.as_str(),
        surface.as_str(), fg.as_str(), accent.as_str(),
    ]
    .join(",");
    let scheme_conf = format!(
        "[ColorScheme]\nactive_colors={active_colors}\ndisabled_colors={active_colors}\ninactive_colors={active_colors}\n"
    );
    for qt in ["qt5ct", "qt6ct"] {
        let cdir = cfg.join(qt).join("colors");
        let _ = fs::create_dir_all(&cdir);
        let _ = fs::write(cdir.join("aethershell.conf"), &scheme_conf);
    }
    0
}

fn hex_to_rgb(h_in: &str) -> (f64, f64, f64) {
    let h = h_in.trim().trim_start_matches('#');
    let full = if h.len() == 3 {
        let mut s = String::with_capacity(6);
        for c in h.chars() {
            s.push(c);
            s.push(c);
        }
        s
    } else {
        h.to_string()
    };
    if full.len() != 6 {
        return (0.118, 0.118, 0.180);
    }
    let r = u8::from_str_radix(&full[0..2], 16).unwrap_or(30) as f64 / 255.0;
    let g = u8::from_str_radix(&full[2..4], 16).unwrap_or(30) as f64 / 255.0;
    let b = u8::from_str_radix(&full[4..6], 16).unwrap_or(46) as f64 / 255.0;
    (r, g, b)
}

fn rgb_to_hex(r: f64, g: f64, b: f64) -> String {
    let clamp = |x: f64| -> u8 { (x.clamp(0.0, 1.0) * 255.0).round() as u8 };
    format!("#{:02x}{:02x}{:02x}", clamp(r), clamp(g), clamp(b))
}

fn rgb_to_hls(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let maxc = r.max(g).max(b);
    let minc = r.min(g).min(b);
    let sumc = maxc + minc;
    let rangec = maxc - minc;
    let l = sumc / 2.0;
    if minc == maxc {
        return (0.0, l, 0.0);
    }
    let s = if l <= 0.5 {
        rangec / sumc
    } else {
        rangec / (2.0 - sumc)
    };
    let rc = (maxc - r) / rangec;
    let gc = (maxc - g) / rangec;
    let bc = (maxc - b) / rangec;
    let mut h = if r == maxc {
        bc - gc
    } else if g == maxc {
        2.0 + rc - bc
    } else {
        4.0 + gc - rc
    };
    h = (h / 6.0).rem_euclid(1.0);
    (h, l, s)
}

fn hls_to_rgb(h: f64, l: f64, s: f64) -> (f64, f64, f64) {
    if s == 0.0 {
        return (l, l, l);
    }
    let m2 = if l <= 0.5 {
        l * (1.0 + s)
    } else {
        l + s - (l * s)
    };
    let m1 = 2.0 * l - m2;
    let v = |mut hue: f64| -> f64 {
        hue = hue.rem_euclid(1.0);
        if hue < 1.0 / 6.0 {
            m1 + (m2 - m1) * hue * 6.0
        } else if hue < 0.5 {
            m2
        } else if hue < 2.0 / 3.0 {
            m1 + (m2 - m1) * (2.0 / 3.0 - hue) * 6.0
        } else {
            m1
        }
    };
    (v(h + 1.0 / 3.0), v(h), v(h - 1.0 / 3.0))
}

fn adjust_lightness(h_color: &str, factor: f64) -> String {
    let (r, g, b) = hex_to_rgb(h_color);
    let (h, mut l, s) = rgb_to_hls(r, g, b);
    if factor >= 0.0 {
        l = (l + (1.0 - l) * factor).min(1.0);
    } else {
        l = (l * (1.0 + factor)).max(0.0);
    }
    let (r2, g2, b2) = hls_to_rgb(h, l, s);
    rgb_to_hex(r2, g2, b2)
}

fn rel_lum(hex_c: &str) -> f64 {
    let lin = |v: f64| -> f64 {
        if v <= 0.03928 {
            v / 12.92
        } else {
            ((v + 0.055) / 1.055).powf(2.4)
        }
    };
    let (r, g, b) = hex_to_rgb(hex_c);
    0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

fn contrast_ratio(c1: &str, c2: &str) -> f64 {
    let (l1, l2) = (rel_lum(c1), rel_lum(c2));
    let (hi, lo) = (l1.max(l2), l1.min(l2));
    (hi + 0.05) / (lo + 0.05)
}

fn ensure_contrast(color_hex: &str, bg_hex: &str, min_ratio: f64) -> String {
    if contrast_ratio(color_hex, bg_hex) >= min_ratio {
        return color_hex.to_string();
    }
    let (r, g, b) = hex_to_rgb(color_hex);
    let (h, l, s) = rgb_to_hls(r, g, b);
    let dark_bg = is_dark(bg_hex);
    let (mut lo, mut hi) = if dark_bg { (l, 1.0) } else { (0.0, l) };
    let mut best = color_hex.to_string();
    for _ in 0..18 {
        let mid = (lo + hi) / 2.0;
        let (cr, cg, cb) = hls_to_rgb(h, mid, s);
        let cand = rgb_to_hex(cr, cg, cb);
        if contrast_ratio(&cand, bg_hex) >= min_ratio {
            best = cand;
            if dark_bg {
                hi = mid;
            } else {
                lo = mid;
            }
        } else if dark_bg {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    if contrast_ratio(&best, bg_hex) < min_ratio {
        if dark_bg {
            "#ffffff".to_string()
        } else {
            "#000000".to_string()
        }
    } else {
        best
    }
}

struct TermPalette {
    theme: String,
    opacity: f64,
    bg: String,
    fg: String,
    cursor: String,
    cursor_text: String,
    selection_bg: String,
    selection_fg: String,
    ansi: Vec<String>,
}

fn compute_terminal_palette(style_data: &Value) -> TermPalette {
    let active = style_data
        .get("active_theme")
        .and_then(|v| v.as_str())
        .unwrap_or("dynamic")
        .to_string();
    let palettes = style_data.get("palette").cloned().unwrap_or(Value::Null);
    let p = palettes
        .get(&active)
        .or_else(|| palettes.get("dynamic"))
        .cloned()
        .unwrap_or(Value::Null);
    let opacity = style_data
        .get("global_opacity")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.85);

    let g = |k: &str, def: &str| -> String {
        p.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or(def)
            .to_string()
    };
    let bg = g("bg", "#1e1e2e");
    let fg = g("fg", "#cdd6f4");
    let accent = g("accent", "#b4befe");
    let accent_muted = g("accent_muted", "#89b4fa");
    let surface = g("surface", "#313244");
    let surface_var = g("surface_variant", "#45475a");
    let err = g("error", "#f38ba8");
    let warn = g("warn", "#fab387");
    let info = g("info", "#89b4fa");
    let succ = g("success", "#a6e3a1");

    let dark = is_dark(&bg);
    let raw_ansi = if dark {
        vec![
            surface.clone(),
            err.clone(),
            succ.clone(),
            warn.clone(),
            accent.clone(),
            accent_muted.clone(),
            info.clone(),
            fg.clone(),
            surface_var.clone(),
            adjust_lightness(&err, 0.25),
            adjust_lightness(&succ, 0.25),
            adjust_lightness(&warn, 0.25),
            adjust_lightness(&accent, 0.25),
            adjust_lightness(&accent_muted, 0.25),
            adjust_lightness(&info, 0.25),
            "#ffffff".to_string(),
        ]
    } else {
        vec![
            "#1e1e2e".to_string(),
            err.clone(),
            succ.clone(),
            warn.clone(),
            accent.clone(),
            accent_muted.clone(),
            info.clone(),
            surface.clone(),
            surface_var.clone(),
            adjust_lightness(&err, -0.2),
            adjust_lightness(&succ, -0.2),
            adjust_lightness(&warn, -0.2),
            adjust_lightness(&accent, -0.2),
            adjust_lightness(&accent_muted, -0.2),
            adjust_lightness(&info, -0.2),
            "#000000".to_string(),
        ]
    };

    let min_ratios = [
        3.0, 4.5, 4.5, 4.5, 4.5, 4.5, 4.5, 7.0, 3.6, 4.5, 4.5, 4.5, 4.5, 4.5, 4.5, 7.0,
    ];
    let ansi = raw_ansi
        .into_iter()
        .zip(min_ratios)
        .map(|(c, r)| ensure_contrast(&c, &bg, r))
        .collect();

    TermPalette {
        theme: active,
        opacity,
        cursor: accent,
        cursor_text: bg.clone(),
        selection_bg: surface_var,
        selection_fg: fg.clone(),
        bg,
        fg,
        ansi,
    }
}

fn build_osc_sequences(t: &TermPalette) -> String {
    let mut seqs = format!(
        "\x1b]10;{}\x07\x1b]11;{}\x07\x1b]12;{}\x07\x1b]17;{}\x07\x1b]19;{}\x07",
        t.fg, t.bg, t.cursor, t.selection_bg, t.selection_fg
    );
    for (idx, col) in t.ansi.iter().enumerate() {
        seqs.push_str(&format!("\x1b]4;{};{}\x07", idx, col));
    }
    seqs
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

fn premier_plan_pts(pts_path: &Path) -> i32 {
    let Ok(meta) = fs::metadata(pts_path) else {
        return -1;
    };
    let cible = meta.rdev();
    if let Ok(rd) = fs::read_dir("/proc") {
        for ent in rd.flatten() {
            let fname = ent.file_name();
            let Some(s) = fname.to_str() else {
                continue;
            };
            if !s.bytes().all(|b| b.is_ascii_digit()) {
                continue;
            }
            let Ok(raw) = fs::read(ent.path().join("stat")) else {
                continue;
            };
            let txt = String::from_utf8_lossy(&raw);
            let Some((_, after)) = txt.rsplit_once(')') else {
                continue;
            };
            let champs: Vec<&str> = after.split_whitespace().collect();
            if champs.len() > 5 {
                let tty_nr: u64 = champs[4].parse().unwrap_or(0);
                let tpgid: i32 = champs[5].parse().unwrap_or(-1);
                if tty_nr == cible && tpgid > 0 {
                    return tpgid;
                }
            }
        }
    }
    -1
}

fn pty_au_repos(pts_path: &Path) -> bool {
    let pgid = premier_plan_pts(pts_path);
    if pgid <= 0 {
        return false;
    }
    let Ok(nom) = fs::read_to_string(format!("/proc/{}/comm", pgid)) else {
        return false;
    };
    matches!(
        nom.trim(),
        "sh" | "bash" | "zsh" | "fish" | "dash" | "ksh" | "mksh" | "yash"
    )
}

fn broadcast_to_pts(osc_seq: &str) -> (usize, usize) {
    let pts_dir = Path::new("/dev/pts");
    if !pts_dir.is_dir() {
        return (0, 0);
    }
    let uid = unsafe { libc::getuid() };
    let mut touches = 0usize;
    let mut ignores = 0usize;
    let Ok(rd) = fs::read_dir(pts_dir) else {
        return (0, 0);
    };
    for ent in rd.flatten() {
        let name = ent.file_name();
        let Some(ns) = name.to_str() else {
            continue;
        };
        if !ns.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        let p = ent.path();
        let Ok(st) = fs::metadata(&p) else {
            continue;
        };
        if st.uid() != uid {
            continue;
        }
        if !pty_au_repos(&p) {
            ignores += 1;
            continue;
        }
        if let Ok(mut f) = OpenOptions::new().write(true).open(&p) {
            if f.write_all(osc_seq.as_bytes()).is_ok() {
                touches += 1;
            } else {
                ignores += 1;
            }
        } else {
            ignores += 1;
        }
    }
    (touches, ignores)
}

fn write_universal_scripts(t: &TermPalette) {
    let h = home_dir();
    let aether_dir = h.join(".config/aethershell");
    let _ = fs::create_dir_all(&aether_dir);
    let aether_script = aether_dir.join("terminal-colors.sh");

    let ansi_lines: Vec<String> = t
        .ansi
        .iter()
        .enumerate()
        .map(|(i, c)| format!("        printf '\\033]4;{i};{c}\\007'"))
        .collect();
    let content = format!(
        "#!/bin/sh\n\
# AetherShell dynamic terminal palette ({theme})\n\
# Généré automatiquement depuis style_vars.json — ne pas modifier à la main.\n\
\n\
if [ -t 1 ] && [ -n \"${{TERM:-}}\" ] && [ \"$TERM\" != \"dumb\" ]; then\n\
    if [ \"${{AETHERSHELL_PALETTE_APPLIED:-}}\" != \"{theme}\" ]; then\n\
        export AETHERSHELL_PALETTE_APPLIED=\"{theme}\"\n\
        printf '\\033]10;{fg}\\007'\n\
        printf '\\033]11;{bg}\\007'\n\
        printf '\\033]12;{cur}\\007'\n\
        printf '\\033]17;{sbg}\\007'\n\
        printf '\\033]19;{sfg}\\007'\n\
{ansi}\n\
    fi\n\
fi\n",
        theme = t.theme,
        fg = t.fg,
        bg = t.bg,
        cur = t.cursor,
        sbg = t.selection_bg,
        sfg = t.selection_fg,
        ansi = ansi_lines.join("\n"),
    );
    ecrire_atomique(&aether_script, &content);
    let _ = fs::set_permissions(&aether_script, fs::Permissions::from_mode(0o755));

    let bashrc_d = h.join(".bashrc.d");
    let _ = fs::create_dir_all(&bashrc_d);
    let hook = "# Séquences de couleurs dynamiques AetherShell\nif [ -f \"$HOME/.config/aethershell/terminal-colors.sh\" ]; then\n    . \"$HOME/.config/aethershell/terminal-colors.sh\"\nfi\n";
    let _ = fs::write(bashrc_d.join("10-aethershell-theme.sh"), hook);

    let bashrc = h.join(".bashrc");
    if bashrc.is_file() {
        let marqueur = "# AetherShell : couleurs du terminal (généré)";
        if let Ok(txt) = fs::read_to_string(&bashrc) {
            if !txt.contains(marqueur) {
                let ajout = format!(
                    "\n{marqueur}\n[ -f \"$HOME/.config/aethershell/terminal-colors.sh\" ] && . \"$HOME/.config/aethershell/terminal-colors.sh\"\n"
                );
                let out = format!("{}{}", txt.trim_end_matches('\n'), ajout);
                ecrire_atomique(&bashrc, &out);
            }
        }
    }
}

fn update_ghostty(t: &TermPalette) {
    let gdir = config_dir().join("ghostty");
    let themes_dir = gdir.join("themes");
    let _ = fs::create_dir_all(&themes_dir);

    let mut lines = vec![
        format!("# AetherShell Ghostty Theme ({})", t.theme),
        format!("background = {}", t.bg),
        format!("foreground = {}", t.fg),
        format!("cursor-color = {}", t.cursor),
        format!("cursor-text = {}", t.cursor_text),
        format!("selection-background = {}", t.selection_bg),
        format!("selection-foreground = {}", t.selection_fg),
    ];
    for (idx, col) in t.ansi.iter().enumerate() {
        lines.push(format!("palette = {}={}", idx, col));
    }
    ecrire_atomique(&themes_dir.join("aethershell"), &(lines.join("\n") + "\n"));

    let user_conf = gdir.join("user.conf");
    let re_theme = Regex::new(r"^\s*theme\s*=").unwrap();
    let re_opac = Regex::new(r"^\s*background-opacity\s*=").unwrap();
    let re_blur = Regex::new(r"^\s*background-blur\s*=").unwrap();
    let mut has_theme = false;
    let mut has_opac = false;
    let mut has_blur = false;
    let mut new_lines = Vec::new();
    if let Ok(txt) = fs::read_to_string(&user_conf) {
        for line in txt.lines() {
            if re_theme.is_match(line) {
                new_lines.push("theme = aethershell".to_string());
                has_theme = true;
            } else if re_opac.is_match(line) {
                new_lines.push(format!("background-opacity = {}", t.opacity));
                has_opac = true;
            } else if re_blur.is_match(line) {
                new_lines.push("background-blur = true".to_string());
                has_blur = true;
            } else {
                new_lines.push(line.to_string());
            }
        }
    }
    if !has_blur {
        new_lines.insert(0, "background-blur = true".to_string());
    }
    if !has_theme {
        new_lines.push("theme = aethershell".to_string());
    }
    if !has_opac {
        new_lines.push(format!("background-opacity = {}", t.opacity));
    }
    ecrire_atomique(&user_conf, &(new_lines.join("\n") + "\n"));

    let mut included = false;
    for name in ["config.ghostty", "config"] {
        let cf = gdir.join(name);
        if cf.is_file() {
            if let Ok(txt) = fs::read_to_string(&cf) {
                if !txt.contains("user.conf") {
                    ecrire_atomique(
                        &cf,
                        &format!("{}\n\n# Configuration utilisateur AetherShell\nconfig-file = ?user.conf\n", txt.trim_end()),
                    );
                }
            }
            included = true;
        }
    }
    if !included {
        ecrire_atomique(
            &gdir.join("config"),
            "# Configuration Ghostty AetherShell\nconfig-file = ?user.conf\n",
        );
    }
}

fn update_kitty(t: &TermPalette) {
    let kdir = config_dir().join("kitty");
    let _ = fs::create_dir_all(&kdir);
    let mut lines = vec![
        format!("# AetherShell Kitty Theme ({})", t.theme),
        format!("foreground            {}", t.fg),
        format!("background            {}", t.bg),
        format!("background_opacity    {}", t.opacity),
        format!("cursor                {}", t.cursor),
        format!("cursor_text_color     {}", t.cursor_text),
        format!("selection_foreground  {}", t.selection_fg),
        format!("selection_background  {}", t.selection_bg),
        String::new(),
    ];
    for (idx, col) in t.ansi.iter().enumerate() {
        lines.push(format!("color{:<2} {}", idx, col));
    }
    ecrire_atomique(
        &kdir.join("aethershell-theme.conf"),
        &(lines.join("\n") + "\n"),
    );

    let kconf = kdir.join("kitty.conf");
    if kconf.is_file() {
        if let Ok(txt) = fs::read_to_string(&kconf) {
            if !txt.contains("aethershell-theme.conf") {
                ecrire_atomique(
                    &kconf,
                    &format!("{}\ninclude aethershell-theme.conf\n", txt.trim_end()),
                );
            }
        }
    }
    let _ = run_cmd("pkill", &["-USR1", "-x", "kitty"]);
}

fn update_alacritty(t: &TermPalette) {
    let adir = config_dir().join("alacritty");
    let _ = fs::create_dir_all(&adir);
    let a = &t.ansi;
    let content = format!(
        "# AetherShell Alacritty Theme ({})\n\n\
[colors.primary]\nbackground = \"{}\"\nforeground = \"{}\"\n\n\
[colors.cursor]\ncursor = \"{}\"\ntext = \"{}\"\n\n\
[colors.selection]\nbackground = \"{}\"\ntext = \"{}\"\n\n\
[colors.normal]\nblack   = \"{}\"\nred     = \"{}\"\ngreen   = \"{}\"\nyellow  = \"{}\"\nblue    = \"{}\"\nmagenta = \"{}\"\ncyan    = \"{}\"\nwhite   = \"{}\"\n\n\
[colors.bright]\nblack   = \"{}\"\nred     = \"{}\"\ngreen   = \"{}\"\nyellow  = \"{}\"\nblue    = \"{}\"\nmagenta = \"{}\"\ncyan    = \"{}\"\nwhite   = \"{}\"\n\n\
[window]\nopacity = {}\n",
        t.theme,
        t.bg,
        t.fg,
        t.cursor,
        t.cursor_text,
        t.selection_bg,
        t.selection_fg,
        a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7],
        a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15],
        t.opacity
    );
    ecrire_atomique(&adir.join("aethershell-theme.toml"), &content);

    let aconf = adir.join("alacritty.toml");
    if !aconf.is_file() {
        return;
    }
    let Ok(txt) = fs::read_to_string(&aconf) else {
        return;
    };
    let nom = "aethershell-theme.toml";
    let mut lignes: Vec<String> = txt.lines().map(|l| l.to_string()).collect();
    let debut = lignes.iter().position(|l| l.trim() == "[general]");
    let Some(deb) = debut else {
        let nouveau = format!("[general]\nimport = [\"{}\"]\n\n{}", nom, txt);
        ecrire_atomique(&aconf, &nouveau);
        return;
    };
    let fin = ((deb + 1)..lignes.len())
        .find(|&j| lignes[j].trim_start().starts_with('['))
        .unwrap_or(lignes.len());
    let re_arr = Regex::new(r"^(\s*)import\s*=\s*\[(.*)\]\s*$").unwrap();
    let re_imp = Regex::new(r"^\s*import\s*=").unwrap();
    let re_item = Regex::new(r#""([^"]+)""#).unwrap();

    for j in (deb + 1)..fin {
        if let Some(cap) = re_arr.captures(&lignes[j]) {
            let dedans = &cap[2];
            if dedans.contains(nom) {
                return;
            }
            let mut gardes: Vec<String> = Vec::new();
            let mut seen = HashSet::new();
            for icap in re_item.captures_iter(dedans) {
                let s = icap[1].to_string();
                if s != nom && seen.insert(s.clone()) {
                    gardes.push(s);
                }
            }
            gardes.push(nom.to_string());
            let formatted: Vec<String> = gardes.iter().map(|x| format!("\"{}\"", x)).collect();
            lignes[j] = format!("{}import = [{}]", &cap[1], formatted.join(", "));
            ecrire_atomique(&aconf, &(lignes.join("\n") + "\n"));
            return;
        }
        if re_imp.is_match(&lignes[j]) {
            return;
        }
    }
    lignes.insert(deb + 1, format!("import = [\"{}\"]", nom));
    ecrire_atomique(&aconf, &(lignes.join("\n") + "\n"));
}

fn update_foot(t: &TermPalette) {
    let fdir = config_dir().join("foot");
    let tdir = fdir.join("themes");
    let _ = fs::create_dir_all(&tdir);
    let a: Vec<&str> = t.ansi.iter().map(|c| c.trim_start_matches('#')).collect();
    let content = format!(
        "# AetherShell Foot Theme ({})\n\
[colors]\nalpha={}\nforeground={}\nbackground={}\n\n\
regular0={}\nregular1={}\nregular2={}\nregular3={}\nregular4={}\nregular5={}\nregular6={}\nregular7={}\n\n\
bright0={}\nbright1={}\nbright2={}\nbright3={}\nbright4={}\nbright5={}\nbright6={}\nbright7={}\n",
        t.theme,
        t.opacity,
        t.fg.trim_start_matches('#'),
        t.bg.trim_start_matches('#'),
        a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7],
        a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15]
    );
    ecrire_atomique(&tdir.join("aethershell.ini"), &content);
}

pub fn run_terminal_theme(args: &[String]) -> i32 {
    let broadcast_only = args.iter().any(|a| a == "--broadcast-only");
    let local_style = core_dir().join("style_vars.json");
    let style_path = if local_style.is_file() {
        local_style
    } else {
        let dep = home_dir().join(".config/quickshell/core/style_vars.json");
        if dep.is_file() {
            dep
        } else {
            local_style
        }
    };
    if !style_path.is_file() {
        eprintln!("Erreur : {} introuvable.", style_path.display());
        return 1;
    }
    let style_data = read_json_value(&style_path);
    if !style_data.is_object() {
        eprintln!("Erreur lors de la lecture de {}", style_path.display());
        return 1;
    }

    let palette_info = compute_terminal_palette(&style_data);
    let osc_seq = build_osc_sequences(&palette_info);
    let (pts_count, pts_ignores) = broadcast_to_pts(&osc_seq);

    if broadcast_only {
        println!(
            "OSC diffusé à {} pseudoterminaux ({} ignorés : programme au premier plan ou nœud mort).",
            pts_count, pts_ignores
        );
        return 0;
    }

    write_universal_scripts(&palette_info);
    update_ghostty(&palette_info);
    update_kitty(&palette_info);
    update_alacritty(&palette_info);
    update_foot(&palette_info);

    println!(
        "Palette '{}' appliquée : {} terminaux mis à jour en direct + configs Ghostty/Kitty/Alacritty/Foot synchronisées.",
        palette_info.theme, pts_count
    );
    0
}
