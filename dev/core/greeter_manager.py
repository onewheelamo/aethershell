#!/usr/bin/env python3
"""Backend du greeter pour le panneau de configuration.

Actions (toutes en JSON sur stdout) :
  list                 — thèmes disponibles, actif, chemins des miniatures
  preview <id>         — aperçu plein écran (fenêtre sddm-greeter en mode test)
  apply <id>           — sélectionne le thème (via le helper polkit)
  refresh              — régénère palette + fond depuis style_vars.json puis applique
  thumbnails [ids…]    — (re)génère les miniatures

L'écriture système passe par /usr/local/bin/greeter-palette (root, polkit) ;
tout ce qui est calcul ou aperçu reste sans privilège.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
THEME = Path("/usr/share/sddm/themes/sddm-astronaut-theme")
THEMES_SYS = Path("/usr/share/sddm/themes")
SDDM_CONF = Path("/etc/sddm.conf.d/10-sddm-theme.conf")
QYLOCK_CACHE = HOME / ".local/share/qylock-themes"
HELPER = "/usr/local/bin/greeter-palette"
THUMBS = HOME / ".cache/quickshell/greeter-thumbs"
GENERATE = HOME / "dev/quickshell_todo/dev/sddm/generate.py"
DEV_SDDM = HOME / "dev/quickshell_todo/dev/sddm"

# Libellés : les identifiants viennent des noms de fichiers du thème.
LABELS = {
    "palette": "Palette de la session",
    "astronaut": "Astronaut",
    "black_hole": "Trou noir",
    "cyberpunk": "Cyberpunk",
    "hyprland_kath": "Hyprland Kath",
    "jake_the_dog": "Jake the Dog",
    "japanese_aesthetic": "Esthétique japonaise",
    "pixel_sakura": "Pixel Sakura",
    "pixel_sakura_static": "Pixel Sakura (statique)",
    "post-apocalyptic_hacker": "Hacker post-apo",
    "purple_leaves": "Feuilles pourpres",
}


def fail(msg, code=1):
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(code)


def current_theme():
    """Dossier de thème sélectionné par SDDM (notre drop-in `Current=`)."""
    try:
        for line in SDDM_CONF.read_text().splitlines():
            if line.startswith("Current="):
                return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return THEME.name


def active_id():
    """Identifiant de la conf réellement sélectionnée dans metadata.desktop."""
    meta = THEME / "metadata.desktop"
    if not meta.exists():
        return ""
    for line in meta.read_text().splitlines():
        if line.startswith("ConfigFile="):
            return Path(line.split("=", 1)[1].strip()).stem
    return ""


def qylock_label(ident):
    """`material-you-dark` → « Material you dark » (pas de titre marketing)."""
    return ident.replace("-", " ").replace("_", " ").strip().capitalize()


def qylock_installed():
    """{nom: chemin} des thèmes qylock installés à côté d'astronaut.

    Le filtre est l'auteur déclaré dans metadata.desktop : `/usr/share/sddm/
    themes` contient aussi les thèmes du système (breeze, elarun, Muse…), et
    les proposer ici les ferait passer pour les nôtres.
    """
    out = {}
    if THEMES_SYS.is_dir():
        for d in sorted(THEMES_SYS.iterdir()):
            meta = d / "metadata.desktop"
            if not d.is_dir() or d == THEME or not (d / "Main.qml").exists():
                continue
            try:
                if "Author=Darkkal44" in meta.read_text():
                    out[d.name] = d
            except OSError:
                continue
    return out


def qylock_cached():
    """{nom installable: (dossier source, installé ?)} depuis le cache local.

    Un thème est un dossier plat, sauf `clockwork` qui en contient trois : ces
    variantes s'installent aplaties en `<thème>-<variante>`, seul moyen pour
    SDDM de les sélectionner (Current= ne nomme qu'un dossier de premier
    niveau).
    """
    out = {}
    if not QYLOCK_CACHE.is_dir():
        return out
    for root in sorted(QYLOCK_CACHE.iterdir()):
        if not root.is_dir():
            continue
        cands = [root] if (root / "metadata.desktop").exists() else []
        cands += [s for s in sorted(root.iterdir())
                  if s.is_dir() and (s / "metadata.desktop").exists()]
        for src in cands:
            name = root.name if src == root else f"{root.name}-{src.name}"
            out[name] = (src, (THEMES_SYS / name).exists())
    return out


def presets():
    cur = current_theme()
    out = []
    for conf in sorted((THEME / "Themes").glob("*.conf")):
        ident = conf.stem
        thumb = THUMBS / f"{ident}.png"
        out.append({
            "id": ident,
            "name": LABELS.get(ident, ident.replace("_", " ").capitalize()),
            "thumb": str(thumb) if thumb.exists() else "",
            "active": cur == THEME.name and ident == active_id(),
            "kind": "astronaut",
        })
    # Thèmes complets (qylock) : ceux installés, puis ceux seulement récupérés.
    merged = qylock_cached()
    for ident, d in qylock_installed().items():
        merged.setdefault(ident, (d, True))
    for ident, (src, installed) in sorted(merged.items()):
        thumb = THUMBS / f"{ident}.png"
        out.append({
            "id": ident,
            "name": qylock_label(ident) + ("" if installed else " (à installer)"),
            "thumb": str(thumb) if thumb.exists() else "",
            "active": installed and ident == cur,
            "kind": "qylock",
            "installed": installed,
        })
    # « palette » en tête : c'est la palette de la session. Puis astronaut, puis
    # les thèmes fixes.
    out.sort(key=lambda p: (p["id"] != "palette", p["kind"] != "astronaut",
                            p["name"].lower()))
    return out


# Ajouté à la seule copie jetable de l'aperçu, jamais au thème installé.
# Le mode test n'a aucun socket d'authentification : la fenêtre ne peut pas
# ouvrir de session, mais elle est plein écran, identique au vrai greeter, et un
# mot de passe tapé dedans se perd sans le moindre message. Le bandeau le dit ;
# la sortie au clavier, elle, ne peut pas venir de QML (`Qt.quit()` s'exécute
# sans arrêter sddm-greeter) mais du compositeur : binds.lua lie Échap à
# core/greeter_preview.sh stop.
PREVIEW_ESCAPE = """
    // Aperçu du panneau : ne fait pas partie du thème installé.
    Rectangle {
        id: previewHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: previewHintLabel.implicitWidth + 28
        height: previewHintLabel.implicitHeight + 14
        radius: 8
        color: "#e6050b12"
        border.width: 1
        border.color: "#40f0f5ff"

        Text {
            id: previewHintLabel
            anchors.centerIn: parent
            text: "Aperçu — la connexion est désactivée · Échap pour fermer"
            color: "#f0f5ff"
            font.pixelSize: 13
        }
    }
"""


def inject_preview_escape(theme_dir):
    """Insère le bandeau + le raccourci Échap dans le Main.qml de la copie.

    L'insertion se fait juste avant l'accolade qui ferme l'objet racine
    (`Pane`), donc au même niveau que ses autres enfants. Échec silencieux
    volontaire : un aperçu sans bandeau reste préférable à un aperçu qui ne
    s'ouvre pas — mais l'équilibre des accolades est vérifié pour éviter
    d'écrire un fichier que QML refuserait de charger.
    """
    main = Path(theme_dir) / "Main.qml"
    try:
        text = main.read_text()
    except OSError:
        return False
    end = text.rstrip()
    if not end.endswith("}"):
        return False
    patched = end[:-1] + PREVIEW_ESCAPE + "}\n"
    if patched.count("{") != patched.count("}"):
        return False
    main.write_text(patched)
    return True


def preview(ident):
    """Ouvre le greeter en mode test sur une copie jetable du thème.

    La copie est nécessaire : le mode test suit `metadata.desktop`, et l'on veut
    prévisualiser n'importe quelle conf sans toucher à la sélection réelle.
    """
    conf = THEME / "Themes" / f"{ident}.conf"
    qylock = qylock_cached().get(ident)
    installed = qylock_installed().get(ident)
    src = installed or (qylock[0] if qylock else None)
    if src is None and not conf.exists():
        fail(f"configuration inconnue : {ident}")
    # Même volume que /usr, sinon `cp -al` échoue (liens durs inter-périphériques).
    tmp = Path(tempfile.mkdtemp(prefix="greeter-preview-", dir="/var/tmp"))
    # Liens durs impossibles (fichiers root, fs.protected_hardlinks=1) : copie
    # réelle, reflink quand le volume est en copy-on-write.
    if src is not None:
        # Thème complet (qylock) : sa metadata porte déjà son ConfigFile.
        subprocess.run(["cp", "-a", "--reflink=auto", f"{src}/.", str(tmp)], check=True)
    else:
        subprocess.run(["cp", "-a", "--reflink=auto", f"{THEME}/.", str(tmp)], check=True)
        meta = tmp / "metadata.desktop"
        lines = []
        for line in meta.read_text().splitlines():
            if line.startswith("ConfigFile="):
                line = f"ConfigFile=Themes/{ident}.conf"
            lines.append(line)
        meta.write_text("\n".join(lines) + "\n")
    inject_preview_escape(tmp)

    env = dict(os.environ)
    env["QT_QPA_PLATFORM"] = "wayland"
    # Le lancement passe par core/greeter_preview.sh : il enregistre le PID pour
    # que Échap (lié dans binds.lua) puisse refermer la fenêtre, et il supprime
    # la copie jetable. Le délai reste le filet si personne n'appuie.
    wrapper = Path(__file__).with_name("greeter_preview.sh")
    subprocess.Popen(["sh", str(wrapper), "start", str(tmp), "45"], env=env,
                     start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps({"ok": True, "preview": ident}))


def helper(*args):
    res = subprocess.run(["pkexec", HELPER, *args], capture_output=True, text=True)
    return res.returncode == 0, (res.stdout + res.stderr).strip()


def apply(ident):
    # Thème complet déjà installé (qylock) : le helper sélectionne le dossier.
    if ident != THEME.name and (THEMES_SYS / ident / "metadata.desktop").exists():
        ok, out = helper("apply", ident)
        if not ok:
            fail(f"sélection refusée : {out[:200]}")
        print(json.dumps({"ok": True, "applied": ident, "message": out}))
        return
    if ident in qylock_cached():
        fail(f"thème récupéré mais pas installé : bash dev/sddm/install.sh --qylock {ident}")
    if not (THEME / "Themes" / f"{ident}.conf").exists():
        fail(f"configuration inconnue : {ident}")
    if ident == "palette":
        # La palette peut avoir changé depuis la dernière installation.
        gen = subprocess.run([sys.executable, str(GENERATE)], capture_output=True, text=True)
        if gen.returncode != 0:
            fail(f"génération impossible : {gen.stderr.strip()[:200]}")
        ok, out = helper("set-palette", str(DEV_SDDM / "out/Themes/palette.conf"),
                         str(DEV_SDDM / "out/Backgrounds/wallpaper.png"))
        if not ok:
            fail(f"installation de la palette refusée : {out[:200]}")
    ok, out = helper("apply", ident)
    if not ok:
        fail(f"sélection refusée : {out[:200]}")
    print(json.dumps({"ok": True, "applied": ident, "message": out}))


def sources(ids):
    """(id, dossier source, type) de tout ce que l'on sait prévisualiser.

    Sortie TSV pour dev/sddm/thumbnails.sh : les confs du thème astronaut
    vivent toutes dans le même dossier (c'est metadata.desktop qu'on pointe),
    un thème qylock est un dossier complet.
    """
    rows = [(c.stem, str(THEME), "astronaut")
            for c in sorted((THEME / "Themes").glob("*.conf"))]
    merged = {}
    for ident, (src, _installed) in qylock_cached().items():
        merged[ident] = str(src)          # le cache est à l'utilisateur : lisible
    for ident, d in qylock_installed().items():
        merged.setdefault(ident, str(d))  # installé sans cache (cache purgé)
    rows += [(ident, merged[ident], "qylock") for ident in sorted(merged)]
    if ids:
        rows = [r for r in rows if r[0] in ids]
    for row in rows:
        print("\t".join(row))


def thumbnails(ids):
    script = DEV_SDDM / "thumbnails.sh"
    if not script.exists():
        fail("thumbnails.sh absent")
    cmd = ["bash", str(script), *ids] if ids else ["bash", str(script)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(json.dumps({"ok": res.returncode == 0, "ids": ids,
                      "message": (res.stdout + res.stderr).strip()[-400:]}))


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "list"
    if action == "list":
        print(json.dumps({
            "ok": True,
            "theme": str(THEME),
            # Thème actif : un id de conf quand c'est astronaut, le nom du
            # dossier quand un thème complet (qylock) est sélectionné.
            "active": (active_id() if current_theme() == THEME.name
                       else current_theme()),
            "current": current_theme(),
            "thumb_dir": str(THUMBS),
            "helper": Path(HELPER).exists(),
            "presets": presets(),
        }, ensure_ascii=False))
    elif action == "preview" and len(sys.argv) > 2:
        preview(sys.argv[2])
    elif action == "apply" and len(sys.argv) > 2:
        apply(sys.argv[2])
    elif action == "refresh":
        apply("palette")
    elif action == "thumbnails":
        thumbnails(sys.argv[2:])
    elif action == "sources":
        sources(sys.argv[2:])
    else:
        fail(f"action inconnue : {action}")


if __name__ == "__main__":
    main()
