#!/usr/bin/env python3
"""Backend du greeter pour le panneau de configuration.

Actions (toutes en JSON sur stdout) :
  list                 — thèmes disponibles, actif, chemins des miniatures
  preview <id>         — aperçu plein écran (fenêtre sddm-greeter en mode test)
  apply <id>           — sélectionne le thème (via le helper polkit)
  refresh              — régénère palette + fond depuis style_vars.json puis applique
  thumbnails [ids…]    — (re)génère les miniatures

L'écriture système passe par /usr/local/bin/portable-greeter (root, polkit) ;
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
HELPER = "/usr/local/bin/portable-greeter"
THUMBS = HOME / ".cache/quickshell/greeter-thumbs"
GENERATE = HOME / "dev/quickshell_todo/dev/sddm/generate.py"
DEV_SDDM = HOME / "dev/quickshell_todo/dev/sddm"

# Libellés : les identifiants viennent des noms de fichiers du thème.
LABELS = {
    "portable": "Portable (palette Matugen)",
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


def active_id():
    """Identifiant de la conf réellement sélectionnée dans metadata.desktop."""
    meta = THEME / "metadata.desktop"
    if not meta.exists():
        return ""
    for line in meta.read_text().splitlines():
        if line.startswith("ConfigFile="):
            return Path(line.split("=", 1)[1].strip()).stem
    return ""


def presets():
    out = []
    for conf in sorted((THEME / "Themes").glob("*.conf")):
        ident = conf.stem
        thumb = THUMBS / f"{ident}.png"
        out.append({
            "id": ident,
            "name": LABELS.get(ident, ident.replace("_", " ").capitalize()),
            "thumb": str(thumb) if thumb.exists() else "",
            "active": ident == active_id(),
        })
    # « portable » en tête : c'est la palette de la session.
    out.sort(key=lambda p: (p["id"] != "portable", p["name"].lower()))
    return out


def preview(ident):
    """Ouvre le greeter en mode test sur une copie jetable du thème.

    La copie est nécessaire : le mode test suit `metadata.desktop`, et l'on veut
    prévisualiser n'importe quelle conf sans toucher à la sélection réelle.
    """
    conf = THEME / "Themes" / f"{ident}.conf"
    if not conf.exists():
        fail(f"configuration inconnue : {ident}")
    # Même volume que /usr, sinon `cp -al` échoue (liens durs inter-périphériques).
    tmp = Path(tempfile.mkdtemp(prefix="portable-greeter-preview-", dir="/var/tmp"))
    # Liens durs impossibles (fichiers root, fs.protected_hardlinks=1) : copie
    # réelle, reflink quand le volume est en copy-on-write.
    subprocess.run(["cp", "-a", "--reflink=auto", f"{THEME}/.", str(tmp)], check=True)
    meta = tmp / "metadata.desktop"
    lines = []
    for line in meta.read_text().splitlines():
        if line.startswith("ConfigFile="):
            line = f"ConfigFile=Themes/{ident}.conf"
        lines.append(line)
    meta.write_text("\n".join(lines) + "\n")

    env = dict(os.environ)
    env["QT_QPA_PLATFORM"] = "wayland"
    # Fenêtre plein écran 1920×1080 ; `timeout` la referme seule et la copie
    # jetable est supprimée avec elle.
    script = (
        f"timeout 45 sddm-greeter-qt6 --test-mode --theme {tmp}; "
        f"rm -rf {tmp}"
    )
    subprocess.Popen(["sh", "-c", script], env=env, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(json.dumps({"ok": True, "preview": ident}))


def helper(*args):
    res = subprocess.run(["pkexec", HELPER, *args], capture_output=True, text=True)
    return res.returncode == 0, (res.stdout + res.stderr).strip()


def apply(ident):
    if not (THEME / "Themes" / f"{ident}.conf").exists():
        fail(f"configuration inconnue : {ident}")
    if ident == "portable":
        # La palette peut avoir changé depuis la dernière installation.
        gen = subprocess.run([sys.executable, str(GENERATE)], capture_output=True, text=True)
        if gen.returncode != 0:
            fail(f"génération impossible : {gen.stderr.strip()[:200]}")
        ok, out = helper("set-palette", str(DEV_SDDM / "out/Themes/portable.conf"),
                         str(DEV_SDDM / "out/Backgrounds/portable.png"))
        if not ok:
            fail(f"installation de la palette refusée : {out[:200]}")
    ok, out = helper("apply", ident)
    if not ok:
        fail(f"sélection refusée : {out[:200]}")
    print(json.dumps({"ok": True, "applied": ident, "message": out}))


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
            "active": active_id(),
            "thumb_dir": str(THUMBS),
            "helper": Path(HELPER).exists(),
            "presets": presets(),
        }, ensure_ascii=False))
    elif action == "preview" and len(sys.argv) > 2:
        preview(sys.argv[2])
    elif action == "apply" and len(sys.argv) > 2:
        apply(sys.argv[2])
    elif action == "refresh":
        apply("portable")
    elif action == "thumbnails":
        thumbnails(sys.argv[2:])
    else:
        fail(f"action inconnue : {action}")


if __name__ == "__main__":
    main()
