use crate::common::contrat::sortir;
use crate::common::io::{parse_options_arg, read_json_value, write_json_atomic};
use crate::common::paths::core_dir;
use serde_json::{json, Map, Value};
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TTL_SECS: u64 = 600;

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn wmo_info(code: i64) -> (&'static str, &'static str) {
    match code {
        0 => ("Dégagé", "sun"),
        1 => ("Peu nuageux", "sun"),
        2 => ("Partiellement nuageux", "cloud"),
        3 => ("Couvert", "cloud"),
        45 => ("Brouillard", "cloud"),
        48 => ("Brouillard givrant", "cloud"),
        51 => ("Bruine faible", "cloud"),
        53 => ("Bruine", "cloud"),
        55 => ("Bruine forte", "cloud"),
        56 => ("Bruine verglaçante", "cloud"),
        57 => ("Bruine verglaçante forte", "cloud"),
        61 => ("Pluie faible", "cloud"),
        63 => ("Pluie", "cloud"),
        65 => ("Pluie forte", "cloud"),
        66 => ("Pluie verglaçante", "cloud"),
        67 => ("Pluie verglaçante forte", "cloud"),
        71 => ("Neige faible", "cloud"),
        73 => ("Neige", "cloud"),
        75 => ("Neige forte", "cloud"),
        77 => ("Grains de neige", "cloud"),
        80 => ("Averses faibles", "cloud"),
        81 => ("Averses", "cloud"),
        82 => ("Averses violentes", "cloud"),
        85 => ("Averses de neige", "cloud"),
        86 => ("Averses de neige fortes", "cloud"),
        95 => ("Orage", "cloud"),
        96 => ("Orage avec grêle", "cloud"),
        99 => ("Orage avec grêle forte", "cloud"),
        _ => ("—", "cloud"),
    }
}

fn country_alias(token: &str) -> Option<&'static str> {
    match token {
        "france" | "fr" => Some("FR"),
        "usa" | "us" | "etats-unis" | "états-unis" | "united states" | "etats unis" => Some("US"),
        "belgique" | "belgium" | "be" => Some("BE"),
        "suisse" | "switzerland" | "ch" => Some("CH"),
        "canada" | "ca" => Some("CA"),
        "allemagne" | "germany" | "de" => Some("DE"),
        "espagne" | "spain" | "es" => Some("ES"),
        "italie" | "italy" | "it" => Some("IT"),
        "portugal" | "pt" => Some("PT"),
        "royaume-uni" | "uk" | "gb" | "angleterre" => Some("GB"),
        "luxembourg" | "lu" => Some("LU"),
        "pays-bas" | "netherlands" | "nl" => Some("NL"),
        "maroc" | "morocco" | "ma" => Some("MA"),
        "algerie" | "algérie" | "dz" => Some("DZ"),
        "tunisie" | "tn" => Some("TN"),
        _ => None,
    }
}

fn http_json(url: &str) -> Result<Value, String> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(12))
        .user_agent("quickshell-todo/1.0")
        .build();
    let resp = agent.get(url).call().map_err(|e| e.to_string())?;
    resp.into_json::<Value>().map_err(|e| e.to_string())
}

fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.as_bytes() {
        match *b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(*b as char),
            b' ' => out.push_str("%20"),
            other => out.push_str(&format!("%{other:02X}")),
        }
    }
    out
}

