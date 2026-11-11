#!/usr/bin/env python3
"""Générateur de thèmes et séquences de couleurs pour terminaux (AetherShell).

Lit la palette active et l'opacité dans `style_vars.json` et synchronise :
1. Les séquences d'échappement OSC universelles (OSC 10/11/12/17/19 et OSC 4 pour les 16 couleurs ANSI).
   - Écrites dans `~/.config/aethershell/terminal-colors.sh`
   - Sourcées automatiquement par `~/.bashrc.d/10-aethershell-theme.sh`
   - Diffusées en direct aux pseudoterminaux ouverts de l'utilisateur (`/dev/pts/*`)
2. Les configurations natives pour les émulateurs connus :
   - Ghostty : `~/.config/ghostty/themes/aethershell` (+ réglage `theme = aethershell` et opacité dans `user.conf`)
   - Kitty : `~/.config/kitty/aethershell-theme.conf` (+ signal SIGUSR1 aux instances actives)
   - Alacritty : `~/.config/alacritty/aethershell-theme.toml` (+ import dans `alacritty.toml`)
   - Foot : `~/.config/foot/themes/aethershell.ini`
"""
import argparse
import colorsys
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path


def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hex(r, g, b):
    return "#%02x%02x%02x" % (
        int(round(max(0.0, min(1.0, r)) * 255)),
        int(round(max(0.0, min(1.0, g)) * 255)),
        int(round(max(0.0, min(1.0, b)) * 255))
    )


def is_dark(hex_c):
    r, g, b = hex_to_rgb(hex_c)
    # Luminance relative
    return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5


def adjust_lightness(h_color, factor):
    """Ajuste la luminosité (factor > 0 éclaircit, factor < 0 assombrit)."""
    r, g, b = hex_to_rgb(h_color)
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    if factor >= 0:
        l = min(1.0, l + (1.0 - l) * factor)
    else:
        l = max(0.0, l * (1.0 + factor))
    r2, g2, b2 = colorsys.hls_to_rgb(h, l, s)
    return rgb_to_hex(r2, g2, b2)


def find_style_file():
    base_dir = Path(__file__).resolve().parent
    local_style = base_dir / "style_vars.json"
    if local_style.is_file():
        return local_style
    deployed = Path.home() / ".config" / "quickshell" / "core" / "style_vars.json"
    if deployed.is_file():
        return deployed
    return local_style


def compute_terminal_palette(style_data):
    palettes = style_data.get("palette", {})
    active = style_data.get("active_theme", "dynamic")
    p = palettes.get(active) or palettes.get("dynamic", {})
    opacity = float(style_data.get("global_opacity", 0.85))

    bg = p.get("bg", "#1e1e2e")
    fg = p.get("fg", "#cdd6f4")
    accent = p.get("accent", "#b4befe")
    accent_muted = p.get("accent_muted", "#89b4fa")
    surface = p.get("surface", "#313244")
    surface_var = p.get("surface_variant", "#45475a")
    err = p.get("error", "#f38ba8")
    warn = p.get("warn", "#fab387")
    info = p.get("info", "#89b4fa")
    succ = p.get("success", "#a6e3a1")

    dark = is_dark(bg)

    if dark:
        c0 = surface
        c1 = err
        c2 = succ
        c3 = warn
        c4 = accent
        c5 = accent_muted
        c6 = info
        c7 = fg
        c8 = surface_var
        c9 = adjust_lightness(err, 0.25)
        c10 = adjust_lightness(succ, 0.25)
        c11 = adjust_lightness(warn, 0.25)
        c12 = adjust_lightness(accent, 0.25)
        c13 = adjust_lightness(accent_muted, 0.25)
        c14 = adjust_lightness(info, 0.25)
        c15 = "#ffffff"
    else:
        c0 = "#1e1e2e"
        c1 = err
        c2 = succ
        c3 = warn
        c4 = accent
        c5 = accent_muted
        c6 = info
        c7 = surface
        c8 = surface_var
        c9 = adjust_lightness(err, -0.2)
        c10 = adjust_lightness(succ, -0.2)
        c11 = adjust_lightness(warn, -0.2)
        c12 = adjust_lightness(accent, -0.2)
        c13 = adjust_lightness(accent_muted, -0.2)
        c14 = adjust_lightness(info, -0.2)
        c15 = "#000000"

    ansi_colors = [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15]

    return {
        "theme": active,
        "is_dark": dark,
        "opacity": opacity,
        "bg": bg,
        "fg": fg,
        "cursor": accent,
        "cursor_text": bg,
        "selection_bg": surface_var,
        "selection_fg": fg,
        "ansi": ansi_colors
    }


