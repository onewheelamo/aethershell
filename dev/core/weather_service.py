#!/usr/bin/env python3
"""Météo des widgets de bureau — Open-Meteo, sans clé d'API.

    weather_service.py [--city "Paris, France"] [--force]

Une ligne JSON sur stdout, rien d'autre.

Résolution de la position, dans l'ordre :
  1. --city
  2. l'option `city` du widget (`widget_set meteo-1 city "Paris, Texas, usa"`)
  3. `weather_city` de style_vars.json
  4. à défaut : géolocalisation par IP — c'est le réglage par défaut

Une ville peut porter le pays et/ou la région : « Paris, France » et
« Paris, Texas, usa » désignent deux endroits différents. Le texte est découpé
sur les virgules — premier segment = nom, le reste = indices (pays, région) — le
géocodage est interrogé large (count=20) et les candidats sont départagés par
pays, par région, puis par population.

Cache de 10 minutes dans core/weather_cache.json : le widget interroge le
service toutes les dix minutes, le cache évite une requête par cycle et sert la
dernière valeur connue (`stale: true`) quand le réseau tombe. La géolocalisation
IP suit le même cache : une requête IP toutes les dix minutes au plus.

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
DEFAULT_CITY = ""  # vide = géolocalisation par IP

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

# Pays en toutes lettres ou en code ISO -> code ISO. Sert à départager deux
# villes homonymes ; une abréviation de deux lettres est acceptée telle quelle.
COUNTRY_ALIASES = {
    "france": "FR", "fr": "FR",
    "usa": "US", "us": "US", "etats-unis": "US", "états-unis": "US",
    "united states": "US", "etats unis": "US",
    "belgique": "BE", "belgium": "BE", "be": "BE",
    "suisse": "CH", "switzerland": "CH", "ch": "CH",
    "canada": "CA", "ca": "CA",
    "allemagne": "DE", "germany": "DE", "de": "DE",
    "espagne": "ES", "spain": "ES", "es": "ES",
    "italie": "IT", "italy": "IT", "it": "IT",
    "portugal": "PT", "pt": "PT",
    "royaume-uni": "GB", "uk": "GB", "gb": "GB", "angleterre": "GB",
    "luxembourg": "LU", "lu": "LU",
    "pays-bas": "NL", "netherlands": "NL", "nl": "NL",
    "maroc": "MA", "morocco": "MA", "ma": "MA",
    "algerie": "DZ", "algérie": "DZ", "dz": "DZ",
    "tunisie": "TN", "tn": "TN",
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


# ─────────────────────────────────────────────────────────────────────────────
# Résolution de la position
# ─────────────────────────────────────────────────────────────────────────────
def parse_city_spec(spec):
    """« Paris, Texas, usa » -> ("Paris", "US", ["texas"])."""
    parts = [p.strip() for p in spec.split(",") if p.strip()]
    if not parts:
        return "", None, []
    name, country, hints = parts[0], None, []
    for token in parts[1:]:
        low = token.lower()
        if country is None and low in COUNTRY_ALIASES:
            country = COUNTRY_ALIASES[low]
        else:
            hints.append(low)
    return name, country, hints


def geocode_city(spec):
    name, country, hints = parse_city_spec(spec)
    if not name:
        raise RuntimeError("ville vide")

    url = ("https://geocoding-api.open-meteo.com/v1/search?name="
           + urllib.parse.quote(name) + "&count=20&language=fr&format=json")
    results = http_json(url).get("results") or []
    if not results:
        raise RuntimeError(f"ville introuvable : {spec}")

    def score(hit):
        value = 0.0
        code = (hit.get("country_code") or "").upper()
        admin = (hit.get("admin1") or "").lower()
        country_name = (hit.get("country") or "").lower()

        if country:
            value += 100 if code == country else -50
        for hint in hints:
            if hint and (admin.startswith(hint) or hint in admin or hint in country_name):
                value += 30
        # À égalité, la ville la plus peuplée est celle qu'on cherche.
        value += min(10.0, (hit.get("population") or 0) / 1_000_000.0)
        return value

    best = max(results, key=score)
    return {
        "lat": float(best["latitude"]),
        "lon": float(best["longitude"]),
        "ville": best.get("name") or name,
        "pays": (best.get("country_code") or "").upper(),
        # Le fuseau sert au panneau (tiroir Localisation) et à l'horloge.
        "tz": best.get("timezone") or "",
        "libelle": ", ".join(x for x in (best.get("name") or name, best.get("country") or "") if x),
    }


def ip_locate():
    """Géolocalisation par IP : ipapi.co, puis ip-api.com en repli.

    Deux services sans clé, appelés au plus une fois par cache : si les deux
    échouent, le service remonte l'erreur et le widget garde sa dernière valeur.
    """
    try:
        data = http_json("https://ipapi.co/json/")
        if data.get("latitude") is not None and data.get("longitude") is not None:
            return (float(data["latitude"]), float(data["longitude"]),
                    data.get("city") or "—", (data.get("country_code") or "").upper())
    except Exception:
        pass

    data = http_json("http://ip-api.com/json/?fields=status,city,countryCode,lat,lon")
    if data.get("status") != "success" or data.get("lat") is None:
        raise RuntimeError("géolocalisation par IP indisponible")
    return (float(data["lat"]), float(data["lon"]),
            data.get("city") or "—", (data.get("countryCode") or "").upper())


# ─────────────────────────────────────────────────────────────────────────────
# Météo
# ─────────────────────────────────────────────────────────────────────────────
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


def stored_location():
    """Localisation réglée dans le panneau (tiroir « Localisation »).

    Rend None si les coordonnées sont absentes : un champ vide ne vaut pas zéro,
    sinon le service demanderait la météo au large du golfe de Guinée.
    """
    data = read_json(STYLE_FILE, {}) or {}
    try:
        lat = float(data.get("user_location_lat"))
        lon = float(data.get("user_location_lon"))
    except (TypeError, ValueError):
        return None
    return {"lat": lat, "lon": lon,
            "ville": str(data.get("user_location_ville") or "").strip(),
            "tz": str(data.get("user_location_tz") or "").strip()}


def resolve_spec(argv):
    """Ville demandée : --city, sinon style_vars.json, sinon vide (= IP)."""
    if "--city" in argv:
        idx = argv.index("--city")
        if idx + 1 < len(argv) and argv[idx + 1].strip():
            return argv[idx + 1].strip()
    stored = str(read_json(STYLE_FILE, {}).get("weather_city") or "").strip()
    return stored or DEFAULT_CITY


def main():
    argv = sys.argv[1:]

    # Mode géocodage, pour le bouton « Vérifier la ville » du panneau :
    #   weather_service.py --geocode "Paris, France"
    if "--geocode" in argv:
        idx = argv.index("--geocode")
        demande = argv[idx + 1] if idx + 1 < len(argv) else ""
        try:
            g = geocode_city(demande)
            g["ok"] = True
            print(json.dumps(g, ensure_ascii=False))
        except Exception as exc:
            print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False))
        return 0

    force = "--force" in argv
    loc = stored_location()
    spec = "" if loc else resolve_spec(argv)

    key = ("loc:%.4f,%.4f" % (loc["lat"], loc["lon"])) if loc else (spec.lower() if spec else "__auto__")
    cache = read_json(CACHE_FILE, {}) or {}
    same = cache.get("spec") == key and cache.get("lat") is not None
    fresh = same and (time.time() - float(cache.get("fetched") or 0) < TTL)

    if fresh and not force:
        out = dict(cache.get("data") or {})
        out["ok"] = True
        out["city"] = cache.get("label") or "—"
        out["source"] = cache.get("source") or ("city" if spec else "ip")
        out["cached"] = True
        print(json.dumps(out, ensure_ascii=False))
        return 0

    try:
        if same:
            lat, lon = float(cache["lat"]), float(cache["lon"])
            label = cache.get("label") or "—"
            source = cache.get("source") or ("city" if spec else "ip")
        elif loc:
            lat, lon = loc["lat"], loc["lon"]
            label = loc["ville"] or "Localisation réglée"
            source = "location"
        elif spec:
            g = geocode_city(spec)
            lat, lon, label = g["lat"], g["lon"], g["ville"]
            source = "city"
        else:
            lat, lon, label, _ = ip_locate()
            source = "ip"

        data = fetch(lat, lon)
        data["city"] = label
        data["source"] = source
        data["cached"] = False

        try:
            CACHE_FILE.write_text(json.dumps({
                "spec": key, "label": label, "lat": lat, "lon": lon, "source": source,
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
            out["city"] = cache.get("label") or "—"
            out["source"] = cache.get("source") or "?"
            out["cached"] = True
            out["stale"] = True
            print(json.dumps(out, ensure_ascii=False))
        else:
            print(json.dumps({"ok": False, "error": str(exc), "city": spec or "—"},
                             ensure_ascii=False))
        return 0


if __name__ == "__main__":
    sys.exit(main())
