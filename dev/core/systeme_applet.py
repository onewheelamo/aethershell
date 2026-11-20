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
import pwd
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

from applet_contrat import compact, presenter, sortir

ICI = Path(__file__).resolve().parent
CACHE = ICI / "systeme_applet_cache.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))) / "quickshell"
ETAT_CPU = CACHE_DIR / "systeme_cpu_cache.json"
ETAT_NET = CACHE_DIR / "systeme_net_cache.json"
_MEM_ETAT_CPU = None
_MEM_ETAT_NET = None
CACHE_TTL = 3          # s : quatre appels rapprochés ne doivent pas refaire nvidia-smi
ECHANTILLON = 0.2      # s

MESURES_DEFAUT = ("cpu", "ram", "gpu", "temp")
MESURES = ("cpu", "ram", "gpu", "temp", "load", "swap", "disk", "net")
NOMS = {
    "cpu": "CPU",
    "ram": "RAM",
    "gpu": "GPU",
    "temp": "Temp",
    "load": "Load",
    "swap": "Swap",
    "disk": "Disque",
    "net": "Réseau",
}
# Noms de tracés d'IconSvg.qml, pas de glyphes Nerd (absents de la fonte).
ICONES = {
    "cpu": "cpu",
    "ram": "ram",
    "gpu": "gpu",
    "temp": "temp",
    "load": "load",
    "swap": "swap",
    "disk": "disque",
    "net": "reseau",
}
SEUIL_ATTENTION = 60
SEUIL_CRITIQUE = 85
TEMP_ATTENTION = 70
TEMP_CRITIQUE = 85


# ── CPU ───────────────────────────────────────────────────────────────────────
def _lire_stat():
    total = idle = 0
    coeurs = {}
    with open("/proc/stat", encoding="utf-8") as f:
        for ligne in f:
            morceaux = ligne.split()
            if not morceaux:
                continue
            nom = morceaux[0]
            if nom == "cpu":
                valeurs = [int(v) for v in morceaux[1:]]
                # idle + iowait : ce qui n'est pas du travail utile.
                total = sum(valeurs)
                idle = valeurs[3] + (valeurs[4] if len(valeurs) > 4 else 0)
            elif nom.startswith("cpu") and nom[3:].isdigit():
                valeurs = [int(v) for v in morceaux[1:]]
                coeurs[nom] = [sum(valeurs), valeurs[3] + (valeurs[4] if len(valeurs) > 4 else 0)]
            elif not nom.startswith("cpu"):
                break
    return total, idle, coeurs


def _sauver_etat_cpu(total, idle, coeurs, maintenant):
    tmp = f"{ETAT_CPU}.tmp.{os.getpid()}"
    try:
        ETAT_CPU.parent.mkdir(parents=True, exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"total": total, "idle": idle, "coeurs": coeurs, "ts": maintenant}, f)
        os.replace(tmp, ETAT_CPU)
    except OSError:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def _cpu_freq_ghz():
    freqs = []
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as f:
            for ligne in f:
                if ligne.startswith("cpu MHz"):
                    _, val = ligne.split(":", 1)
                    freqs.append(float(val.strip()))
    except (OSError, ValueError):
        return None
    if not freqs:
        return None
    return round(sum(freqs) / len(freqs) / 1000.0, 2)


def cpu_mesures(persister=True):
    global _MEM_ETAT_CPU
    try:
        maintenant = time.monotonic()
        total2, idle2, coeurs2 = _lire_stat()
        total1 = idle1 = None
        coeurs1 = {}
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
                    if isinstance(prev.get("coeurs"), dict):
                        coeurs1 = prev["coeurs"]
            except (ValueError, KeyError, TypeError):
                pass

        if total1 is None or (total2 - total1) <= 0:
            total1, idle1, coeurs1 = total2, idle2, coeurs2
            time.sleep(ECHANTILLON)
            total2, idle2, coeurs2 = _lire_stat()
            maintenant = time.monotonic()

        if persister:
            _sauver_etat_cpu(total2, idle2, coeurs2, maintenant)
        else:
            _MEM_ETAT_CPU = {"total": total2, "idle": idle2, "coeurs": coeurs2, "ts": maintenant}
        dt, di = total2 - total1, idle2 - idle1
        if dt <= 0:
            return None, [], None
        pct = max(0.0, min(100.0, 100.0 * (dt - di) / dt))
        coeurs_pct = []
        for nom in sorted(coeurs2, key=lambda k: int(k[3:])):
            t2, i2 = coeurs2[nom]
            c1 = coeurs1.get(nom)
            if c1 and len(c1) == 2 and (t2 - c1[0]) > 0:
                cdt, cdi = t2 - c1[0], i2 - c1[1]
                coeurs_pct.append(round(max(0.0, min(100.0, 100.0 * (cdt - cdi) / cdt)), 1))
            else:
                coeurs_pct.append(round(pct, 1))
        return pct, coeurs_pct, _cpu_freq_ghz()
    except (OSError, ValueError):
        return None, [], None


