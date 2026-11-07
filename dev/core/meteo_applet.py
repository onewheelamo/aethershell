#!/usr/bin/env python3
"""Applet Météo — température et condition dans la barre.

    meteo_applet.py [--options={"city": "Paris, France"}]

Une ligne JSON sur stdout, au contrat des applets (voir applet_contrat.py). Les
données viennent de `core/weather_service.py` (Open-Meteo, sans clé, cache de
dix minutes) : cet applet ne fait que choisir ce que la barre montre et ranger
le reste pour le popup.

Règles tenues ici :

  * **jamais d'alerte.** Une météo n'est pas une panne : `alerte` reste faux,
    même quand le service échoue. La barre affiche « — » et le popup dit
    pourquoi ;
  * le compact tient en trois caractères (« 9° ») ; la condition et la ville
    vont dans le libellé, que la barre n'affiche pas mais que l'infobulle lit ;
  * l'icône suit la condition, avec les glyphes qui existent vraiment dans le
    singleton Icon du shell (sun, cloud, weather-cloud, weather-night) — une
    condition sans glyphe propre retombe sur un nuage plutôt que sur du vide.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applet_contrat import presenter, sortir  # noqa: E402

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVICE = os.path.join(BASE_DIR, "weather_service.py")

# Conditions rendues par weather_service.py → glyphes réellement présents dans
# Icon.qml. La pluie, la neige et l'orage n'ont pas de glyphe : un nuage est plus
# honnête qu'une icône absente.
GLYPHES = {
    "sun": "sun",
    "clear": "sun",
    "moon": "weather-night",
    "night": "weather-night",
    "cloud": "cloud",
    "overcast": "cloud",
    "fog": "weather-cloud",
    "rain": "weather-cloud",
    "drizzle": "weather-cloud",
    "snow": "weather-cloud",
    "storm": "weather-cloud",
}


def _options_cli(argv):
    for arg in argv[1:]:
        if arg.startswith("--options="):
            try:
                return json.loads(arg.split("=", 1)[1])
            except ValueError:
                return {}
    return {}


def lire_meteo(city=""):
    """Interroge le service. Il gère son cache : l'appel est bon marché."""
    commande = [sys.executable, SERVICE]
    if city:
        commande += ["--city", city]
    try:
        proc = subprocess.run(commande, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as e:
        return {"ok": False, "error": "service injoignable : %s" % e}
    try:
        return json.loads(proc.stdout.strip() or "{}")
    except ValueError:
        return {"ok": False, "error": "réponse illisible du service météo"}


def analyser(options):
    options = options or {}
    ville = str(options.get("city") or "").strip()
    d = lire_meteo(ville)

    if not d.get("ok"):
        return {
            "ok": False,
            "applet": "meteo",
            "icone": "cloud",
            "error": str(d.get("error") or "météo indisponible"),
            "compact": {"valeur": "—", "libelle": "météo", "alerte": False},
            "detail": {},
        }

    temp = d.get("temp")
    valeur = "%d°" % round(float(temp)) if isinstance(temp, (int, float)) else "—"
    libelle = "%s · %s" % (str(d.get("label") or ""), str(d.get("city") or ""))
    icone = GLYPHES.get(str(d.get("icon") or "").lower(),
                        "weather-night" if not d.get("day", True) else "cloud")

    return {
        "ok": True,
        "applet": "meteo",
        "icone": icone,
        # Une météo ne passe jamais la barre en couleur d'alerte.
        "alerte": False,
        "compact": {"valeur": valeur, "libelle": libelle.strip(" ·"), "alerte": False},
        "detail": {
            "temp": temp,
            "feels": d.get("feels"),
            "tmin": d.get("tmin"),
            "tmax": d.get("tmax"),
            "label": d.get("label"),
            "city": d.get("city"),
            "day": d.get("day"),
            "code": d.get("code"),
            "source": d.get("source"),
            "updated": d.get("updated"),
            # `cached` = dernière valeur connue servie parce que le réseau est
            # tombé : le popup doit le dire, pas le cacher.
            "cached": bool(d.get("cached")),
        },
    }


def main(argv):
    donnees = analyser(_options_cli(argv))
    if donnees.get("ok"):
        presenter(donnees, "meteo", donnees["icone"], donnees["compact"])
    return sortir(donnees)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
