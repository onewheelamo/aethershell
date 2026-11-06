#!/usr/bin/env python3
"""Applet « Système » : quatre mesures, chacune sa mini-barre horizontale.

La barre ne montre pas un chiffre unique mais N barres : CPU, RAM, GPU et
température, chacune activable indépendamment (`options.mesures`). Un applet qui
n'affiche qu'une valeur ne pouvait pas raconter une machine ; une jauge par
mesure, si.

Sources, toutes locales (aucun réseau, aucun process par mesure) :

  - CPU : `/proc/stat`, échantillonné sur 200 ms pour que la valeur soit
    immédiate — un cache de l'échantillon précédent donnerait un chiffre vieux
    d'une minute à la première ouverture ;
  - RAM : `/proc/meminfo` (utilisé = Total − Available, la seule définition qui
    compte ce qui peut encore être alloué) ;
  - GPU : `nvidia-smi` en une requête (utilisation, température, VRAM) ;
  - Température : sonde « Package id 0 » de `coretemp`, à défaut la plus chaude.

Une sonde absente ne casse pas l'applet : la mesure disparaît de la liste, les
autres continuent. Mieux vaut trois barres qu'une croix rouge.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

from applet_contrat import compact, presenter, sortir

ICI = Path(__file__).resolve().parent
CACHE = ICI / "systeme_applet_cache.json"
ETAT_CPU = ICI / "systeme_applet_cpu.json"
CACHE_TTL = 3          # s : quatre appels rapprochés ne doivent pas refaire nvidia-smi
ECHANTILLON = 0.2      # s

MESURES = ("cpu", "ram", "gpu", "temp")
NOMS = {"cpu": "CPU", "ram": "RAM", "gpu": "GPU", "temp": "Temp"}
# Noms de tracés d'IconSvg.qml, pas de glyphes Nerd (absents de la fonte).
ICONES = {"cpu": "cpu", "ram": "ram", "gpu": "gpu", "temp": "temp"}
SEUIL_ATTENTION = 60
SEUIL_CRITIQUE = 85
TEMP_ATTENTION = 70
TEMP_CRITIQUE = 85


# ── CPU ───────────────────────────────────────────────────────────────────────
def _lire_stat():
    with open("/proc/stat", encoding="utf-8") as f:
        champs = f.readline().split()[1:]
    valeurs = [int(v) for v in champs]
    # idle + iowait : ce qui n'est pas du travail utile.
    return sum(valeurs), valeurs[3] + (valeurs[4] if len(valeurs) > 4 else 0)


def cpu_pourcent():
    try:
        total1, idle1 = _lire_stat()
        time.sleep(ECHANTILLON)
        total2, idle2 = _lire_stat()
        dt, di = total2 - total1, idle2 - idle1
        if dt <= 0:
            return None
        return max(0.0, min(100.0, 100.0 * (dt - di) / dt))
    except (OSError, ValueError):
        return None


# ── RAM ───────────────────────────────────────────────────────────────────────
def ram_pourcent():
    try:
        with open("/proc/meminfo", encoding="utf-8") as f:
            infos = {}
            for ligne in f:
                morceaux = ligne.split(":")
                if len(morceaux) == 2:
                    infos[morceaux[0].strip()] = int(morceaux[1].split()[0])
        total = infos.get("MemTotal", 0)
        dispo = infos.get("MemAvailable", 0)
        if total <= 0:
            return None, None, None
        utilises = total - dispo
        return 100.0 * utilises / total, utilises / 1024 / 1024, total / 1024 / 1024
    except (OSError, ValueError):
        return None, None, None


# ── GPU ───────────────────────────────────────────────────────────────────────
def gpu_mesures():
    try:
        res = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        if res.returncode != 0:
            return None
        ligne = res.stdout.strip().splitlines()[0]
        util, temp, vram, vram_tot = [float(x) for x in ligne.split(",")]
        return {"utilisation": util, "temperature": temp, "vram": vram, "vram_total": vram_tot}
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return None


# ── Température ───────────────────────────────────────────────────────────────
def temp_cpu():
    candidats = []
    try:
        for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
            try:
                nom = (hwmon / "name").read_text(encoding="utf-8").strip()
            except OSError:
                continue
            for entree in hwmon.glob("temp*_input"):
                try:
                    valeur = int(entree.read_text(encoding="utf-8").strip()) / 1000.0
                except (OSError, ValueError):
                    continue
                label = ""
                etiquette = entree.with_name(entree.name.replace("_input", "_label"))
                try:
                    label = etiquette.read_text(encoding="utf-8").strip()
                except OSError:
                    pass
                if nom == "coretemp" and label.startswith("Package"):
                    return valeur
                candidats.append(valeur)
    except OSError:
        return None
    return max(candidats) if candidats else None


# ── assemblage ────────────────────────────────────────────────────────────────
def _niveau(valeur, attention, critique):
    if valeur >= critique:
        return "critique"
    if valeur >= attention:
        return "attention"
    return "ok"


def _barre(cle, valeur, texte):
    if cle == "temp":
        niveau = _niveau(valeur, TEMP_ATTENTION, TEMP_CRITIQUE)
        # Une température ne se remplit pas : la jauge va de 30 à 100 °C, pour
        # qu'une machine à 40 °C ne paraisse pas « à moitié chaude ».
        remplissage = max(0.0, min(100.0, (valeur - 30.0) / 70.0 * 100.0))
    else:
        niveau = _niveau(valeur, SEUIL_ATTENTION, SEUIL_CRITIQUE)
        remplissage = max(0.0, min(100.0, valeur))
    return {
        "cle": cle,
        "nom": NOMS[cle],
        "icone": ICONES[cle],
        "valeur": round(float(valeur), 1),
        "remplissage": round(remplissage, 1),
        "texte": texte,
        "niveau": niveau,
        "alerte": niveau != "ok",
    }


def analyser(options=None, force=False):
    if not force:
        try:
            lu = json.loads(CACHE.read_text(encoding="utf-8"))
            if 0 <= time.time() - float(lu.get("ts", 0)) < CACHE_TTL:
                return _filtrer(lu, options)
        except (OSError, ValueError):
            pass

    voulues = _choisies(options)
    barres = []
    detail = {}

    for cle in voulues:
        if cle == "cpu":
            v = cpu_pourcent()
            if v is not None:
                barres.append(_barre(cle, v, f"{v:.0f}%"))
        elif cle == "ram":
            v, utilises, total = ram_pourcent()
            if v is not None and utilises is not None and total is not None:
                barres.append(_barre(cle, v, f"{v:.0f}%"))
                detail["ram"] = {"utilisee_go": round(float(utilises), 1),
                                 "totale_go": round(float(total), 1)}
        elif cle == "gpu":
            g = gpu_mesures()
            if g:
                barres.append(_barre(cle, g["utilisation"], f"{g['utilisation']:.0f}%"))
                detail["gpu"] = {"temperature": g["temperature"],
                                 "vram_go": round(g["vram"] / 1024, 1),
                                 "vram_totale_go": round(g["vram_total"] / 1024, 1)}
        elif cle == "temp":
            t = temp_cpu()
            if t is not None:
                barres.append(_barre(cle, t, f"{t:.0f}°"))
                detail["temp"] = {"cpu": round(t, 1)}

    donnees = {
        "ok": True,
        "ts": time.time(),
        "compact": compact(barres[0]["texte"] if barres else "", "système",
                           alerte=any(b["alerte"] for b in barres), barres=barres),
        "detail": detail,
        "mesures": [b["cle"] for b in barres],
    }
    try:
        CACHE.write_text(json.dumps(donnees, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass
    return donnees


def _choisies(options):
    """Les mesures demandées, **rangées dans l'ordre canonique**.

    L'utilisateur choisit un ensemble, pas une disposition : sans ce tri, une
    liste enregistrée dans un autre ordre donnait des jauges mélangées (RAM,
    Temp, CPU…) selon l'historique des clics.
    """
    # Liste absente = toutes ; liste **vide** = aucune. Confondre les deux
    # empêchait de tout filtrer, et donc de vérifier qu'on peut revenir en arrière.
    brut = (options or {}).get("mesures")
    if brut is None:
        return list(MESURES)
    return [m for m in MESURES if m in brut]


def _filtrer(donnees, options):
    """Le cache porte toutes les mesures ; le choix de l'utilisateur filtre."""
    voulues = _choisies(options)
    barres = [b for b in donnees.get("compact", {}).get("barres", []) if b["cle"] in voulues]
    copie = dict(donnees)
    compacte = dict(donnees.get("compact", {}))
    compacte["barres"] = barres
    compacte["valeur"] = barres[0]["texte"] if barres else ""
    compacte["alerte"] = any(b["alerte"] for b in barres)
    copie["compact"] = compacte
    copie["mesures"] = [b["cle"] for b in barres]
    return copie


def main(argv):
    force = "--force" in argv
    options = {}
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                options = json.loads(arg.split("=", 1)[1])
            except ValueError:
                options = {}
    donnees = analyser(options, force=force)
    presenter(donnees, "systeme", "cpu", donnees["compact"],
              alerte=donnees["compact"]["alerte"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