def cpu_pourcent(persister=True):
    pct, _, _ = cpu_mesures(persister=persister)
    return pct


# ── RAM & Swap ────────────────────────────────────────────────────────────────
_CPU_NOM_CACHE = None


def _cpu_nom():
    global _CPU_NOM_CACHE
    if _CPU_NOM_CACHE is not None:
        return _CPU_NOM_CACHE
    nom = ""
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.lower().startswith("model name") and ":" in line:
                nom = line.split(":", 1)[1].strip()
                break
    except OSError:
        nom = ""
    if nom:
        nom = re.sub(r"\((?:R|TM|tm|r)\)", "", nom)
        nom = re.sub(r"\s*@\s*[\d.]+\s*GHz", "", nom, flags=re.IGNORECASE)
        nom = re.sub(r"\b\d+-Core Processor\b", "", nom, flags=re.IGNORECASE)
        nom = re.sub(r"\bCPU\b", "", nom)
        nom = re.sub(r"\s+", " ", nom).strip()
    _CPU_NOM_CACHE = nom or "CPU"
    return _CPU_NOM_CACHE


def memoire_mesures():
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
            return None
        utilises = total - dispo
        buffers_kio = infos.get("Buffers", 0)
        cached_kio = infos.get("Cached", 0) + infos.get("SReclaimable", 0)
        cache_kio = buffers_kio + cached_kio
        htop_kio = max(0, total - infos.get("MemFree", 0) - cache_kio + infos.get("Shmem", 0))
        swap_total = infos.get("SwapTotal", 0)
        swap_free = infos.get("SwapFree", 0)
        swap_util = max(0, swap_total - swap_free)
        return {
            "ram_pct": 100.0 * utilises / total,
            "utilisee_go": round(utilises / 1048576.0, 1),
            "dispo_go": round(dispo / 1048576.0, 1),
            "totale_go": round(total / 1048576.0, 1),
            "buffers_go": round(buffers_kio / 1048576.0, 1),
            "cache_go": round(cache_kio / 1048576.0, 1),
            "htop_go": round(htop_kio / 1048576.0, 1),
            "swap_pct": (100.0 * swap_util / swap_total) if swap_total > 0 else 0.0,
            "swap_utilisee_go": round(swap_util / 1048576.0, 1),
            "swap_totale_go": round(swap_total / 1048576.0, 1),
        }
    except (OSError, ValueError):
        return None


def ram_pourcent():
    m = memoire_mesures()
    if not m:
        return None, None, None
    return m["ram_pct"], m["utilisee_go"], m["totale_go"]


# ── GPU ───────────────────────────────────────────────────────────────────────
def _parse_float(val):
    try:
        return float(val.strip())
    except (ValueError, AttributeError):
        return None


def _lire_int(chemin):
    try:
        return int(Path(chemin).read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


def _gpu_nvidia():
    try:
        res = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=5,
        )
        if res.returncode != 0:
            return None
        ligne = res.stdout.strip().splitlines()[0]
        champs = ligne.split(",")
        util = _parse_float(champs[0])
        temp = _parse_float(champs[1])
        vram = _parse_float(champs[2])
        vram_tot = _parse_float(champs[3])
        power = _parse_float(champs[4]) if len(champs) > 4 else None
        if util is None or temp is None or vram is None or vram_tot is None:
            return None
        return {
            "utilisation": util,
            "temperature": temp,
            "vram": vram,
            "vram_total": vram_tot,
            "power_w": round(power, 1) if power is not None else None,
        }
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        return None


