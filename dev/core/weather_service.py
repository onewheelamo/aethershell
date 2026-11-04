#!/usr/bin/env python3
"""Météo des widgets de bureau — Open-Meteo, sans clé d'API.

    weather_service.py [--city NOM] [--force]

Une ligne JSON sur stdout, rien d'autre. Le résultat est mis en cache 10 minutes
dans core/weather_cache.json : le widget interroge la service toutes les dix
minutes, le cache évite une requête inutile quand deux widgets météo coexistent
et rend une valeur — marquée `cached` — même si le réseau tombe.

Ordre de résolution de la ville : --city, puis `weather_city` dans
style_vars.json (réglable par `config_manager.py style weather_city Lyon`), puis
« Paris ». Le géocodage n'est fait qu'une fois : ses coordonnées sont mémorisées
dans le cache.

Sortie en cas d'échec : {"ok": false, "error": "..."} avec un code de retour 0 —
le widget affiche alors un tiret plutôt que de disparaître.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
STYLE_FILE = BASE_DIR / "style_vars.json"
CACHE_FILE = BASE_DIR / "weather_cache.json"

TTL = 600
DEFAULT_CITY = "Paris"

# Codes WMO -> (libellé français, glyphe). Deux glyphes seulement : « sun » et
# « cloud » existent dans Icon.qml, inutile d'inventer un nom que la police
# d'icônes ne connaît pas — un glyphe inconnu rend un carré vide, pas une erreur.
WMO = {
    0: ("Dégagé", "sun"),
    1: ("Peu nuageux", "sun"),
    2: ("Partiellement nuageux", "cloud"),
    3: ("Couvert", "cloud"),
    45: ("Brouillard", "cloud"),
    48: ("Brouillard givrant", "cloud"),
    51: ("Bruine faible", "cloud"),
    53: ("Bruine", "cloud"),
    55: ("Bruine forte", "cloud"),
    56: ("Bruine verglaçante", "cloud"),
    57: ("Bruine verglaçante forte", "cloud"),
    61: ("Pluie faible", "cloud"),
    63: ("Pluie", "cloud"),
    65: ("Pluie forte", "cloud"),
    66: ("Pluie verglaçante", "cloud"),
    67: ("Pluie verglaçante forte", "cloud"),
    71: ("Neige faible", "cloud"),
    73: ("Neige", "cloud"),
    75: ("Neige forte", "cloud"),
    77: ("Grains de neige", "cloud"),
    80: ("Averses faibles", "cloud"),
    81: ("Averses", "cloud"),
    82: ("Averses violentes", "cloud"),
    85: ("Averses de neige", "cloud"),
    86: ("Averses de neige fortes", "cloud"),
    95: ("Orage", "cloud"),
    96: ("Orage avec grêle", "cloud"),
    99: ("Orage avec grêle forte", "cloud"),
}


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def http_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "quickshell-todo/1.0"})
    with urllib.request.urlopen(req, timeout=12) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def geocode(city):
    url = ("https://geocoding-api.open-meteo.com/v1/search?name="
           + urllib.parse.quote(city) + "&count=1&language=fr&format=json")
    results = http_json(url).get("results") or []
    if not results:
        raise RuntimeError(f"ville introuvable : {city}")
    hit = results[0]
    return float(hit["latitude"]), float(hit["longitude"]), hit.get("name") or city


def fetch(lat, lon):
    url = ("https://api.open-meteo.com/v1/forecast"
           f"?latitude={lat:.4f}&longitude={lon:.4f}"
           "&current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"
           "&daily=temperature_2m_max,temperature_2m_min"
           "&timezone=auto&forecast_days=1")
    payload = http_json(url)
    current = payload.get("current") or {}
    daily = payload.get("daily") or {}

    code = int(current.get("weather_code") or 0)
    label, icon = WMO.get(code, ("—", "cloud"))
    tmin = (daily.get("temperature_2m_min") or [None])[0]
    tmax = (daily.get("temperature_2m_max") or [None])[0]

    return {
        "ok": True,
        "temp": round(float(current.get("temperature_2m") or 0), 1),
        "feels": round(float(current.get("apparent_temperature") or 0), 1),
        "code": code,
        "label": label,
        "icon": icon,
        "day": bool(current.get("is_day", 1)),
        "tmin": round(float(tmin), 1) if tmin is not None else None,
        "tmax": round(float(tmax), 1) if tmax is not None else None,
        "updated": int(time.time()),
    }


def main():
    argv = sys.argv[1:]
    force = "--force" in argv

    city = ""
    if "--city" in argv:
        idx = argv.index("--city")
        if idx + 1 < len(argv):
            city = argv[idx + 1].strip()
    if not city:
        city = str(read_json(STYLE_FILE, {}).get("weather_city") or "").strip()
    if not city:
        city = DEFAULT_CITY

    cache = read_json(CACHE_FILE, {}) or {}
    same_city = cache.get("city") == city and cache.get("lat") is not None
    fresh = same_city and (time.time() - float(cache.get("fetched") or 0) < TTL)

    if fresh and not force:
        out = dict(cache.get("data") or {})
        out["ok"] = True
        out["city"] = cache.get("label") or city
        out["cached"] = True
        print(json.dumps(out, ensure_ascii=False))
        return 0

    try:
        if same_city:
            lat, lon = float(cache["lat"]), float(cache["lon"])
            label = cache.get("label") or city
        else:
            lat, lon, label = geocode(city)

        data = fetch(lat, lon)
        data["city"] = label
        data["cached"] = False

        try:
            CACHE_FILE.write_text(json.dumps({
                "city": city, "label": label, "lat": lat, "lon": lon,
                "fetched": int(time.time()), "data": data,
            }, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass  # un cache non écrit ne doit pas priver de la valeur du jour

        print(json.dumps(data, ensure_ascii=False))
        return 0
    except Exception as exc:
        # Une météo périmée vaut mieux qu'une case vide.
        stale = cache.get("data") if cache else None
        if stale:
            out = dict(stale)
            out["ok"] = True
            out["city"] = cache.get("label") or city
            out["cached"] = True
            out["stale"] = True
            print(json.dumps(out, ensure_ascii=False))
        else:
            print(json.dumps({"ok": False, "error": str(exc), "city": city},
                             ensure_ascii=False))
        return 0


if __name__ == "__main__":
    sys.exit(main())
