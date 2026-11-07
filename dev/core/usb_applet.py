#!/usr/bin/env python3
"""Applet « Périphériques » : clés USB, cartes SD, disques optiques.

Trois sources du noyau, **aucun processus de fond** (même choix que le plugin
`usb-manager` de Noctalia) :

  /sys/block/*                 disques et partitions : taille, amovible, type
  /run/udev/data/b<maj:min>    bus, modèle, système de fichiers, étiquette
  /proc/self/mountinfo         ce qui est monté où, apparié par maj:min
  /proc/swaps                  les partitions d'échange ne sont jamais proposées
                               au retrait

Les actions passent par udisks2 : `udisksctl` pour monter, démonter, déverrouiller,
verrouiller et couper l'alimentation, `gdbus` pour `Drive.Eject` — éjecter une
carte ou un disque n'a pas d'équivalent dans `udisksctl`.

    python3 usb_applet.py etat              # ce que la barre et le panneau lisent
    python3 usb_applet.py monter /dev/sdb1
    python3 usb_applet.py demonter /dev/sdb1
    python3 usb_applet.py deverrouiller /dev/sdb1 --phrase « … »
    python3 usb_applet.py retirer sdb       # coupe l'alimentation ou éjecte
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

DELAI = 6
# Montages qu'on ne touche pas : le système tourne dessus.
SYSTEME = ("/", "/boot", "/boot/efi", "/home", "/var", "/usr", "/etc", "/nix")
# Un disque sans taille n'est pas un disque : baie de carte vide, lecteur optique
# vide. Les afficher ferait une ligne morte dans le panneau.
TAILLE_MIN = 1024 * 1024


# ── lecture du noyau ──────────────────────────────────────────────────────────
def _lire(chemin):
    try:
        with open(chemin, "r", encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return ""


def _nombre(chemin, defaut=0):
    try:
        return int(_lire(chemin))
    except ValueError:
        return defaut


def _decoder(valeur):
    """Les valeurs udev échappent les espaces en `\\x20`, entre autres."""
    if not valeur:
        return ""
    sortie = []
    i = 0
    while i < len(valeur):
        if valeur[i] == "\\" and valeur[i + 1:i + 4].startswith("x"):
            try:
                sortie.append(chr(int(valeur[i + 2:i + 4], 16)))
                i += 4
                continue
            except ValueError:
                pass
        sortie.append(valeur[i])
        i += 1
    return "".join(sortie)


def _proprietes_udev(majmin):
    """{clé: valeur} depuis /run/udev/data — la seule source du bus et de l'étiquette."""
    props = {}
    for ligne in _lire("/run/udev/data/b%s" % majmin).splitlines():
        if not ligne.startswith("E:"):
            continue
        cle, _, valeur = ligne[2:].partition("=")
        if cle:
            props[cle] = valeur
    return props


def _montages():
    """{(maj,min): (point de montage, options)} depuis /proc/self/mountinfo."""
    trouves = {}
    try:
        with open("/proc/self/mountinfo", "r", encoding="utf-8") as f:
            lignes = f.readlines()
    except OSError:
        return trouves
    for ligne in lignes:
        morceaux = ligne.split()
        if len(morceaux) < 5:
            continue
        try:
            maj, min_ = morceaux[2].split(":")
        except ValueError:
            continue
        point = morceaux[4].replace("\\040", " ")
        trouves[(int(maj), int(min_))] = point
    return trouves


def _echanges():
    """Les périphériques d'échange : jamais proposés au retrait."""
    trouves = set()
    try:
        with open("/proc/swaps", "r", encoding="utf-8") as f:
            for ligne in f.readlines()[1:]:
                morceaux = ligne.split()
                if morceaux and morceaux[0].startswith("/dev/"):
                    trouves.add(os.path.realpath(morceaux[0]).rsplit("/", 1)[-1])
    except OSError:
        pass
    return trouves