def _gpu_amd():
    try:
        cards = sorted(
            p for p in Path("/sys/class/drm").glob("card*")
            if re.fullmatch(r"card\d+", p.name)
        )
    except OSError:
        return None

    for card in cards:
        dev = card / "device"
        if not dev.is_dir():
            continue
        try:
            vendor = (dev / "vendor").read_text(encoding="utf-8").strip().lower()
        except OSError:
            vendor = ""
        busy_path = dev / "gpu_busy_percent"
        if vendor != "0x1002" and not busy_path.is_file():
            continue

        util = _lire_int(busy_path)
        if util is None:
            continue

        vram_used_b = _lire_int(dev / "mem_info_vram_used")
        vram_tot_b = _lire_int(dev / "mem_info_vram_total")
        if vram_tot_b is None or vram_tot_b <= 0:
            vram_used_b = _lire_int(dev / "mem_info_gtt_used")
            vram_tot_b = _lire_int(dev / "mem_info_gtt_total")

        temp = None
        power_w = None
        hwmon_root = dev / "hwmon"
        if hwmon_root.is_dir():
            for hw in sorted(hwmon_root.glob("hwmon*")):
                # Température : privilégier edge / junction, sinon premier temp*_input
                temp_vals = []
                for tf in sorted(hw.glob("temp*_input")):
                    mc = _lire_int(tf)
                    if mc is None:
                        continue
                    c = mc / 1000.0
                    lbl_path = tf.with_name(tf.name.replace("_input", "_label"))
                    lbl = ""
                    try:
                        lbl = lbl_path.read_text(encoding="utf-8").strip().lower()
                    except OSError:
                        pass
                    if lbl == "edge":
                        temp = c
                        break
                    temp_vals.append(c)
                if temp is None and temp_vals:
                    temp = temp_vals[0]

                # Puissance GPU (microwatts -> watts)
                for pf in ("power1_average", "power1_input"):
                    uw = _lire_int(hw / pf)
                    if uw is not None:
                        power_w = round(uw / 1_000_000.0, 1)
                        break
                if temp is not None or power_w is not None:
                    break

        return {
            "utilisation": float(util),
            "temperature": round(temp, 1) if temp is not None else 0.0,
            "vram": round((vram_used_b or 0) / (1024 * 1024), 1),
            "vram_total": round((vram_tot_b or 0) / (1024 * 1024), 1),
            "power_w": power_w,
        }
    return None


def gpu_mesures():
    return _gpu_nvidia() or _gpu_amd()


# ── Température ───────────────────────────────────────────────────────────────
def temp_cpu():
    candidats = []
    try:
        for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
            try:
                nom = (hwmon / "name").read_text(encoding="utf-8").strip()
            except OSError:
                continue
            if nom == "amdgpu":
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
                if nom in ("k10temp", "zenpower") and label in ("Tdie", "Tctl"):
                    return valeur
                candidats.append(valeur)
    except OSError:
        return None
    return max(candidats) if candidats else None


def _psi(kind):
    try:
        with open(f"/proc/pressure/{kind}", encoding="utf-8") as f:
            vals = {}
            for ligne in f:
                cle = ligne.split(None, 1)[0]
                for champ in ligne.split()[1:]:
                    if champ.startswith("avg10="):
                        vals[cle] = float(champ.split("=", 1)[1])
                        break
        if "some" in vals and "full" in vals:
            return f"some {vals['some']:.1f}% · full {vals['full']:.1f}%"
        if "some" in vals:
            return f"some {vals['some']:.1f}%"
    except (OSError, ValueError):
        pass
    return ""


def _top_proc_rapide():
    try:
        moi = pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        moi = ""
    lignes = []
    try:
        res = subprocess.run(
            ["ps", "-eo", "user:16,pcpu,rss,comm", "--sort=-pcpu", "--no-headers"],
            capture_output=True, text=True, timeout=1.5,
        )
        if res.returncode == 0:
            for l in res.stdout.splitlines():
                cols = l.split(None, 3)
                if len(cols) < 4:
                    continue
                try:
                    lignes.append({
                        "user": cols[0],
                        "cpu": float(cols[1]),
                        "ram_mo": int(cols[2]) / 1024.0,
                        "nom": cols[3].strip()[:20],
                        "moi": (cols[0] == moi),
                    })
                except ValueError:
                    continue
    except (OSError, subprocess.TimeoutExpired):
        return [], []
    top_cpu = sorted([p for p in lignes if p["cpu"] >= 0.5], key=lambda p: p["cpu"], reverse=True)[:3]
    top_ram = sorted([p for p in lignes if p["ram_mo"] >= 10], key=lambda p: p["ram_mo"], reverse=True)[:3]
    return top_cpu, top_ram


