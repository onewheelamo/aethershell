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
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from applet_contrat import compact, presenter, sortir

ICI = Path(__file__).resolve().parent
CACHE = ICI / "systeme_applet_cache.json"
ETAT_CPU = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "quickshell" / "systeme_cpu_cache.json"
_MEM_ETAT_CPU = None
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


def _sauver_etat_cpu(total, idle, maintenant):
    tmp = f"{ETAT_CPU}.tmp.{os.getpid()}"
    try:
        ETAT_CPU.parent.mkdir(parents=True, exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"total": total, "idle": idle, "ts": maintenant}, f)
        os.replace(tmp, ETAT_CPU)
    except OSError:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def cpu_pourcent(persister=True):
    global _MEM_ETAT_CPU
    try:
        maintenant = time.monotonic()
        total2, idle2 = _lire_stat()
        total1 = idle1 = None
        if not persister:
            prev = _MEM_ETAT_CPU
        else:
            prev = None
            try:
                with open(ETAT_CPU, "r", encoding="utf-8") as f:
                    prev = json.load(f)
            except (OSError, ValueError):
                prev = None
        if isinstance(prev, dict):
            try:
                ts_prev = float(prev.get("ts", 0))
                if 0 < (maintenant - ts_prev) <= 30.0:
                    total1 = int(prev["total"])
                    idle1 = int(prev["idle"])
            except (ValueError, KeyError, TypeError):
                pass

        if total1 is None or (total2 - total1) <= 0:
            total1, idle1 = total2, idle2
            time.sleep(ECHANTILLON)
            total2, idle2 = _lire_stat()
            maintenant = time.monotonic()

        if persister:
            _sauver_etat_cpu(total2, idle2, maintenant)
        else:
            _MEM_ETAT_CPU = {"total": total2, "idle": idle2, "ts": maintenant}
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


