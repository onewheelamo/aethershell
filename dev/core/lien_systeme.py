#!/usr/bin/env python3
"""Faire connaître au système les programmes par défaut du shell.

`core/app_vars.json` ne parlait qu'au shell et à Hyprland (`programs.lua`).
Résultat : Thunar, lancé depuis Hyprland, ne savait pas quel terminal ouvrir —
« Could not find fallback TerminalEmulator application » — parce que le système
n'a rien à voir avec nos variables.

Ce script comble le fossé dans l'autre sens : il lit `app_vars.json` et écrit les
deux registres que le reste du monde consulte.

  • `~/.config/xfce4/helpers.rc` — ce que lit `exo-open` (donc le clic droit de
    Thunar, Xarchiver, etc.). Une ligne par rôle : `TerminalEmulator=ghostty`.
  • `~/.config/mimeapps.list` — les associations par type MIME, pour
    `xdg-open` et tous les programmes GTK/Qt qui suivent la spécification.

Les autres lignes de `mimeapps.list` ne sont pas touchées : on ne réécrit que
les types qui correspondent à un rôle connu, et seulement ceux dont le
programme a été trouvé sur la machine.

CLI :
    lien_systeme.py --appliquer     écrit les deux registres
    lien_systeme.py --etat          montre ce qui serait écrit, sans rien écrire
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
APP_VARS = BASE_DIR / "app_vars.json"
HELPERS = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "xfce4" / "helpers.rc"
# Aides d'exo : sans ces fichiers `.rc`, `helpers.rc` ne suffit pas — exo cherche
# l'aide qui porte le nom qu'on lui donne, et sur cette machine le paquet n'en
# installe aucune (`/usr/share/xfce4/helpers` n'existe pas).
AIDES = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "xfce4" / "helpers"
MIMEAPPS = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "mimeapps.list"

# Dossiers où chercher les fichiers .desktop, du plus prioritaire au moins.
DESKTOP_DIRS = [
    Path.home() / ".local" / "share" / "applications",
    Path("/usr/share/applications"),
    Path("/var/lib/flatpak/exports/share/applications"),
    Path.home() / ".local" / "share" / "flatpak" / "exports" / "share" / "applications",
]

# Rôle du shell → clé d'exo et types MIME associés.
ROLES = {
    "Terminal": {
        "exo": "TerminalEmulator",
        "mimes": ["application/x-terminal-emulator"],
        "categories": ["TerminalEmulator"],
    },
    "Files": {
        "exo": "FileManager",
        "mimes": ["inode/directory"],
        "categories": ["FileManager"],
    },
    "Browser": {
        "exo": "WebBrowser",
        "mimes": ["x-scheme-handler/http", "x-scheme-handler/https",
                  "text/html", "application/xhtml+xml"],
        "categories": ["WebBrowser"],
    },
    "Browser2": {
        "exo": None,
        "mimes": ["x-scheme-handler/http", "x-scheme-handler/https"],
        "categories": ["WebBrowser"],
        "secondaire": True,
    },
    "Editor": {
        "exo": "TextEditor",
        "mimes": ["text/plain"],
        "categories": ["TextEditor", "Development"],
    },
    "Video": {
        "exo": "VideoPlayer",
        "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime"],
        "categories": ["Player", "Video"],
    },
    "Music": {
        "exo": "AudioPlayer",
        "mimes": ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav"],
        "categories": ["Audio", "Player"],
    },
    "Images": {
        "exo": "ImageViewer",
        "mimes": ["image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml"],
        "categories": ["Viewer", "Graphics"],
    },
}


# Comment demander à chaque terminal de démarrer dans un dossier donné. exo
# passe le dossier en argument au binaire de l'aide ; sans cette traduction, le
# terminal l'ignore et s'ouvre là où le bureau a été lancé.
OPTIONS_DOSSIER = {
    "ghostty": "--working-directory={d}",
    "kitty": "--directory={d}",
    "alacritty": "--working-directory={d}",
    "foot": "--working-directory={d}",
    "konsole": "--workdir {d}",
    "gnome-terminal": "--working-directory={d}",
    "xfce4-terminal": "--working-directory={d}",
    "terminator": "--working-directory={d}",
    "urxvt": "-cd {d}",
    "xterm": "-e sh -c 'cd \"{d}\" && exec $SHELL'",
    "wezterm": "start --cwd {d}",
    "tilix": "--working-directory={d}",
    "kgx": "--working-directory={d}",
    "ptyxis": "--working-directory={d}",
}
LANGEURS = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))) / "aethershell" / "lanceurs"


def ecrire_lanceur(binaire, dossier_lanceurs=None):
    """Écrit un lanceur qui sait ouvrir le terminal dans un dossier.

    exo appelle le binaire de son aide en lui passant le dossier en argument.
    Les terminaux ne partagent pas la même option pour cela, et certains
    l'ignorent complètement : ce petit script traduit un argument en l'option du
    terminal, et se comporte comme le terminal nu quand il n'y a rien à traduire.
    Rend le chemin du lanceur, ou None si le terminal est inconnu (on garde alors
    le binaire d'origine, quitte à perdre le dossier).
    """
    gabarit = OPTIONS_DOSSIER.get(binaire)
    if not gabarit:
        return None
    dossier = Path(dossier_lanceurs or LANGEURS)
    dossier.mkdir(parents=True, exist_ok=True)
    chemin = dossier / ("terminal-" + binaire)
    script = """#!/bin/sh
# Lanceur généré par core/lien_systeme.py — ne pas éditer à la main.
# exo (clic droit « Ouvrir un terminal ici ») passe le dossier en argument ;
# %(binaire)s n'a pas la même option pour ça, d'où cette traduction.
if [ -n "$1" ] && [ -d "$1" ]; then
    dossier=$1
    shift
    set -- %(option)s
fi
if [ -n "$LIEN_DRY_RUN" ]; then
    echo %(binaire)s "$@"
    pwd
    exit 0
fi
exec %(binaire)s "$@"
""" % {"binaire": binaire, "option": gabarit.format(d='"$dossier"')}
    chemin.write_text(script, encoding="utf-8")
    chemin.chmod(0o755)
    return chemin


def lire_desktop(chemin):
    """Rend (id, nom, exec, categories) d'un fichier .desktop, ou None."""
    try:
        texte = chemin.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    entete = texte.split("[Desktop Entry]", 1)
    if len(entete) != 2:
        return None
    corps = entete[1].split("\n[", 1)[0]
    champs = {}
    for ligne in corps.split("\n"):
        if "=" not in ligne or ligne.lstrip().startswith("#"):
            continue
        cle, valeur = ligne.split("=", 1)
        champs.setdefault(cle.strip(), valeur.strip())
    if champs.get("NoDisplay", "").lower() == "true" or champs.get("Hidden", "").lower() == "true":
        return None
    if champs.get("Type", "Application") != "Application":
        return None
    return {
        "id": chemin.name,
        "nom": champs.get("Name", ""),
        "exec": champs.get("Exec", ""),
        "categories": [c for c in champs.get("Categories", "").split(";") if c],
        "mimes": [m for m in champs.get("MimeType", "").split(";") if m],
    }


def tous_desktop():
    vus = []
    for dossier in DESKTOP_DIRS:
        if not dossier.is_dir():
            continue
        for chemin in sorted(dossier.glob("*.desktop")):
            entree = lire_desktop(chemin)
            if entree:
                vus.append(entree)
    return vus


def resoudre(nom, categories, entrees):
    """Trouve le .desktop d'un programme nommé `ghostty`, `thunar`, `code`…

    Trois passes, de la plus stricte à la plus large : le nom exact du binaire
    dans `Exec`, l'identifiant du fichier, puis le nom affiché. La catégorie sert
    d'arbitre quand plusieurs candidats restent (deux navigateurs, par exemple).
    """
    nom = (nom or "").strip().lower()
    if not nom:
        return None
    candides = []
    for e in entrees:
        exec_base = re.split(r"[\s/]", e["exec"].replace('"', "").strip())[0]
        exec_base = Path(exec_base).name.lower()
        identifiant = e["id"].lower().removesuffix(".desktop")
        if nom in (exec_base, identifiant) or identifiant.endswith("." + nom) or identifiant.endswith("-" + nom):
            candides.append(e)
    if not candides:
        for e in entrees:
            if nom == e["nom"].lower():
                candides.append(e)
    if not candides and len(nom) >= 4:
        # Dernier recours : l'identifiant commence par le nom demandé
        # (« code » → `code-oss.desktop`). Borné à quatre lettres pour ne pas
        # attraper `mpv` → `mpvv` n'importe quoi.
        for e in entrees:
            identifiant = e["id"].lower().removesuffix(".desktop")
            if identifiant.startswith(nom) or identifiant.split(".")[-1].startswith(nom):
                candides.append(e)
    if not candides:
        return None
    # Priorité à celui qui porte la bonne catégorie freedesktop.
    for e in candides:
        if any(c in e["categories"] for c in categories):
            return e
    return candides[0]


def construire(apps, entrees):
    """Rend (lignes helpers.rc, {mime: id desktop}) sans rien écrire."""
    helpers, mimes, aides, binaires = {}, {}, {}, {}
    for role, regle in ROLES.items():
        nom = apps.get(role)
        if not nom:
            continue
        entree = resoudre(nom, regle["categories"], entrees)
        if not entree:
            continue
        if regle.get("exo"):
            binaire = Path(re.split(r"[\s/]", entree["exec"].replace('"', "").strip())[0]).name
            identifiant = binaire or Path(entree["id"]).stem
            # Terminal : on passe par un lanceur qui sait ouvrir dans un dossier.
            if role == "Terminal":
                lanceur = ecrire_lanceur(binaire)
                if lanceur:
                    # L'aide porte le nom du lanceur ; c'est `X-XFCE-Binaries`
                    # qui pointe son chemin absolu (exo accepte les deux).
                    identifiant = lanceur.name
                    binaire = str(lanceur)
            # KDE et GNOME attendent une **commande**, pas un identifiant d'aide :
            # ils reçoivent donc le chemin complet du lanceur.
            binaires[regle["exo"]] = binaire
            helpers[regle["exo"]] = identifiant
            aides[identifiant] = {
                "nom": entree["nom"] or identifiant,
                "categorie": regle["categories"][0],
                "icone": Path(entree["id"]).stem,
                "binaire": binaire,
            }
        for mime in regle["mimes"]:
            # Le premier rôle qui revendique un type gagne : Browser2 ne doit pas
            # écraser le navigateur principal sur http/https.
            mimes.setdefault(mime, entree["id"])
    return helpers, mimes, aides, binaires


def ecrire_helpers(helpers):
    lignes = []
    if HELPERS.is_file():
        lignes = [l for l in HELPERS.read_text(encoding="utf-8").split("\n")
                  if l.strip() and l.split("=", 1)[0].strip() not in helpers]
    for cle, valeur in helpers.items():
        lignes.append("%s=%s" % (cle, valeur))
    HELPERS.parent.mkdir(parents=True, exist_ok=True)
    HELPERS.write_text("\n".join(lignes) + "\n", encoding="utf-8")


def ecrire_aides(aides):
    """Écrit un fichier d'aide exo par rôle (`~/.local/share/xfce4/helpers/*.rc`).

    Format attendu par exo : un `Type=X-XFCE-Helper`, une catégorie et le nom du
    binaire. C'est ce fichier que `helpers.rc` désigne ensuite par son nom.
    """
    AIDES.mkdir(parents=True, exist_ok=True)
    for identifiant, aide in aides.items():
        contenu = [
            "[Desktop Entry]",
            "Version=1.0",
            "Encoding=UTF-8",
            "Type=X-XFCE-Helper",
            "Name=%s" % aide["nom"],
            "Icon=%s" % aide["icone"],
            "X-XFCE-Category=%s" % aide["categorie"],
            "X-XFCE-Binaries=%s;" % aide["binaire"],
            "",
        ]
        (AIDES / ("%s.rc" % identifiant)).write_text("\n".join(contenu), encoding="utf-8")


def ecrire_mimeapps(mimes):
    """Met à jour [Default Applications] sans toucher aux autres sections."""
    sections = {}
    ordre = []
    courant = None
    if MIMEAPPS.is_file():
        for ligne in MIMEAPPS.read_text(encoding="utf-8").split("\n"):
            if ligne.strip().startswith("[") and ligne.strip().endswith("]"):
                courant = ligne.strip()[1:-1]
                ordre.append(courant)
                sections.setdefault(courant, [])
            elif courant is not None and ligne.strip():
                sections[courant].append(ligne)
    cible = "Default Applications"
    if cible not in sections:
        ordre.insert(0, cible)
        sections[cible] = []
    restantes = [l for l in sections[cible]
                 if l.split("=", 1)[0].strip() not in mimes]
    for mime, identifiant in mimes.items():
        restantes.append("%s=%s" % (mime, identifiant))
    sections[cible] = restantes

    sortie = []
    for nom in ordre:
        sortie.append("[%s]" % nom)
        sortie.extend(sections[nom])
        sortie.append("")
    MIMEAPPS.write_text("\n".join(sortie).rstrip("\n") + "\n", encoding="utf-8")


def couche_bureau(binaires, mimes):
    """Pose les mêmes choix dans les registres propres à chaque bureau.

    `mimeapps.list` est la couche commune (freedesktop) : tous les bureaux la
    lisent. Certains gardent en plus leur propre clé — KDE dans `kdeglobals`,
    GNOME dans gsettings, Xfce dans exo (déjà traité plus haut). On écrit
    seulement si l'outil existe : rien à installer, rien à casser ailleurs.
    """
    faits = {}

    id_browser = None
    for mime in ("x-scheme-handler/https", "text/html"):
        if mime in mimes:
            id_browser = mimes[mime]
            break
    if id_browser and shutil.which("xdg-settings"):
        r = subprocess.run(["xdg-settings", "set", "default-web-browser", id_browser],
                           capture_output=True, text=True)
        faits["xdg-settings"] = "navigateur → %s" % id_browser if r.returncode == 0 else "échec"

    if shutil.which("kwriteconfig6"):
        commandes = []
        terminal = binaires.get("TerminalEmulator")
        if terminal:
            commandes.append(["kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                              "--key", "TerminalApplication", terminal])
        if id_browser:
            commandes.append(["kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                              "--key", "BrowserApplication", id_browser])
        faits["kde"] = 0
        for cmd in commandes:
            if subprocess.run(cmd, check=False).returncode == 0:
                faits["kde"] += 1

    if shutil.which("gsettings"):
        schema = subprocess.run(["gsettings", "get", "org.gnome.desktop.default-applications.terminal",
                                 "exec"], capture_output=True, text=True)
        terminal = binaires.get("TerminalEmulator")
        if schema.returncode == 0 and terminal:
            subprocess.run(["gsettings", "set", "org.gnome.desktop.default-applications.terminal",
                            "exec", terminal], check=False)
            faits["gnome"] = terminal
    return faits


def appliquer(silencieux=False):
    if not APP_VARS.is_file():
        sys.exit("app_vars.json introuvable : %s" % APP_VARS)
    apps = json.loads(APP_VARS.read_text(encoding="utf-8"))
    entrees = tous_desktop()
    helpers, mimes, aides, binaires = construire(apps, entrees)
    ecrire_aides(aides)
    ecrire_helpers(helpers)
    ecrire_mimeapps(mimes)
    bureaux = couche_bureau(binaires, mimes)
    # `xdg-open`/GLib gardent un cache : on le rafraîchit pour que le prochain
    # clic droit voie les associations sans attendre une reconnexion.
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", "-q",
                        str(Path.home() / ".local" / "share" / "applications")],
                       check=False)
    if not silencieux:
        print(json.dumps({"ok": True, "helpers": helpers, "aides": sorted(aides),
                          "mimes": len(mimes), "bureaux": bureaux}, ensure_ascii=False))


def etat():
    apps = json.loads(APP_VARS.read_text(encoding="utf-8")) if APP_VARS.is_file() else {}
    entrees = tous_desktop()
    helpers, mimes, aides, binaires = construire(apps, entrees)
    manquants = [role for role in ROLES
                 if apps.get(role) and not resoudre(apps[role], ROLES[role]["categories"], entrees)]
    print(json.dumps({"app_vars": apps, "helpers": helpers, "mimes": mimes,
                      "introuvables": manquants}, ensure_ascii=False, indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--appliquer", action="store_true", help="écrit helpers.rc et mimeapps.list")
    ap.add_argument("--etat", action="store_true", help="montre sans écrire")
    a = ap.parse_args()
    if a.etat:
        etat()
    elif a.appliquer:
        appliquer()
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