fn geocode_city(spec: &str) -> Result<Value, String> {
    let parts: Vec<&str> = spec.split(',').map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
    if parts.is_empty() {
        return Err("ville vide".into());
    }
    let name = parts[0];
    let mut country: Option<&'static str> = None;
    let mut hints: Vec<String> = Vec::new();
    for tok in &parts[1..] {
        let low = tok.to_ascii_lowercase();
        if country.is_none() {
            if let Some(c) = country_alias(&low) {
                country = Some(c);
                continue;
            }
        }
        hints.push(low);
    }

    let url = format!(
        "https://geocoding-api.open-meteo.com/v1/search?name={}&count=20&language=fr&format=json",
        url_encode(name)
    );
    let payload = http_json(&url)?;
    let results = payload
        .get("results")
        .and_then(|v| v.as_array())
        .filter(|a| !a.is_empty())
        .ok_or_else(|| format!("ville introuvable : {spec}"))?;

    let best = results
        .iter()
        .max_by(|a, b| {
            let score = |hit: &Value| -> f64 {
                let mut v = 0.0;
                let code = hit.get("country_code").and_then(|x| x.as_str()).unwrap_or("").to_ascii_uppercase();
                let admin = hit.get("admin1").and_then(|x| x.as_str()).unwrap_or("").to_ascii_lowercase();
                let cname = hit.get("country").and_then(|x| x.as_str()).unwrap_or("").to_ascii_lowercase();
                if let Some(c) = country {
                    v += if code == c { 100.0 } else { -50.0 };
                }
                for h in &hints {
                    if !h.is_empty() && (admin.starts_with(h) || admin.contains(h) || cname.contains(h)) {
                        v += 30.0;
                    }
                }
                let pop = hit.get("population").and_then(|x| x.as_f64()).unwrap_or(0.0);
                v + (pop / 1_000_000.0).min(10.0)
            };
            score(a).partial_cmp(&score(b)).unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap();

    let lat = best.get("latitude").and_then(|v| v.as_f64()).ok_or("latitude manquante")?;
    let lon = best.get("longitude").and_then(|v| v.as_f64()).ok_or("longitude manquante")?;
    let ville = best.get("name").and_then(|v| v.as_str()).unwrap_or(name);
    let pays = best.get("country_code").and_then(|v| v.as_str()).unwrap_or("").to_ascii_uppercase();
    let tz = best.get("timezone").and_then(|v| v.as_str()).unwrap_or("");
    let c_full = best.get("country").and_then(|v| v.as_str()).unwrap_or("");
    let libelle = if c_full.is_empty() { ville.to_string() } else { format!("{ville}, {c_full}") };

    Ok(json!({
        "lat": lat,
        "lon": lon,
        "ville": ville,
        "pays": pays,
        "tz": tz,
        "libelle": libelle,
    }))
}

fn ip_locate() -> Result<(f64, f64, String), String> {
    if let Ok(d) = http_json("https://ipapi.co/json/") {
        if let (Some(lat), Some(lon)) = (
            d.get("latitude").and_then(|v| v.as_f64()),
            d.get("longitude").and_then(|v| v.as_f64()),
        ) {
            let city = d.get("city").and_then(|v| v.as_str()).unwrap_or("—").to_string();
            return Ok((lat, lon, city));
        }
    }
    let d = http_json("http://ip-api.com/json/?fields=status,city,countryCode,lat,lon")?;
    if d.get("status").and_then(|v| v.as_str()) == Some("success") {
        if let (Some(lat), Some(lon)) = (
            d.get("lat").and_then(|v| v.as_f64()),
            d.get("lon").and_then(|v| v.as_f64()),
        ) {
            let city = d.get("city").and_then(|v| v.as_str()).unwrap_or("—").to_string();
            return Ok((lat, lon, city));
        }
    }
    Err("géolocalisation par IP indisponible".into())
}

fn round1(v: f64) -> f64 {
    (v * 10.0).round() / 10.0
}

fn fetch_forecast(lat: f64, lon: f64) -> Result<Map<String, Value>, String> {
    let url = format!(
        "https://api.open-meteo.com/v1/forecast?latitude={lat:.4}&longitude={lon:.4}\
        &current=temperature_2m,apparent_temperature,weather_code,is_day,\
        relative_humidity_2m,wind_speed_10m,wind_direction_10m,precipitation,pressure_msl\
        &daily=temperature_2m_max,temperature_2m_min,weather_code,\
        precipitation_probability_max,sunrise,sunset&timezone=auto&forecast_days=6"
    );
    let payload = http_json(&url)?;
    let cur = payload.get("current").and_then(|v| v.as_object()).cloned().unwrap_or_default();
    let daily = payload.get("daily").and_then(|v| v.as_object()).cloned().unwrap_or_default();

    let code = cur.get("weather_code").and_then(|v| v.as_i64()).unwrap_or(0);
    let (label, icon) = wmo_info(code);
    let tmin = daily.get("temperature_2m_min").and_then(|v| v.as_array()).and_then(|a| a.first()).and_then(|v| v.as_f64());
    let tmax = daily.get("temperature_2m_max").and_then(|v| v.as_array()).and_then(|a| a.first()).and_then(|v| v.as_f64());

    let jours = daily.get("time").and_then(|v| v.as_array()).cloned().unwrap_or_default();
    let mut prev = Vec::new();
    for (i, d_val) in jours.iter().enumerate() {
        let c = daily.get("weather_code").and_then(|v| v.get(i)).and_then(|v| v.as_i64()).unwrap_or(0);
        let (etiq, ico) = wmo_info(c);
        let d_min = daily.get("temperature_2m_min").and_then(|v| v.get(i)).and_then(|v| v.as_f64()).map(round1);
        let d_max = daily.get("temperature_2m_max").and_then(|v| v.get(i)).and_then(|v| v.as_f64()).map(round1);
        let pluie = daily.get("precipitation_probability_max").and_then(|v| v.get(i)).cloned().unwrap_or(Value::Null);
        let lever = daily.get("sunrise").and_then(|v| v.get(i)).cloned().unwrap_or(Value::Null);
        let coucher = daily.get("sunset").and_then(|v| v.get(i)).cloned().unwrap_or(Value::Null);
        prev.push(json!({
            "date": d_val,
            "tmin": d_min,
            "tmax": d_max,
            "code": c,
            "label": etiq,
            "icon": ico,
            "pluie": pluie,
            "lever": lever,
            "coucher": coucher,
        }));
    }

    let mut m = Map::new();
    m.insert("ok".into(), json!(true));
    m.insert("temp".into(), json!(round1(cur.get("temperature_2m").and_then(|v| v.as_f64()).unwrap_or(0.0))));
    m.insert("feels".into(), json!(round1(cur.get("apparent_temperature").and_then(|v| v.as_f64()).unwrap_or(0.0))));
    m.insert("humidite".into(), cur.get("relative_humidity_2m").cloned().unwrap_or(Value::Null));
    m.insert("vent".into(), json!(round1(cur.get("wind_speed_10m").and_then(|v| v.as_f64()).unwrap_or(0.0))));
    m.insert("vent_dir".into(), cur.get("wind_direction_10m").cloned().unwrap_or(Value::Null));
    m.insert("pluie_mm".into(), cur.get("precipitation").cloned().unwrap_or(Value::Null));
    m.insert("pression".into(), cur.get("pressure_msl").cloned().unwrap_or(Value::Null));
    m.insert("previsions".into(), Value::Array(prev));
    m.insert("code".into(), json!(code));
    m.insert("label".into(), json!(label));
    m.insert("icon".into(), json!(icon));
    m.insert("day".into(), json!(cur.get("is_day").and_then(|v| v.as_i64()).unwrap_or(1) != 0));
    m.insert("tmin".into(), tmin.map(round1).map(|v| json!(v)).unwrap_or(Value::Null));
    m.insert("tmax".into(), tmax.map(round1).map(|v| json!(v)).unwrap_or(Value::Null));
    m.insert("updated".into(), json!(now_secs()));
    Ok(m)
}

fn cache_path() -> PathBuf {
    core_dir().join("weather_cache.json")
}

fn style_path() -> PathBuf {
    core_dir().join("style_vars.json")
}

pub fn query_weather(city_opt: Option<&str>, force: bool) -> Value {
    let style = read_json_value(&style_path());
    let loc_lat = style.get("user_location_lat").and_then(|v| v.as_f64());
    let loc_lon = style.get("user_location_lon").and_then(|v| v.as_f64());
    let loc_ville = style.get("user_location_ville").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();

    let spec = if loc_lat.is_some() && loc_lon.is_some() {
        String::new()
    } else if let Some(c) = city_opt.filter(|s| !s.trim().is_empty()) {
        c.trim().to_string()
    } else {
        style.get("weather_city").and_then(|v| v.as_str()).unwrap_or("").trim().to_string()
    };

    let key = if let (Some(la), Some(lo)) = (loc_lat, loc_lon) {
        format!("loc:{la:.4},{lo:.4}")
    } else if !spec.is_empty() {
        spec.to_ascii_lowercase()
    } else {
        "__auto__".to_string()
    };

    let cache = read_json_value(&cache_path());
    let same = cache.get("spec").and_then(|v| v.as_str()) == Some(key.as_str())
        && cache.get("lat").and_then(|v| v.as_f64()).is_some();
    let fetched = cache.get("fetched").and_then(|v| v.as_u64()).unwrap_or(0);
    let fresh = same && now_secs().saturating_sub(fetched) < TTL_SECS;

    if fresh && !force {
        if let Some(mut data) = cache.get("data").and_then(|v| v.as_object()).cloned() {
            data.insert("ok".into(), json!(true));
            data.insert("city".into(), json!(cache.get("label").and_then(|v| v.as_str()).unwrap_or("—")));
            data.insert("source".into(), json!(cache.get("source").and_then(|v| v.as_str()).unwrap_or("ip")));
            data.insert("cached".into(), json!(true));
            return Value::Object(data);
        }
    }

    let resolved: Result<(f64, f64, String, &str), String> = if same {
        Ok((
            cache.get("lat").and_then(|v| v.as_f64()).unwrap(),
            cache.get("lon").and_then(|v| v.as_f64()).unwrap(),
            cache.get("label").and_then(|v| v.as_str()).unwrap_or("—").to_string(),
            if loc_lat.is_some() { "location" } else if !spec.is_empty() { "city" } else { "ip" },
        ))
    } else if let (Some(la), Some(lo)) = (loc_lat, loc_lon) {
        Ok((la, lo, if loc_ville.is_empty() { "Localisation réglée".into() } else { loc_ville }, "location"))
    } else if !spec.is_empty() {
        geocode_city(&spec).map(|g| {
            let la = g.get("lat").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let lo = g.get("lon").and_then(|v| v.as_f64()).unwrap_or(0.0);
            let v = g.get("ville").and_then(|v| v.as_str()).unwrap_or("—").to_string();
            (la, lo, v, "city")
        })
    } else {
        ip_locate().map(|(la, lo, c)| (la, lo, c, "ip"))
    };

    match resolved.and_then(|(la, lo, lbl, src)| {
        let mut data = fetch_forecast(la, lo)?;
        data.insert("city".into(), json!(lbl));
        data.insert("source".into(), json!(src));
        data.insert("cached".into(), json!(false));
        let _ = write_json_atomic(
            &cache_path(),
            &json!({
                "spec": key,
                "label": lbl,
                "lat": la,
                "lon": lo,
                "source": src,
                "fetched": now_secs(),
                "data": Value::Object(data.clone()),
            }),
            0o644,
        );
        Ok(Value::Object(data))
    }) {
        Ok(v) => v,
        Err(err) => {
            if let Some(mut stale) = cache.get("data").and_then(|v| v.as_object()).cloned() {
                stale.insert("ok".into(), json!(true));
                stale.insert("city".into(), json!(cache.get("label").and_then(|v| v.as_str()).unwrap_or("—")));
                stale.insert("source".into(), json!(cache.get("source").and_then(|v| v.as_str()).unwrap_or("?")));
                stale.insert("cached".into(), json!(true));
                stale.insert("stale".into(), json!(true));
                Value::Object(stale)
            } else {
                json!({ "ok": false, "error": err, "city": if spec.is_empty() { "—" } else { &spec } })
            }
        }
    }
}

pub fn run_weather(args: &[String]) -> i32 {
    if let Some(pos) = args.iter().position(|a| a == "--geocode") {
        let req = args.get(pos + 1).map(|s| s.as_str()).unwrap_or("");
        let out = match geocode_city(req) {
            Ok(mut v) => {
                if let Value::Object(ref mut m) = v {
                    m.insert("ok".into(), json!(true));
                }
                v
            }
            Err(e) => json!({ "ok": false, "error": e }),
        };
        return sortir(&out);
    }
    let force = args.iter().any(|a| a == "--force");
    let city = args
        .iter()
        .position(|a| a == "--city")
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str());
    sortir(&query_weather(city, force))
}

pub fn run_meteo(args: &[String]) -> i32 {
    let opts = parse_options_arg(args);
    let city = opts.get("city").and_then(|v| v.as_str()).map(|s| s.trim()).filter(|s| !s.is_empty());
    let d = query_weather(city, false);
    if !d.get("ok").and_then(|v| v.as_bool()).unwrap_or(false) {
        return sortir(&json!({
            "ok": false,
            "applet": "meteo",
            "icone": "cloud",
            "error": d.get("error").and_then(|v| v.as_str()).unwrap_or("météo indisponible"),
            "compact": { "valeur": "—", "libelle": "météo", "alerte": false },
            "detail": {},
        }));
    }
    let temp = d.get("temp").and_then(|v| v.as_f64());
    let valeur = temp.map(|t| format!("{}°", t.round() as i64)).unwrap_or_else(|| "—".into());
    let lbl = d.get("label").and_then(|v| v.as_str()).unwrap_or("");
    let c_name = d.get("city").and_then(|v| v.as_str()).unwrap_or("");
    let libelle = format!("{lbl} · {c_name}").trim_matches(|c| c == ' ' || c == '·').to_string();
    let ico_raw = d.get("icon").and_then(|v| v.as_str()).unwrap_or("").to_ascii_lowercase();
    let day = d.get("day").and_then(|v| v.as_bool()).unwrap_or(true);
    let icone = match ico_raw.as_str() {
        "sun" | "clear" => "sun",
        "moon" | "night" => "weather-night",
        "cloud" | "overcast" => "cloud",
        "fog" | "rain" | "drizzle" | "snow" | "storm" => "weather-cloud",
        _ => if !day { "weather-night" } else { "cloud" },
    };
    sortir(&json!({
        "ok": true,
        "applet": "meteo",
        "icone": icone,
        "alerte": false,
        "compact": { "valeur": valeur, "libelle": libelle, "alerte": false },
        "detail": {
            "temp": d.get("temp"),
            "feels": d.get("feels"),
            "tmin": d.get("tmin"),
            "tmax": d.get("tmax"),
            "label": d.get("label"),
            "city": d.get("city"),
            "day": d.get("day"),
            "code": d.get("code"),
            "source": d.get("source"),
            "updated": d.get("updated"),
            "cached": d.get("cached").and_then(|v| v.as_bool()).unwrap_or(false),
        },
    }))
}