def _majmin(nom):
    """(maj, min) d'un /dev/<nom>, en lisant le nœud — pas de stat qui suit la dm."""
    try:
        st = os.stat("/dev/%s" % nom)
    except OSError:
        return None
    return (os.major(st.st_rdev), os.minor(st.st_rdev))


def _est_disque(nom):
    """Ce qu'on regarde : disques branchés et lecteurs optiques. Ni loop, ni dm,
    ni nvme interne (traité par le drapeau `removable`)."""
    if not (nom.startswith("sd") or nom.startswith("mmcblk") or nom.startswith("sr")):
        return False
    return os.path.isdir("/sys/block/%s" % nom)


def _enfants(nom):
    """Les partitions d'un disque : /sys/block/<nom>/<nom>N."""
    try:
        return sorted(e for e in os.listdir("/sys/block/%s" % nom) if e.startswith(nom))
    except OSError:
        return []


def _volume(nom, montages, echanges):
    majmin = _majmin(nom)
    props = _proprietes_udev("%d:%d" % majmin) if majmin else {}
    dev = "/dev/%s" % nom
    # `/sys/class/block` couvre disques **et** partitions ; `/sys/block/<nom>`
    # n'existe que pour les disques, une partition y serait muette.
    taille = _nombre("/sys/class/block/%s/size" % nom) * 512
    fs = props.get("ID_FS_TYPE") or ""
    etiquette = _decoder(props.get("ID_FS_LABEL_ENC") or props.get("ID_FS_LABEL") or "")
    return {
        "dev": dev,
        "nom": nom,
        "etiquette": etiquette,
        "fs": fs,
        "taille_o": taille,
        "montage": montages.get(majmin, "") if majmin else "",
        "chiffre": fs == "crypto_LUKS",
        "echange": nom in echanges,
    }


def _bus(props):
    bus = (props.get("ID_BUS") or "").lower()
    if bus == "usb":
        # La vitesse négociée : le meilleur signe qu'une clé est en USB 2 plutôt
        # qu'USB 3, ce qu'un utilisateur remarque avant tout le reste.
        return "usb"
    return bus or "?"


def peripheriques():
    """[{nom, modele, bus, amovible, optique, taille_o, volumes:[…]}] — les branchés.

    Le filtre est volontairement strict : taille nulle (baie vide), disque non
    amovible et non optique (le SSD interne) sont écartés. Une clé USB fat32
    vide reste visible, elle a une taille.
    """
    montages = _montages()
    echanges = _echanges()
    disques = []
    try:
        entrees = sorted(os.listdir("/sys/block"))
    except OSError:
        return disques
    for nom in entrees:
        if not _est_disque(nom):
            continue
        majmin = _majmin(nom)
        props = _proprietes_udev("%d:%d" % majmin) if majmin else {}
        optique = _lire("/sys/block/%s/device/type" % nom) == "5" or nom.startswith("sr")
        amovible = _nombre("/sys/block/%s/removable" % nom) == 1
        bus = _bus(props)
        if not (amovible or optique or bus == "usb"):
            continue
        volumes = [_volume(e, montages, echanges) for e in _enfants(nom)]
        volumes = [v for v in volumes if v["taille_o"] > 0 or v["fs"] or v["montage"]]
        taille = _nombre("/sys/block/%s/size" % nom) * 512
        if taille < TAILLE_MIN and not volumes:
            continue
        disques.append({
            "nom": nom,
            "modele": _decoder(props.get("ID_MODEL_ENC") or props.get("ID_MODEL") or nom),
            "bus": bus,
            "amovible": amovible,
            "optique": optique,
            "taille_o": taille,
            "volumes": volumes,
            "monte": any(v["montage"] for v in volumes),
            "systeme": any(v["montage"] in SYSTEME for v in volumes),
        })
    return disques