def build_osc_sequences(theme_info):
    """Construit la chaîne d'échappement OSC standard (OSC 10, 11, 12, 17, 19, 4)."""
    seqs = []
    # OSC 10: Texte normal (Foreground)
    seqs.append(f"\033]10;{theme_info['fg']}\007")
    # OSC 11: Arrière-plan (Background)
    seqs.append(f"\033]11;{theme_info['bg']}\007")
    # OSC 12: Curseur
    seqs.append(f"\033]12;{theme_info['cursor']}\007")
    # OSC 17: Fond de sélection
    seqs.append(f"\033]17;{theme_info['selection_bg']}\007")
    # OSC 19: Texte de sélection
    seqs.append(f"\033]19;{theme_info['selection_fg']}\007")
    # OSC 4: Palette ANSI 0-15
    for idx, col in enumerate(theme_info["ansi"]):
        seqs.append(f"\033]4;{idx};{col}\007")
    return "".join(seqs)


def garantir_source_bashrc(home):
    """Fait que `~/.bashrc` source le hook, une seule fois.

    Écrire `~/.bashrc.d/10-aethershell-theme.sh` ne suffit pas : Arch ne source
    pas `~/.bashrc.d` par défaut. Mesuré sur la machine — le hook existait,
    `.bashrc` ne le nommait pas, et les nouveaux shells n'avaient donc aucune
    couleur. On ajoute une ligne gardée par un marqueur, sans toucher au reste.
    """
    bashrc = home / ".bashrc"
    if not bashrc.is_file():
        return False
    marqueur = "# AetherShell : couleurs du terminal (généré)"
    try:
        texte = bashrc.read_text(encoding="utf-8")
    except OSError:
        return False
    if marqueur in texte:
        return True
    ajout = (f"\n{marqueur}\n"
             "[ -f \"$HOME/.config/aethershell/terminal-colors.sh\" ] && "
             ". \"$HOME/.config/aethershell/terminal-colors.sh\"\n")
    temporaire = bashrc.with_name(".bashrc.aethershell.tmp")
    try:
        temporaire.write_text(texte.rstrip("\n") + "\n" + ajout, encoding="utf-8")
        os.replace(temporaire, bashrc)
    except OSError:
        return False
    return True


