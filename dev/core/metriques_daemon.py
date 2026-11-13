#!/usr/bin/env python3
"""Démon persistant de métriques (P1) — supprime les lancements python3 en boucle.

Importe `systeme_applet` et `reseau_widget` une seule fois au démarrage et émet
une ligne JSON sur stdout à chaque période pour les widgets et l'îlot.
"""
from __future__ import annotations

import json
import signal
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reseau_widget
import systeme_applet

_ACTIF = True


def _arreter(_sig, _frame):
    global _ACTIF
    _ACTIF = False


def main(argv: list[str]) -> int:
    signal.signal(signal.SIGTERM, _arreter)
    signal.signal(signal.SIGINT, _arreter)
    intervalle = 2.0
    if len(argv) >= 2:
        try:
            intervalle = max(1.0, float(argv[1]))
        except ValueError:
            pass

    while _ACTIF:
        debut = time.monotonic()
        charge = {}
        try:
            charge["systeme"] = systeme_applet.analyser(force=True, persister=False)
        except Exception:
            charge["systeme"] = {"ok": False}
        try:
            charge["reseau"] = reseau_widget.analyser(persister=False)
        except Exception:
            charge["reseau"] = {"ok": False}
        try:
            sys.stdout.write(json.dumps(charge, ensure_ascii=False) + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            return 0
        ecoule = time.monotonic() - debut
        reste = intervalle - ecoule
        if reste > 0.05:
            time.sleep(reste)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