# ── état pour la barre ────────────────────────────────────────────────────────
def _vrai(valeur, defaut=True):
    """Un booléen venu du panneau peut être `true`, "true", "oui", "1"…"""
    if isinstance(valeur, bool):
        return valeur
    if valeur is None:
        return defaut
    return str(valeur).strip().lower() not in ("false", "0", "non", "")


def analyser(options=None):
    disques = peripheriques()
    options = options or {}
    # Rien de branché : la barre n'affiche rien du tout si l'option le demande
    # (un applet qui compte des périphériques n'a pas à occuper une place vide).
    masquer = _vrai(options.get("masquer_vide"), True)
    montes = [d for d in disques if d["monte"]]
    if not disques:
        return {"ok": True, "compact": compact("" if masquer else "0",
                                               "aucun périphérique"),
                "disques": [], "vide": True, "masque": masquer}
    valeur = str(len(disques))
    alerte = False
    # Un disque monté se voit : c'est ce qu'on vient de brancher et qu'on cherche
    # à ouvrir. Sans montage, l'applet reste sobre.
    libelle = "%d périphérique%s" % (len(disques), "s" if len(disques) > 1 else "")
    if montes and len(disques) == 1:
        v = montes[0]["volumes"][0] if montes[0]["volumes"] else None
        if v and v["etiquette"]:
            libelle = v["etiquette"]
    return {
        "ok": True,
        "compact": compact(valeur, libelle, alerte=alerte),
        "disques": disques,
        "vide": False,
        "masque": masquer,
        "montes": len(montes),
    }


# ── actions ───────────────────────────────────────────────────────────────────
def _udisks(*args):
    if not shutil.which("udisksctl"):
        return False, "udisksctl absent (paquet udisks2)"
    try:
        res = subprocess.run(["udisksctl"] + list(args), capture_output=True,
                             text=True, timeout=DELAI)
    except (OSError, subprocess.TimeoutExpired) as erreur:
        return False, str(erreur)
    if res.returncode != 0:
        return False, (res.stderr or res.stdout or "").strip() or "échec"
    return True, (res.stdout or "").strip()


def monter(dev):
    return _udisks("mount", "-b", dev)


def demonter(dev):
    return _udisks("unmount", "-b", dev)


def _gestionnaire():
    """Le gestionnaire de fichiers du shell, sinon un repli, sinon xdg-open.

    `xdg-open` seul ne suffit pas : sur cette machine, le type `inode/directory`
    est associé à un analyseur d'occupation disque, donc « ouvrir » une clé y
    ouvrait un camembert au lieu du contenu. Le shell a déjà son gestionnaire
    (réglages → programmes), c'est lui qui décide.
    """
    configure = ""
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "style_vars.json"), "r", encoding="utf-8") as f:
            apps = (json.load(f) or {}).get("apps") or {}
        configure = str(apps.get("Files") or "").strip()
    except (OSError, ValueError):
        configure = ""
    for candidat in (configure, "thunar", "nemo", "nautilus", "dolphin", "pcmanfm"):
        if candidat and shutil.which(candidat):
            return [candidat]
    return ["xdg-open"]


def ouvrir(chemin):
    """Ouvre un dossier monté dans le gestionnaire de fichiers."""
    if not chemin or not os.path.isdir(chemin):
        return False, "dossier introuvable"
    commande = _gestionnaire() + [chemin]
    try:
        subprocess.Popen(commande, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError as erreur:
        return False, str(erreur)
    return True, " ".join(commande)


def verrouiller(dev):
    return _udisks("lock", "-b", dev)


def deverrouiller(dev, phrase):
    """Déverrouille un volume LUKS. La phrase ne passe pas par la ligne de
    commande — elle serait visible dans `ps` — mais par un fichier de passage
    en mémoire, effacé aussitôt."""
    if not shutil.which("udisksctl"):
        return False, "udisksctl absent (paquet udisks2)"
    chemin = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
                          "quickshell-luks-%d" % os.getpid())
    try:
        with open(chemin, "w", encoding="utf-8") as f:
            f.write(phrase)
        os.chmod(chemin, 0o600)
        res = subprocess.run(["udisksctl", "unlock", "-b", dev, "--key-file", chemin],
                             capture_output=True, text=True, timeout=DELAI)
        if res.returncode != 0:
            return False, (res.stderr or "").strip() or "échec du déverrouillage"
        return True, (res.stdout or "").strip()
    except (OSError, subprocess.TimeoutExpired) as erreur:
        return False, str(erreur)
    finally:
        try:
            os.unlink(chemin)
        except OSError:
            pass