def write_universal_scripts(theme_info, osc_seq):
    home = Path.home()

    # 1. ~/.config/aethershell/terminal-colors.sh
    aether_dir = home / ".config" / "aethershell"
    aether_dir.mkdir(parents=True, exist_ok=True)
    aether_script = aether_dir / "terminal-colors.sh"

    ansi_lines = "\n".join(
        f'        printf \'\\033]4;{i};{c}\\007\'' for i, c in enumerate(theme_info["ansi"])
    )

    content = f"""#!/bin/sh
# AetherShell dynamic terminal palette ({theme_info['theme']})
# Généré automatiquement depuis style_vars.json — ne pas modifier à la main.

if [ -t 1 ] && [ -n "${{TERM:-}}" ] && [ "$TERM" != "dumb" ]; then
    if [ "${{AETHERSHELL_PALETTE_APPLIED:-}}" != "{theme_info['theme']}" ]; then
        export AETHERSHELL_PALETTE_APPLIED="{theme_info['theme']}"
        printf '\\033]10;{theme_info['fg']}\\007'
        printf '\\033]11;{theme_info['bg']}\\007'
        printf '\\033]12;{theme_info['cursor']}\\007'
        printf '\\033]17;{theme_info['selection_bg']}\\007'
        printf '\\033]19;{theme_info['selection_fg']}\\007'
{ansi_lines}
    fi
fi
"""
    _ecrire_atomique(aether_script, content)
    aether_script.chmod(0o755)

    # 2. ~/.bashrc.d/10-aethershell-theme.sh, et la ligne qui le source
    bashrc_d = home / ".bashrc.d"
    bashrc_d.mkdir(parents=True, exist_ok=True)
    bashrc_hook = bashrc_d / "10-aethershell-theme.sh"
    hook_content = f"""# Séquences de couleurs dynamiques AetherShell
if [ -f "$HOME/.config/aethershell/terminal-colors.sh" ]; then
    . "$HOME/.config/aethershell/terminal-colors.sh"
fi
"""
    bashrc_hook.write_text(hook_content, encoding="utf-8")

    # Le hook ne sert à rien si personne ne le source : on s'en assure ici.
    # `.bashrc.d` n'est pas lu par défaut sur Arch.
    garantir_source_bashrc(home)


SHELLS = {"sh", "bash", "zsh", "fish", "dash", "ksh", "mksh", "yash"}


def pty_au_repos(entree):
    """Vrai si ce pty attend sur un shell, faux si un programme y tourne.

    Écrire des séquences dans un pty dont le premier plan est un programme plein
    écran (vim, less, une invite de mot de passe) peut corrompre son affichage.
    On ne touche donc qu'aux terminaux dont le processus de premier plan est un
    shell : c'est là que la diffusion est à la fois utile et sans risque.
    """
    pgid = premier_plan(entree)
    if pgid <= 0:
        return False
    try:
        nom = Path(f"/proc/{pgid}/comm").read_text(encoding="utf-8").strip()
    except OSError:
        return False
    return nom in SHELLS


