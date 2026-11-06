#!/usr/bin/env python3
"""Applet « Disques » : une barre, l'espace occupé hors racine.

Dans la barre, une seule jauge : la part occupée sur l'ensemble des systèmes de
fichiers montés **hors `/`** (la racine a déjà son propre suivi, elle noierait la
mesure). Le popup et le widget reprennent le détail : chaque montage, puis chaque
disque physique avec son modèle, son type et sa température quand un capteur
existe.

SMART est lu quand `smartctl` y arrive sans privilège ; sinon la ligne est omise
plutôt que d'afficher un état inventé. Les températures viennent de hwmon, qui ne
demande rien (module `drivetemp` ou capteur NVMe).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import compact, presenter, sortir  # noqa: E402

PSEUDO = ("tmpfs", "devtmpfs", "efivarfs", "squashfs", "overlay", "proc", "sysfs",
          "cgroup", "cgroup2", "ramfs", "autofs", "fuse.portal", "devpts",
          "binfmt_misc", "securityfs", "pstore", "debugfs", "tracefs",
          "configfs", "fusectl", "hugetlbfs", "mqueue", "nsfs", "bpf")
SEUIL_ATTENTION = 80
SEUIL_CRITIQUE = 92


def _run(cmd, timeout=6):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def _niveau(pct):
    if pct >= SEUIL_CRITIQUE:
        return "critique"
    if pct >= SEUIL_ATTENTION:
        return "attention"
    return "ok"


def montages():
    """Les systèmes de fichiers montés, hors racine et hors pseudo-systèmes."""
    sortie = _run(["df", "-B1", "--output=source,target,fstype,size,used,avail"])
    lignes = sortie.splitlines()[1:]
    out = []
    for ligne in lignes:
        morceaux = ligne.split()
        if len(morceaux) < 5:
            continue
        source, cible, fstype = morceaux[0], morceaux[1], morceaux[2]
        try:
            taille, utilise, dispo = int(morceaux[3]), int(morceaux[4]), int(morceaux[5])
        except (IndexError, ValueError):
            continue
        # La racine est un montage comme un autre : elle est exclue par défaut
        # dans la sélection, mais reste cochable dans le panneau.
        if fstype in PSEUDO or fstype.startswith("fuse."):
            continue
        # Les instantanés btrfs et les doublons de même périphérique n'apportent
        # rien : on garde le premier point de montage par source.
        if any(m["source"] == source for m in out):
            continue
        if taille <= 0:
            continue
        pct = round(100 * utilise / taille)
        out.append({
            "source": source,
            "montage": cible,
            "fstype": fstype,
            "taille_go": round(taille / 1e9, 1),
            "utilise_go": round(utilise / 1e9, 1),
            "libre_go": round(dispo / 1e9, 1),
            "pourcent": pct,
            "niveau": _niveau(pct),
        })
    out.sort(key=lambda m: m["montage"])
    return out


def _temperature_nvme():
    """Capteur NVMe de hwmon (aucun privilège requis)."""
    try:
        for h in os.listdir("/sys/class/hwmon"):
            base = os.path.join("/sys/class/hwmon", h)
            try:
                with open(os.path.join(base, "name")) as f:
                    nom = f.read().strip()
            except OSError:
                continue
            if nom in ("nvme", "drivetemp"):
                try:
                    with open(os.path.join(base, "temp1_input")) as f:
                        return round(int(f.read().strip()) / 1000)
                except (OSError, ValueError):
                    continue
    except OSError:
        pass
    return None


def _smart(device):
    """(santé, heures, usure) si smartctl y arrive sans privilège, sinon rien."""
    brut = _run(["smartctl", "-a", "--json", device])
    if not brut.strip():
        return {}
    try:
        d = json.loads(brut)
    except ValueError:
        return {}
    if (d.get("smartctl") or {}).get("exit_status") in (1, 2, 3):
        # 2 = périphérique non ouvert (droits) : on ne prétend rien savoir.
        return {}
    infos = {}
    etat = (d.get("smart_status") or {}).get("passed")
    if etat is not None:
        infos["sante"] = bool(etat)
    heures = (d.get("power_on_time") or {}).get("hours")
    if heures is not None:
        infos["heures"] = int(heures)
    usure = (d.get("nvme_smart_health_information_log") or {}).get("percentage_used")
    if usure is not None:
        infos["usure"] = int(usure)
    temp = (d.get("temperature") or {}).get("current")
    if temp is not None:
        infos["temperature"] = int(temp)
    return infos


def disques():
    """Les disques physiques : modèle, type, capacité, température, SMART."""
    sortie = _run(["lsblk", "-J", "-b", "-d", "-o", "NAME,MODEL,SIZE,TYPE,ROTA,TRAN"])
    try:
        arbre = json.loads(sortie).get("blockdevices", [])
    except ValueError:
        return []

    temp_nvme = _temperature_nvme()
    out = []
    for dev in arbre:
        nom = str(dev.get("name") or "")
        taille = int(dev.get("size") or 0)
        if not nom or taille <= 0:
            continue
        transport = str(dev.get("tran") or "")
        rotatif = bool(dev.get("rota"))
        nature = ("nvme" if transport == "nvme"
                  else ("disque" if rotatif else "ssd"))
        infos = {
            "nom": nom,
            "modele": str(dev.get("model") or "").strip(),
            "taille_go": round(taille / 1e9, 1),
            "type": nature,
        }
        if nature == "nvme" and temp_nvme is not None:
            infos["temperature"] = temp_nvme
        infos.update(_smart("/dev/" + nom))
        out.append(infos)
    out.sort(key=lambda d: d["nom"])
    return out


def _options_cli(argv, options=None):
    """Options de l'applet : celles passées par la barre, sinon celles du registre.

    Le widget de bureau n'a pas d'options propres : il appelle ce service sans
    argument et doit voir la même sélection que l'applet. Lire le registre évite
    deux listes à tenir."""
    if options:
        return options
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                return json.loads(arg.split("=", 1)[1])
            except ValueError:
                return {}
    try:
        chemin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bar_applets.json")
        with open(chemin, "r", encoding="utf-8") as f:
            etat = json.load(f)
        entree = (etat.get("actifs") or {}).get("disques") or {}
        return entree.get("options") or {}
    except (OSError, ValueError):
        return {}


def _selection(options):
    """Les montages à afficher.

    Sans choix enregistré : tout **sauf la racine** — elle a ses propres jauges
    ailleurs et noierait la mesure. Un choix explicite est respecté tel quel, `/`
    compris.
    """
    choisis = (options or {}).get("montages")
    if isinstance(choisis, list):
        return set(str(c) for c in choisis)
    return None


def analyser(options=None):
    sel = _selection(options)
    m = montages()
    if sel is None:
        m = [x for x in m if x["montage"] != "/"]
    else:
        m = [x for x in m if x["montage"] in sel]
    d = disques()

    if m:
        total = sum(x["taille_go"] for x in m)
        utilise = sum(x["utilise_go"] for x in m)
        pct = round(100 * utilise / total) if total > 0 else 0
        niveau = _niveau(pct)
    else:
        pct, niveau = 0, "ok"

    barres = [{
        "cle": "disques",
        "nom": "Disques",
        "icone": "disque",
        "valeur": pct,
        "remplissage": pct,
        "texte": str(pct) + " %",
        "niveau": niveau,
        "alerte": niveau != "ok",
    }]

    return {
        "ok": True,
        "compact": compact(str(pct) + " %", "disques", niveau != "ok", barres=barres),
        "detail": {"montages": m, "disques": d},
        "mesures": ["disques"],
        "applet": "disques",
        "icone": "disque",
        "alerte": niveau != "ok",
    }


def main(argv):
    if "liste" in argv[1:]:
        # Inventaire pour les cases à cocher du panneau : tout ce qui est monté,
        # avec la taille, pour que le choix se fasse sur des chiffres.
        print(json.dumps({"ok": True, "montages": montages()}, ensure_ascii=False))
        return 0
    donnees = analyser(_options_cli(argv))
    presenter(donnees, "disques", "disque", donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