def _chemin_disque(nom_disque):
    """Le chemin d'objet D-Bus du disque, tel que udisks2 le nomme.

    On ne le reconstruit pas depuis /dev/disk/by-id : les identifiants contiennent
    des « : » et des « - », interdits dans un chemin D-Bus, et udisks2 les échappe
    à sa façon. `udisksctl info` donne la réponse exacte.
    """
    ok, sortie = _udisks("info", "-b", "/dev/%s" % nom_disque)
    if not ok:
        return ""
    for ligne in sortie.splitlines():
        ligne = ligne.strip()
        if ligne.startswith("Drive:"):
            return ligne.split(":", 1)[1].strip().strip("'")
    return ""


def retirer(nom_disque):
    """Coupe l'alimentation (clé USB) ou éjecte (carte, disque optique).

    `power-off` refuse quand un volume est monté : ce refus est rendu tel quel
    plutôt que masqué par une tentative d'éjection, qui donnait un message
    incompréhensible sur un chemin D-Bus mal reconstruit.
    """
    ok, message = _udisks("power-off", "-b", "/dev/%s" % nom_disque,
                          "--no-user-interaction")
    if ok:
        return ok, message or "retiré"
    if "mount" in message.lower() or "monté" in message.lower():
        return False, message

    # Pas d'alimentation à couper (lecteur de carte, lecteur optique) : `Eject`
    # n'a pas d'équivalent dans udisksctl, il passe par D-Bus.
    chemin = _chemin_disque(nom_disque)
    if chemin and shutil.which("gdbus"):
        try:
            res = subprocess.run(
                ["gdbus", "call", "--system",
                 "--dest", "org.freedesktop.UDisks2",
                 "--object-path", chemin,
                 "--method", "org.freedesktop.UDisks2.Drive.Eject", "{}"],
                capture_output=True, text=True, timeout=DELAI)
            if res.returncode == 0:
                return True, "éjecté"
            return False, (res.stderr or "").strip() or message
        except (OSError, subprocess.TimeoutExpired) as erreur:
            return False, str(erreur)
    return False, message


def _options_cli(argv):
    options = {}
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                options = json.loads(arg.split("=", 1)[1])
            except ValueError:
                options = {}
    return options


def main(argv):
    action = argv[1] if len(argv) > 1 else ""
    if action == "ouvrir" and len(argv) > 2:
        ok, message = ouvrir(argv[2])
        print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
        return 0 if ok else 1

    if action in ("monter", "demonter", "verrouiller", "deverrouiller", "retirer") and len(argv) > 2:
        cible = argv[2]
        if action == "monter":
            ok, message = monter(cible)
        elif action == "demonter":
            ok, message = demonter(cible)
        elif action == "verrouiller":
            ok, message = verrouiller(cible)
        elif action == "deverrouiller":
            phrase = ""
            if "--phrase" in argv and argv.index("--phrase") + 1 < len(argv):
                phrase = argv[argv.index("--phrase") + 1]
            if not phrase:
                print(json.dumps({"ok": False, "erreur": "phrase absente"}))
                return 2
            ok, message = deverrouiller(cible, phrase)
        else:
            ok, message = retirer(cible)
        print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
        return 0 if ok else 1

    donnees = analyser(_options_cli(argv))
    presenter(donnees, "usb", "usb", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