def premier_plan(entree):
    """pgrp au premier plan d'un pty, sans `tcgetpgrp()`.

    `tcgetpgrp()` est refusé ici — `ENOTTY` sur **tous** les ptys, y compris
    depuis un service utilisateur — alors que `tcgetattr()` passe : c'est
    l'ioctl TIOCGPGRP qui ne l'est pas. Le filtre répondait donc toujours
    « programme au premier plan », et la diffusion n'atteignait aucun terminal.

    `/proc/<pid>/stat` porte la même information : champ 7 = terminal, champ 8 =
    pgrp au premier plan. On renvoie le premier trouvé. Repli sur `tcgetpgrp()`
    si `/proc` est restreint.
    """
    try:
        cible = os.stat(entree).st_rdev
    except OSError:
        return -1
    try:
        for entree_proc in os.listdir("/proc"):
            if not entree_proc.isdigit():
                continue
            try:
                with open(f"/proc/{entree_proc}/stat", "rb") as f:
                    champs = f.read().rsplit(b")", 1)[1].split()
            except (OSError, IndexError):
                continue
            # après « ) » : etat ppid pgrp session tty_nr tpgid …
            try:
                tty_nr = int(champs[4])
                tpgid = int(champs[5])
            except (IndexError, ValueError):
                continue
            if tty_nr == cible and tpgid > 0:
                return tpgid
    except OSError:
        pass
    # Repli : l'ioctl, s'il est permis sur cette machine.
    try:
        fd = os.open(entree, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError:
        return -1
    try:
        return os.tcgetpgrp(fd)
    except (OSError, ValueError):
        return -1
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def broadcast_to_pts(osc_seq):
    """Diffuse la séquence OSC aux pseudoterminaux au repos.

    Rend (mis à jour, ignorés). Un pty est ignoré quand son premier plan n'est
    pas un shell — et un nœud mort de `/dev/pts` répond « pas un tty », donc il
    tombe du même côté. Le compte est publié : sans lui, un filtre trop strict se
    lirait comme « la diffusion ne marche plus », sans rien pour le dire.
    """
    pts_dir = Path("/dev/pts")
    if not pts_dir.is_dir():
        return 0, 0
    uid = os.getuid()
    touchés = 0
    ignorés = 0
    raw_bytes = osc_seq.encode("utf-8")
    for entry in pts_dir.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            st = entry.stat()
        except OSError:
            continue
        if st.st_uid != uid:
            continue
        if not pty_au_repos(entry):
            ignorés += 1
            continue
        try:
            with open(entry, "wb", buffering=0) as f:
                f.write(raw_bytes)
            touchés += 1
        except OSError:
            ignorés += 1
    return touchés, ignorés


def update_ghostty(theme_info):
    ghostty_dir = Path.home() / ".config" / "ghostty"
    ghostty_dir.mkdir(parents=True, exist_ok=True)

    # Thème dans themes/aethershell
    themes_dir = ghostty_dir / "themes"
    themes_dir.mkdir(parents=True, exist_ok=True)
    theme_file = themes_dir / "aethershell"

    lines = [
        f"# AetherShell Ghostty Theme ({theme_info['theme']})",
        f"background = {theme_info['bg']}",
        f"foreground = {theme_info['fg']}",
        f"cursor-color = {theme_info['cursor']}",
        f"cursor-text = {theme_info['cursor_text']}",
        f"selection-background = {theme_info['selection_bg']}",
        f"selection-foreground = {theme_info['selection_fg']}",
    ]
    for idx, col in enumerate(theme_info["ansi"]):
        lines.append(f"palette = {idx}={col}")

    _ecrire_atomique(theme_file, "\n".join(lines) + "\n")

    # Mise à jour de user.conf (theme, background-opacity et background-blur)
    user_conf = ghostty_dir / "user.conf"
    conf_lines = []
    if user_conf.is_file():
        conf_lines = user_conf.read_text(encoding="utf-8").splitlines()

    # Remplacement ou ajout de theme, background-opacity et background-blur
    has_theme = False
    has_opacity = False
    has_blur = False
    new_lines = []
    for line in conf_lines:
        if re.match(r"^\s*theme\s*=", line):
            new_lines.append("theme = aethershell")
            has_theme = True
        elif re.match(r"^\s*background-opacity\s*=", line):
            new_lines.append(f"background-opacity = {theme_info['opacity']}")
            has_opacity = True
        elif re.match(r"^\s*background-blur\s*=", line):
            new_lines.append("background-blur = true")
            has_blur = True
        else:
            new_lines.append(line)

    if not has_blur:
        new_lines.insert(0, "background-blur = true")
    if not has_theme:
        new_lines.append("theme = aethershell")
    if not has_opacity:
        new_lines.append(f"background-opacity = {theme_info['opacity']}")

    _ecrire_atomique(user_conf, "\n".join(new_lines) + "\n")

    # S'assurer que le fichier de config principal (config.ghostty ou config) inclut user.conf
    included = False
    for cfg_name in ["config.ghostty", "config"]:
        cfg_file = ghostty_dir / cfg_name
        if cfg_file.is_file():
            txt = cfg_file.read_text(encoding="utf-8")
            if "user.conf" not in txt:
                _ecrire_atomique(cfg_file, txt.rstrip() + "\n\n# Configuration utilisateur AetherShell\nconfig-file = ?user.conf\n")
            included = True
    if not included:
        _ecrire_atomique(ghostty_dir / "config", "# Configuration Ghostty AetherShell\nconfig-file = ?user.conf\n")


def update_kitty(theme_info):
    kitty_dir = Path.home() / ".config" / "kitty"
    kitty_dir.mkdir(parents=True, exist_ok=True)

    theme_file = kitty_dir / "aethershell-theme.conf"
    lines = [
        f"# AetherShell Kitty Theme ({theme_info['theme']})",
        f"foreground            {theme_info['fg']}",
        f"background            {theme_info['bg']}",
        f"background_opacity    {theme_info['opacity']}",
        f"cursor                {theme_info['cursor']}",
        f"cursor_text_color     {theme_info['cursor_text']}",
        f"selection_foreground  {theme_info['selection_fg']}",
        f"selection_background  {theme_info['selection_bg']}",
        "",
    ]
    for idx, col in enumerate(theme_info["ansi"]):
        lines.append(f"color{idx:<2} {col}")

    _ecrire_atomique(theme_file, "\n".join(lines) + "\n")

    # Inscription dans kitty.conf si présent
    kitty_conf = kitty_dir / "kitty.conf"
    if kitty_conf.is_file():
        txt = kitty_conf.read_text(encoding="utf-8")
        if "aethershell-theme.conf" not in txt:
            _ecrire_atomique(kitty_conf, txt.rstrip() + "\ninclude aethershell-theme.conf\n")

    # Signal SIGUSR1 à tous les processus kitty pour rechargement à chaud
    subprocess.run(["pkill", "-USR1", "-x", "kitty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _ecrire_atomique(chemin, contenu):
    """Écrit un fichier de configuration sans jamais en laisser un à moitié écrit.

    Ces fichiers sont lus au démarrage d'un terminal : un fichier tronqué par un
    arrêt au mauvais moment casse le terminal, pas la couleur.
    """
    temporaire = chemin.with_name("." + chemin.name + ".aethershell.tmp")
    temporaire.write_text(contenu, encoding="utf-8")
    os.replace(temporaire, chemin)


def importer_dans_alacritty(txt):
    """Ajoute l'import du thème au tableau `import` de [general], sans doublon.

    L'ancienne version insérait `import = [...]` juste après `[general]` : quand
    la section en portait déjà un, le fichier avait deux clés `import`, ce que
    TOML refuse — Alacritty ne démarrait plus. On complète le tableau existant.

    Rend (texte, modifié). Un import écrit sur plusieurs lignes n'est pas réécrit :
    on préfère perdre la couleur automatique que la mise en forme du fichier.
    """
    nom = "aethershell-theme.toml"
    lignes = txt.splitlines()
    debut = None
    for i, ligne in enumerate(lignes):
        if ligne.strip() == "[general]":
            debut = i
            break
    if debut is None:
        return '[general]\nimport = ["%s"]\n\n' % nom + txt, True

    fin = len(lignes)
    for j in range(debut + 1, len(lignes)):
        if lignes[j].lstrip().startswith("["):
            fin = j
            break
    for j in range(debut + 1, fin):
        m = re.match(r"^(\s*)import\s*=\s*\[(.*)\]\s*$", lignes[j])
        if m:
            dedans = m.group(2)
            if nom in dedans:
                return txt, False
            gardes = [x for x in re.findall(r"\"([^\"]+)\"", dedans) if x != nom]
            gardes.append(nom)
            lignes[j] = '%simport = [%s]' % (m.group(1),
                                             ", ".join('"%s"' % x for x in gardes))
            return "\n".join(lignes) + "\n", True
        if re.match(r"^\s*import\s*=", lignes[j]):
            return txt, False
    lignes.insert(debut + 1, 'import = ["%s"]' % nom)
    return "\n".join(lignes) + "\n", True


def update_alacritty(theme_info):
    alacritty_dir = Path.home() / ".config" / "alacritty"
    if not alacritty_dir.is_dir():
        alacritty_dir.mkdir(parents=True, exist_ok=True)

    theme_file = alacritty_dir / "aethershell-theme.toml"
    a = theme_info["ansi"]
    content = f"""# AetherShell Alacritty Theme ({theme_info['theme']})

[colors.primary]
background = "{theme_info['bg']}"
foreground = "{theme_info['fg']}"

[colors.cursor]
cursor = "{theme_info['cursor']}"
text = "{theme_info['cursor_text']}"

[colors.selection]
background = "{theme_info['selection_bg']}"
text = "{theme_info['selection_fg']}"

[colors.normal]
black   = "{a[0]}"
red     = "{a[1]}"
green   = "{a[2]}"
yellow  = "{a[3]}"
blue    = "{a[4]}"
magenta = "{a[5]}"
cyan    = "{a[6]}"
white   = "{a[7]}"

[colors.bright]
black   = "{a[8]}"
red     = "{a[9]}"
green   = "{a[10]}"
yellow  = "{a[11]}"
blue    = "{a[12]}"
magenta = "{a[13]}"
cyan    = "{a[14]}"
white   = "{a[15]}"

[window]
opacity = {theme_info['opacity']}
"""
    _ecrire_atomique(theme_file, content)

    # Import dans alacritty.toml si présent
    alacritty_conf = alacritty_dir / "alacritty.toml"
    if alacritty_conf.is_file():
        try:
            txt = alacritty_conf.read_text(encoding="utf-8")
        except OSError:
            return
        nouveau, change = importer_dans_alacritty(txt)
        if not change:
            return
        # Le fichier de l'utilisateur n'est réécrit que si le résultat est du TOML
        # valide : une couleur vaut moins qu'un terminal qui démarre.
        try:
            import tomllib
        except ModuleNotFoundError:
            tomllib = None
        if tomllib is not None:
            try:
                tomllib.loads(nouveau)
            except Exception:
                return
        try:
            _ecrire_atomique(alacritty_conf, nouveau)
        except OSError:
            pass


def update_foot(theme_info):
    foot_dir = Path.home() / ".config" / "foot"
    if not foot_dir.is_dir():
        foot_dir.mkdir(parents=True, exist_ok=True)
    themes_dir = foot_dir / "themes"
    themes_dir.mkdir(parents=True, exist_ok=True)
    theme_file = themes_dir / "aethershell.ini"

    a = [c.lstrip("#") for c in theme_info["ansi"]]
    bg_clean = theme_info["bg"].lstrip("#")
    fg_clean = theme_info["fg"].lstrip("#")

    content = f"""# AetherShell Foot Theme ({theme_info['theme']})
[colors]
alpha={theme_info['opacity']}
foreground={fg_clean}
background={bg_clean}

regular0={a[0]}
regular1={a[1]}
regular2={a[2]}
regular3={a[3]}
regular4={a[4]}
regular5={a[5]}
regular6={a[6]}
regular7={a[7]}

bright0={a[8]}
bright1={a[9]}
bright2={a[10]}
bright3={a[11]}
bright4={a[12]}
bright5={a[13]}
bright6={a[14]}
bright7={a[15]}
"""
    _ecrire_atomique(theme_file, content)


def main():
    parser = argparse.ArgumentParser(description="Synchronise les couleurs du terminal avec le thème AetherShell.")
    parser.add_argument("--broadcast-only", action="store_true", help="Diffuse uniquement les séquences OSC aux /dev/pts existants.")
    args = parser.parse_args()

    style_path = find_style_file()
    if not style_path.is_file():
        sys.exit(f"Erreur : {style_path} introuvable.")

    try:
        with open(style_path, "r", encoding="utf-8") as f:
            style_data = json.load(f)
    except Exception as e:
        sys.exit(f"Erreur lors de la lecture de {style_path} : {e}")

    palette_info = compute_terminal_palette(style_data)
    osc_seq = build_osc_sequences(palette_info)

    # 1. Diffusion directe aux pts actifs
    pts_count, pts_ignores = broadcast_to_pts(osc_seq)

    if args.broadcast_only:
        print(f"OSC diffusé à {pts_count} pseudoterminaux ({pts_ignores} ignorés : programme au premier plan ou nœud mort).")
        return

    # 2. Scripts universels pour nouveaux shells
    write_universal_scripts(palette_info, osc_seq)

    # 3. Émulateurs spécifiques
    update_ghostty(palette_info)
    update_kitty(palette_info)
    update_alacritty(palette_info)
    update_foot(palette_info)

    print(f"Palette '{palette_info['theme']}' appliquée : {pts_count} terminaux mis à jour en direct + configs Ghostty/Kitty/Alacritty/Foot synchronisées.")


if __name__ == "__main__":
    main()