def analyser(options=None, force=False, persister=True):
    if not force and persister:
        try:
            lu = json.loads(CACHE.read_text(encoding="utf-8"))
            if 0 <= time.time() - float(lu.get("ts", 0)) < CACHE_TTL:
                return _filtrer(lu, options)
        except (OSError, ValueError):
            pass

    barres = []
    detail = {}

    for cle in MESURES:
        if cle == "cpu":
            v = cpu_pourcent(persister=persister)
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
    if persister:
        try:
            CACHE.write_text(json.dumps(donnees, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass
    return _filtrer(donnees, options)


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




# ── processus (inspiration nvtop, sans nvtop) ────────────────────────────────
#
# nvtop est un programme interactif en ncurses : le lire demande de le lancer
# dans un pseudo-terminal et d'en découper l'écran. /proc donne les mêmes
# chiffres, et nvidia-smi la part GPU — deux sources déjà utilisées ici. Le
# compromis est assumé : pas de courbes dessinées (Pillow chez eux), mais une
# liste triable et des gestes.

TICKS = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100
# Sous ce seuil, un processus n'a rien fait : la liste resterait bruyante.
CPU_MIN = 0.5


def _jiffies():
    """{pid: (utime+stime, nom, rss_page)} depuis /proc."""
    etats = {}
    for entree in os.listdir("/proc"):
        if not entree.isdigit():
            continue
        pid = int(entree)
        try:
            with open("/proc/%d/stat" % pid, "r", encoding="utf-8") as f:
                champs = f.read().rsplit(")", 1)
            if len(champs) != 2:
                continue
            nom = champs[0].split("(", 1)[-1]
            reste = champs[1].split()
            # Aprés le « ) » : état (0), ... utime (11), stime (12), rss (21)
            cpu = int(reste[11]) + int(reste[12])
            etats[pid] = (cpu, nom.strip()[:24], int(reste[21]))
        except (OSError, IndexError, ValueError):
            continue
    return etats


def _commandes(pids):
    """La ligne de commande, bornée : c'est ce qu'on lit pour reconnaître un processus."""
    sortie = {}
    for pid in pids:
        try:
            with open("/proc/%d/cmdline" % pid, "rb") as f:
                brut = f.read().replace(b"\0", b" ").decode("utf-8", "ignore").strip()
        except OSError:
            brut = ""
        sortie[pid] = brut[:160]
    return sortie


def _gpu_par_processus():
    """{pid: mémoire GPU en Mio} si nvidia-smi répond, sinon {}."""
    try:
        res = subprocess.run(
            ["nvidia-smi", "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return {}
    sortie = {}
    for ligne in res.stdout.splitlines():
        morceaux = [m.strip() for m in ligne.split(",")]
        if len(morceaux) >= 2 and morceaux[0].isdigit():
            try:
                sortie[int(morceaux[0])] = int(morceaux[1])
            except ValueError:
                continue
    return sortie


def processus(limite=14):
    """Les processus qui consomment, mesurés sur deux relevés rapprochés.

    Un seul relevé ne donne pas de pourcentage : on échantillonne à 250 ms
    d'intervalle, ce qui coûte un quart de seconde **au moment où le panneau
    s'ouvre** — et rien le reste du temps, puisque rien ne tourne en fond.
    """
    premier = _jiffies()
    debut = time.monotonic()
    time.sleep(0.25)
    second = _jiffies()
    ecoule = max(0.05, time.monotonic() - debut)
    if not premier or not second:
        return []
    gpu = _gpu_par_processus()
    lignes = []
    for pid, (cpu, nom, rss) in second.items():
        avant = premier.get(pid)
        if not avant:
            continue
        # Pourcentage « à la top » : jiffies consommées rapportées au temps
        # écoulé. Un processus qui sature deux cœurs affiche 200 %.
        part = max(0.0, (cpu - avant[0]) / (ecoule * TICKS) * 100.0)
        lignes.append({
            "pid": pid,
            "nom": nom,
            "cpu": round(part, 1),
            "ram_mo": round(rss * (os.sysconf("SC_PAGE_SIZE") if hasattr(os, "sysconf") else 4096) / 1048576, 1),
            "gpu_mo": gpu.get(pid, 0),
        })
    # Le popup trie en mémoire par CPU, RAM ou GPU : on garde la tête de chaque
    # axe pour qu'un gros consommateur de RAM au repos CPU reste visible.
    par_cpu = sorted([l for l in lignes if l["cpu"] >= CPU_MIN],
                     key=lambda l: (l["cpu"], l["ram_mo"]), reverse=True)[:limite]
    par_ram = sorted([l for l in lignes if l["ram_mo"] > 0],
                     key=lambda l: (l["ram_mo"], l["cpu"]), reverse=True)[:limite]
    par_gpu = sorted([l for l in lignes if l["gpu_mo"] > 0],
                     key=lambda l: (l["gpu_mo"], l["cpu"]), reverse=True)[:limite]
    vus = {}
    for l in par_cpu + par_ram + par_gpu:
        vus[l["pid"]] = l
    retenues = sorted(vus.values(), key=lambda l: (l["cpu"], l["ram_mo"]), reverse=True)
    commandes = _commandes([l["pid"] for l in retenues])
    for ligne in retenues:
        ligne["commande"] = commandes.get(ligne["pid"], "")
    return retenues


def tuer(pid, force=False):
    """Tue un processus, avec les garde-fous qui évitent les dégâts.

    Refusé : pid <= 1, son propre pid, son parent (le shell qui a lancé la
    commande), et tout processus dont l'utilisateur n'est pas le propriétaire.
    """
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return False, "pid invalide"
    if pid <= 1:
        return False, "refusé : pid système"
    if pid in (os.getpid(), os.getppid()):
        return False, "refusé : c'est le shell qui exécute la commande"
    try:
        if os.stat("/proc/%d" % pid).st_uid != os.getuid():
            return False, "refusé : processus d'un autre utilisateur"
    except OSError:
        return False, "processus disparu"
    try:
        os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
    except OSError as erreur:
        return False, str(erreur)
    return True, ("tué (SIGKILL)" if force else "arrêt demandé (SIGTERM)")


def main(argv):
    action = argv[1] if len(argv) > 1 else ""
    if action == "processus":
        print(json.dumps({"processus": processus(),
                          "gpu": bool(_gpu_par_processus())}, ensure_ascii=False))
        return 0
    if action == "tuer" and len(argv) > 2:
        ok, message = tuer(argv[2], force="--force" in argv)
        print(json.dumps({"ok": ok, "message": message}, ensure_ascii=False))
        return 0 if ok else 1
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