def _tous_capteurs_et_ventilateurs():
    capteurs = []
    ventilos = []
    try:
        for hwmon in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
            try:
                nom = (hwmon / "name").read_text(encoding="utf-8").strip()
            except OSError:
                continue
            for entree in hwmon.glob("temp*_input"):
                try:
                    val = int(entree.read_text(encoding="utf-8").strip()) / 1000.0
                except (OSError, ValueError):
                    continue
                if val <= 0 or val >= 150:
                    continue
                label = ""
                try:
                    label = entree.with_name(entree.name.replace("_input", "_label")).read_text(encoding="utf-8").strip()
                except OSError:
                    pass
                capteurs.append((val, label or nom))
            for entree in hwmon.glob("fan*_input"):
                try:
                    rpm = int(entree.read_text(encoding="utf-8").strip())
                except (OSError, ValueError):
                    continue
                if rpm > 0:
                    ventilos.append((rpm, nom))
    except OSError:
        pass
    capteurs.sort(key=lambda c: c[0], reverse=True)
    return capteurs[:6], ventilos[:4]


def _systemes_fichiers_locaux():
    types_ok = {"ext4", "btrfs", "xfs", "vfat", "ntfs", "fuseblk", "zfs", "f2fs", "ext3"}
    vus_dev = set()
    sortie = []
    try:
        with open("/proc/mounts", encoding="utf-8") as f:
            for ligne in f:
                cols = ligne.split()
                if len(cols) < 3:
                    continue
                dev, mp, fstype = cols[0], cols[1], cols[2]
                if fstype not in types_ok or dev in vus_dev:
                    continue
                if mp.startswith(("/boot", "/efi")) and len(sortie) > 0:
                    pass
                vus_dev.add(dev)
                try:
                    st = os.statvfs(mp)
                    total = st.f_blocks * st.f_frsize
                    dispo = st.f_bavail * st.f_frsize
                    if total <= 0:
                        continue
                    util = max(0, total - dispo)
                    pct = 100.0 * util / total
                    sortie.append((mp, round(util / 1073741824.0, 1), round(total / 1073741824.0, 1), round(pct, 1)))
                except OSError:
                    continue
    except OSError:
        pass
    return sortie[:5]


def _swaps_et_zram():
    swaps = []
    try:
        with open("/proc/swaps", encoding="utf-8") as f:
            for ligne in f.readlines()[1:]:
                cols = ligne.split()
                if len(cols) >= 4:
                    size_go = int(cols[2]) / 1048576.0
                    used_go = int(cols[3]) / 1048576.0
                    swaps.append((Path(cols[0]).name, round(used_go, 2), round(size_go, 1)))
    except (OSError, ValueError):
        pass
    zram_info = ""
    for z in sorted(Path("/sys/block").glob("zram*/mm_stat")):
        try:
            cols = z.read_text(encoding="utf-8").split()
            if len(cols) >= 3:
                orig = int(cols[0]) / 1048576.0
                comp = int(cols[1]) / 1048576.0
                zram_info = f"{z.parent.name} : {orig:.0f} → {comp:.0f} Mo" if orig > 0 else f"{z.parent.name} : Vide"
                break
        except (OSError, ValueError):
            pass
    if not zram_info:
        try:
            en = Path("/sys/module/zswap/parameters/enabled").read_text(encoding="utf-8").strip()
            zram_info = "zswap actif" if en == "Y" else "zswap inactif"
        except OSError:
            pass
    return swaps, zram_info


