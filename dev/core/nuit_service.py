#!/usr/bin/env python3
"""Mode nuit : filtre chaud de l'écran, à la main ou sur une plage horaire.

Le filtre est appliqué par `hyprsunset`, qui reste en écoute une fois lancé : on
lui parle par `hyprctl hyprsunset`. Sans plage horaire configurée, rien n'est
automatique — c'est l'utilisateur qui allume et éteint. Dès qu'une plage existe,
`appliquer` allume dans l'intervalle et éteint en dehors, à chaque minute.

L'état vit dans style_vars.json, à côté des autres réglages du shell :

    night_mode   allumé / éteint
    night_temp   température en kelvins (2200-6500)
    night_from   début de plage « 21:00 » (vide = pas de plage)
    night_to     fin de plage « 07:00 »

    python3 nuit_service.py etat
    python3 nuit_service.py basculer
    python3 nuit_service.py activer | desactiver
    python3 nuit_service.py temperature 4000
    python3 nuit_service.py plage 21:00 07:00   (ou: plage "" "")
    python3 nuit_service.py appliquer
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

BASE = os.path.dirname(os.path.abspath(__file__))
STYLE = os.path.join(BASE, "style_vars.json")

TEMPERATURE_DEFAUT = 4000
TEMPERATURE_MIN = 2200
TEMPERATURE_MAX = 6500


# ── état ────────────────────────────────────────────────────────────────────
def _lire():
    try:
        with open(STYLE, "r", encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        d = {}
    return d if isinstance(d, dict) else {}


def _ecrire(cle, valeur):
    d = _lire()
    d[cle] = valeur
    tmp = STYLE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(tmp, STYLE)


def etat():
    d = _lire()
    temp = d.get("night_temp")
    return {
        "allume": bool(d.get("night_mode", False)),
        "temperature": int(temp) if isinstance(temp, (int, float)) else TEMPERATURE_DEFAUT,
        "de": str(d.get("night_from") or ""),
        "a": str(d.get("night_to") or ""),
        "plage": bool(str(d.get("night_from") or "").strip()),
        "daemon": os.path.exists(_socket()),
    }


# ── hyprsunset ──────────────────────────────────────────────────────────────
def _signature():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        return sig
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid())), "hypr")
    try:
        entrees = sorted(os.listdir(base))
    except OSError:
        return None
    return entrees[-1] if entrees else None


def _socket():
    sig = _signature()
    racine = os.environ.get("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    if not sig:
        return os.path.join(racine, "hypr", "absent", ".hyprsunset.sock")
    return os.path.join(racine, "hypr", sig, ".hyprsunset.sock")


def _env():
    sig = _signature()
    e = dict(os.environ)
    if sig:
        e["HYPRLAND_INSTANCE_SIGNATURE"] = sig
    e.setdefault("XDG_RUNTIME_DIR", "/run/user/" + str(os.getuid()))
    return e


def _hyprctl(*args):
    try:
        return subprocess.run(["hyprctl", "hyprsunset"] + list(args), capture_output=True,
                              text=True, timeout=5, env=_env())
    except (OSError, subprocess.TimeoutExpired) as e:
        return None


def _demarrer_daemon():
    """hyprsunset doit écouter pour recevoir les ordres ; on le lance en identité."""
    if os.path.exists(_socket()):
        return True
    try:
        subprocess.Popen(["hyprsunset", "-i"], env=_env(),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except OSError:
        return False
    for _ in range(20):
        if os.path.exists(_socket()):
            return True
        time.sleep(0.1)
    return False


def appliquer_filtre(temp):
    if not _demarrer_daemon():
        return False
    if temp is None:
        res = _hyprctl("identity")
    else:
        res = _hyprctl("temperature", str(int(temp)))
    return res is not None and res.returncode == 0


# ── plage horaire ───────────────────────────────────────────────────────────
def _minutes(hhmm):
    m = re.match(r"^\s*(\d{1,2})[:h](\d{2})\s*$", str(hhmm or ""))
    if not m:
        return None
    h, mn = int(m.group(1)), int(m.group(2))
    if h > 23 or mn > 59:
        return None
    return h * 60 + mn


def dans_la_plage(maintenant, debut, fin):
    if debut is None or fin is None:
        return False
    if debut == fin:
        return False
    if debut < fin:
        return debut <= maintenant < fin
    # plage qui passe minuit, ex. 21:00 → 07:00
    return maintenant >= debut or maintenant < fin


def appliquer():
    e = etat()
    if not e["plage"]:
        return e          # aucune plage : rien d'automatique
    debut, fin = _minutes(e["de"]), _minutes(e["a"])
    if debut is None or fin is None:
        return e
    maintenant = time.localtime()
    minute = maintenant.tm_hour * 60 + maintenant.tm_min
    vouloir = dans_la_plage(minute, debut, fin)
    if vouloir != e["allume"]:
        _ecrire("night_mode", vouloir)
        appliquer_filtre(e["temperature"] if vouloir else None)
        e = etat()
    elif vouloir and not e["daemon"]:
        appliquer_filtre(e["temperature"])
        e = etat()
    return e


def main(argv):
    action = (argv[1] if len(argv) > 1 else "etat").strip()

    if action == "etat":
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    if action in ("activer", "desactiver", "basculer"):
        e = etat()
        vouloir = e["allume"] if action == "basculer" else action == "activer"
        if action == "basculer":
            vouloir = not e["allume"]
        ok = appliquer_filtre(e["temperature"] if vouloir else None)
        if ok:
            _ecrire("night_mode", vouloir)
        print(json.dumps({"ok": ok, **etat()}, ensure_ascii=False))
        return 0 if ok else 1

    if action == "temperature" and len(argv) > 2:
        try:
            temp = int(argv[2])
        except ValueError:
            return 2
        temp = max(TEMPERATURE_MIN, min(TEMPERATURE_MAX, temp))
        _ecrire("night_temp", temp)
        if etat()["allume"]:
            appliquer_filtre(temp)
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    if action == "plage":
        debut = argv[2].strip() if len(argv) > 2 else ""
        fin = argv[3].strip() if len(argv) > 3 else ""
        if debut and (_minutes(debut) is None or _minutes(fin) is None):
            print(json.dumps({"ok": False, "erreur": "heure invalide (HH:MM)"}, ensure_ascii=False))
            return 2
        _ecrire("night_from", debut)
        _ecrire("night_to", fin)
        print(json.dumps(etat(), ensure_ascii=False))
        return 0

    if action == "appliquer":
        print(json.dumps(appliquer(), ensure_ascii=False))
        return 0

    print(json.dumps({"erreur": "action inconnue"}, ensure_ascii=False))
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