def _reseau_details():
    iface = ""
    ip_lan = ""
    ssid = ""
    try:
        res = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True, timeout=1.0)
        if res.returncode == 0 and res.stdout.strip():
            cols = res.stdout.strip().splitlines()[0].split()
            if len(cols) >= 4:
                iface = cols[1]
                ip_lan = cols[3].split("/")[0]
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        res = subprocess.run(["iwgetid", "-r"], capture_output=True, text=True, timeout=1.0)
        if res.returncode == 0:
            ssid = res.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    rx_tot, tx_tot = 0, 0
    try:
        rx_tot, tx_tot = _lire_net_dev()
    except OSError:
        pass
    return {
        "iface": iface,
        "ip": ip_lan,
        "ssid": ssid,
        "rx_tot_go": round(rx_tot / 1073741824.0, 2),
        "tx_tot_go": round(tx_tot / 1073741824.0, 2),
    }


# ── Load, Disque, Réseau, Uptime, Alertes (inspiration YASSM) ────────────────
def load_mesures():
    try:
        l1, l5, l15 = os.getloadavg()
        coeurs = os.cpu_count() or 1
        pct = min(100.0, 100.0 * l1 / coeurs)
        return {
            "l1": round(l1, 2),
            "l5": round(l5, 2),
            "l15": round(l15, 2),
            "coeurs": coeurs,
            "pct": round(pct, 1),
        }
    except OSError:
        return None


def disque_racine():
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        dispo = st.f_bavail * st.f_frsize
        if total <= 0:
            return None
        utilise = max(0, total - dispo)
        pct = 100.0 * utilise / total
        return {
            "utilise_go": round(utilise / 1073741824.0, 1),
            "total_go": round(total / 1073741824.0, 1),
            "pct": round(pct, 1),
        }
    except OSError:
        return None


def _lire_net_dev():
    rx = tx = 0
    with open("/proc/net/dev", encoding="utf-8") as f:
        for ligne in f.readlines()[2:]:
            if ":" not in ligne:
                continue
            iface, reste = ligne.split(":", 1)
            if iface.strip() == "lo":
                continue
            cols = reste.split()
            if len(cols) >= 10:
                rx += int(cols[0])
                tx += int(cols[8])
    return rx, tx


def _format_debit(bps):
    if bps >= 1048576:
        return f"{bps / 1048576:.1f} M/s"
    if bps >= 1024:
        return f"{bps / 1024:.0f} K/s"
    return f"{bps:.0f} o/s"


def reseau_debits(persister=True):
    global _MEM_ETAT_NET
    try:
        maintenant = time.monotonic()
        rx2, tx2 = _lire_net_dev()
        if not persister:
            prev = _MEM_ETAT_NET
        else:
            prev = None
            try:
                with open(ETAT_NET, "r", encoding="utf-8") as f:
                    prev = json.load(f)
            except (OSError, ValueError):
                prev = None

        rx_bps = tx_bps = 0.0
        if isinstance(prev, dict):
            try:
                dt = maintenant - float(prev.get("ts", 0))
                if 0.05 <= dt <= 30.0:
                    rx_bps = max(0.0, (rx2 - int(prev["rx"])) / dt)
                    tx_bps = max(0.0, (tx2 - int(prev["tx"])) / dt)
            except (ValueError, KeyError, TypeError):
                pass

        if persister:
            tmp = f"{ETAT_NET}.tmp.{os.getpid()}"
            try:
                ETAT_NET.parent.mkdir(parents=True, exist_ok=True)
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump({"rx": rx2, "tx": tx2, "ts": maintenant}, f)
                os.replace(tmp, ETAT_NET)
            except OSError:
                if os.path.exists(tmp):
                    try:
                        os.unlink(tmp)
                    except OSError:
                        pass
        else:
            _MEM_ETAT_NET = {"rx": rx2, "tx": tx2, "ts": maintenant}

        # Référence jauge : 50 Mio/s cumulés = 100 %
        pct = min(100.0, (rx_bps + tx_bps) / (50.0 * 1048576.0) * 100.0)
        return {
            "rx_kio": round(rx_bps / 1024.0, 1),
            "tx_kio": round(tx_bps / 1024.0, 1),
            "rx_texte": _format_debit(rx_bps),
            "tx_texte": _format_debit(tx_bps),
            "pct": round(pct, 1),
        }
    except (OSError, ValueError):
        return None


def uptime_info():
    try:
        with open("/proc/uptime", encoding="utf-8") as f:
            sec = int(float(f.read().split()[0]))
        mins = (sec // 60) % 60
        heures = (sec // 3600) % 24
        jours = sec // 86400
        if jours > 0:
            texte = f"{jours}j {heures}h"
        elif sec >= 3600:
            texte = f"{sec // 3600}h{mins:02d}"
        else:
            texte = f"{max(1, sec // 60)}m"
        return {"secondes": sec, "texte": texte}
    except (OSError, ValueError, IndexError):
        return None


def _zombies_proc():
    zombies = 0
    try:
        for entree in os.listdir("/proc"):
            if not entree.isdigit():
                continue
            try:
                with open(f"/proc/{entree}/stat", "r", encoding="utf-8") as f:
                    champs = f.read().rsplit(")", 1)
                if len(champs) == 2 and champs[1].lstrip().startswith("Z"):
                    zombies += 1
            except OSError:
                continue
    except OSError:
        pass
    return zombies


def _systemd_failed(user=False):
    cmd = ["systemctl"]
    if user:
        cmd.append("--user")
    cmd.extend(["--failed", "--no-legend", "--plain", "--no-pager"])
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=1.5)
        if res.returncode != 0:
            return []
        unites = []
        for ligne in res.stdout.splitlines():
            nom = ligne.split(None, 1)[0].strip()
            if nom and nom != "●":
                unites.append(nom)
            elif nom == "●" and len(ligne.split()) > 1:
                unites.append(ligne.split()[1].strip())
        return unites
    except (OSError, subprocess.TimeoutExpired):
        return []


def alertes_systeme(barres):
    zombies = _zombies_proc()
    failed_sys = _systemd_failed(user=False)
    failed_usr = [f"user:{u}" for u in _systemd_failed(user=True)]
    systemd_failed = failed_sys + failed_usr
    seuils = [
        {"cle": b["cle"], "nom": b["nom"], "texte": b["texte"], "niveau": b["niveau"]}
        for b in barres if b.get("alerte")
    ]
    total = (1 if zombies > 0 else 0) + len(systemd_failed) + len(seuils)
    return {
        "total": total,
        "zombies": zombies,
        "systemd_failed": systemd_failed,
        "seuils": seuils,
    }


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
    elif cle == "disk":
        niveau = _niveau(valeur, 80, 92)
        remplissage = max(0.0, min(100.0, valeur))
    elif cle == "net":
        niveau = "ok"
        remplissage = max(0.0, min(100.0, valeur))
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
    mem = memoire_mesures()

    for cle in MESURES:
        if cle == "cpu":
            v, coeurs_pct, freq_ghz = cpu_mesures(persister=persister)
            if v is not None:
                barres.append(_barre(cle, v, f"{v:.0f}%"))
                detail["cpu"] = {
                    "nom": _cpu_nom(),
                    "pct": round(v, 1),
                    "coeurs": coeurs_pct,
                    "freq_ghz": freq_ghz,
                }
        elif cle == "ram":
            if mem:
                barres.append(_barre(cle, mem["ram_pct"], f"{mem['ram_pct']:.0f}%"))
                detail["ram"] = {
                    "utilisee_go": mem["utilisee_go"],
                    "totale_go": mem["totale_go"],
                    "cache_go": mem["cache_go"],
                }
        elif cle == "gpu":
            g = gpu_mesures()
            if g:
                barres.append(_barre(cle, g["utilisation"], f"{g['utilisation']:.0f}%"))
                detail["gpu"] = {
                    "pct": round(g["utilisation"], 1),
                    "temperature": g["temperature"],
                    "vram_go": round(g["vram"] / 1024, 1),
                    "vram_totale_go": round(g["vram_total"] / 1024, 1),
                    "power_w": g.get("power_w"),
                }
        elif cle == "temp":
            t = temp_cpu()
            if t is not None:
                barres.append(_barre(cle, t, f"{t:.0f}°"))
                detail["temp"] = {"cpu": round(t, 1)}
        elif cle == "load":
            ld = load_mesures()
            if ld:
                barres.append(_barre(cle, ld["pct"], f"{ld['l1']:.2f}"))
                detail["load"] = ld
        elif cle == "swap":
            if mem and mem["swap_totale_go"] > 0:
                barres.append(_barre(cle, mem["swap_pct"], f"{mem['swap_pct']:.0f}%"))
                detail["swap"] = {
                    "utilisee_go": mem["swap_utilisee_go"],
                    "totale_go": mem["swap_totale_go"],
                    "pct": round(mem["swap_pct"], 1),
                }
        elif cle == "disk":
            dk = disque_racine()
            if dk:
                barres.append(_barre(cle, dk["pct"], f"{dk['pct']:.0f}%"))
                detail["disk"] = dk
        elif cle == "net":
            nt = reseau_debits(persister=persister)
            if nt:
                barres.append(_barre(cle, nt["pct"], f"↓{nt['rx_texte']}"))
                detail["net"] = nt

    up = uptime_info()
    if up:
        detail["uptime"] = up
    detail["alerts"] = alertes_systeme(barres)

    # ── infobulles détaillées par élément (inspiration YASSM) ─────────────────
    top_cpu, top_ram = _top_proc_rapide()
    capteurs_t, ventilos_t = _tous_capteurs_et_ventilateurs()
    if ventilos_t:
        rpms = []
        for _, val in ventilos_t:
            m_rpm = re.search(r"(\d+)", str(val))
            if m_rpm:
                rpms.append(int(m_rpm.group(1)))
        if rpms:
            detail["fan_rpm"] = max(rpms)
    fs_locaux = _systemes_fichiers_locaux()
    swaps_list, zram_txt = _swaps_et_zram()
    net_det = _reseau_details()

    def _sv(nom, valeur, alerte=False):
        return {"nom": nom, "valeur": str(valeur), "alerte": bool(alerte)}

    for b in barres:
        c = b["cle"]
        sv = []
        if c == "cpu" and "cpu" in detail:
            d_cpu = detail["cpu"]
            freq = f" · {d_cpu['freq_ghz']} GHz" if d_cpu.get("freq_ghz") else ""
            sv.append(_sv("CPU", f"{b['texte']}{freq}", b["alerte"]))
            coeurs = d_cpu.get("coeurs") or []
            for i in range(0, len(coeurs), 4):
                fin = min(i + 3, len(coeurs) - 1)
                vals = " · ".join(f"{x:.0f}%" for x in coeurs[i:i + 4])
                sv.append(_sv(f"C{i}–C{fin}", vals))
            psi_c = _psi("cpu")
            if psi_c:
                sv.append(_sv("PSI CPU", psi_c))
            for p in top_cpu:
                who = "" if p["moi"] else f" ({p['user']})"
                sv.append(_sv(f"{p['nom']}{who}", f"{p['cpu']:.1f}%"))
        elif c == "ram" and "ram" in detail and mem:
            sv.append(_sv("Utilisée", f"{mem['utilisee_go']} / {mem['totale_go']} Go ({b['texte']})", b["alerte"]))
            sv.append(_sv("Disponible", f"{mem['dispo_go']} Go"))
            sv.append(_sv("Tampon / Cache", f"{mem['buffers_go']} / {mem['cache_go']} Go"))
            sv.append(_sv("htop", f"{mem['htop_go']} Go"))
            psi_m = _psi("memory")
            if psi_m:
                sv.append(_sv("PSI RAM", psi_m))
            for p in top_ram:
                who = "" if p["moi"] else f" ({p['user']})"
                val_m = f"{p['ram_mo'] / 1024:.1f} Go" if p["ram_mo"] >= 1024 else f"{p['ram_mo']:.0f} Mo"
                sv.append(_sv(f"{p['nom']}{who}", val_m))
        elif c == "swap" and "swap" in detail:
            sv.append(_sv("Swap", f"{detail['swap']['utilisee_go']} / {detail['swap']['totale_go']} Go ({b['texte']})", b["alerte"]))
            for nom_s, u_s, t_s in swaps_list:
                sv.append(_sv(nom_s, f"{u_s} / {t_s} Go"))
            if zram_txt:
                sv.append(_sv("Compression", zram_txt))
        elif c == "load" and "load" in detail:
            ld = detail["load"]
            sv.append(_sv("Charge (1/5/15m)", f"{ld['l1']} · {ld['l5']} · {ld['l15']}", b["alerte"]))
            sv.append(_sv("Normalisée", f"{ld['pct']:.0f}% ({ld['coeurs']} threads)", b["alerte"]))
        elif c == "gpu" and "gpu" in detail:
            dg = detail["gpu"]
            sv.append(_sv("GPU", f"{b['texte']} · {dg['temperature']:.0f}°C", b["alerte"]))
            sv.append(_sv("VRAM", f"{dg['vram_go']} / {dg['vram_totale_go']} Go"))
            if dg.get("power_w") is not None:
                sv.append(_sv("Puissance", f"{dg['power_w']} W"))
        elif c == "temp":
            for val_t, lbl_t in capteurs_t:
                sv.append(_sv(lbl_t[:18], f"{val_t:.1f}°C", val_t >= TEMP_ATTENTION))
            for rpm, nom_v in ventilos_t:
                sv.append(_sv(f"Ventilo ({nom_v})", f"{rpm} RPM"))
        elif c == "disk":
            for mp, u_d, t_d, pct_d in fs_locaux:
                sv.append(_sv(mp, f"{u_d} / {t_d} Go ({pct_d:.0f}%)", pct_d >= 80))
            psi_io = _psi("io")
            if psi_io:
                sv.append(_sv("PSI I/O", psi_io))
        elif c == "net" and "net" in detail:
            dn = detail["net"]
            sv.append(_sv("Débit ↓ / ↑", f"{dn['rx_texte']} / {dn['tx_texte']}"))
            sv.append(_sv("Session ↓ / ↑", f"{net_det['rx_tot_go']} / {net_det['tx_tot_go']} Go"))
            if net_det["ip"]:
                lbl_if = net_det["iface"] or "IP LAN"
                sv.append(_sv(lbl_if, net_det["ip"]))
            if net_det["ssid"]:
                sv.append(_sv("Wi-Fi", net_det["ssid"]))
        b["survol"] = sv

    survol_global = []
    if up:
        survol_global.append(_sv("Uptime", up["texte"]))
    if "load" in detail:
        survol_global.append(_sv("Load", f"{detail['load']['l1']} ({detail['load']['pct']:.0f}%)"))
    if "disk" in detail:
        survol_global.append(_sv("Disque /", f"{detail['disk']['utilise_go']} / {detail['disk']['total_go']} Go"))
    if "net" in detail:
        survol_global.append(_sv("Réseau", f"↓{detail['net']['rx_texte']} ↑{detail['net']['tx_texte']}"))
    if detail["alerts"]["total"] > 0:
        survol_global.append(_sv("Alertes", str(detail["alerts"]["total"]), True))

    donnees = {
        "ok": True,
        "ts": time.time(),
        "compact": compact(barres[0]["texte"] if barres else "", "système",
                           alerte=any(b["alerte"] for b in barres) or detail["alerts"]["total"] > 0,
                           barres=barres),
        "survol": survol_global,
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
    # Liste absente = mesures par défaut (cpu, ram, gpu, temp) ;
    # liste **vide** = aucune.
    brut = (options or {}).get("mesures")
    if brut is None:
        return list(MESURES_DEFAUT)
    return [m for m in MESURES if m in brut]


def _filtrer(donnees, options):
    """Le cache porte toutes les mesures ; le choix de l'utilisateur filtre."""
    voulues = _choisies(options)
    barres = [b for b in donnees.get("compact", {}).get("barres", []) if b["cle"] in voulues]
    copie = dict(donnees)
    compacte = dict(donnees.get("compact", {}))
    compacte["barres"] = barres
    compacte["valeur"] = barres[0]["texte"] if barres else ""
    alerts = donnees.get("detail", {}).get("alerts") or {}
    compacte["alerte"] = any(b["alerte"] for b in barres) or bool(alerts.get("zombies") or alerts.get("systemd_failed"))
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
    mon_uid = os.getuid()
    for ligne in retenues:
        ligne["commande"] = commandes.get(ligne["pid"], "")
        try:
            uid = os.stat("/proc/%d" % ligne["pid"]).st_uid
            ligne["moi"] = (uid == mon_uid)
            try:
                ligne["user"] = pwd.getpwuid(uid).pw_name
            except KeyError:
                ligne["user"] = str(uid)
        except OSError:
            ligne["moi"] = True
            ligne["user"] = ""
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
