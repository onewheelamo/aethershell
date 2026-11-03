import calendar
import datetime
import json
import os
import re
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo
try:
    import requests
    from requests.auth import HTTPBasicAuth
    REQUESTS_AVAILABLE = True
except ImportError:
    requests = None
    HTTPBasicAuth = None
    REQUESTS_AVAILABLE = False

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from runtime_paths import runtime_path  # noqa: E402

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SECRETS_FILE = os.path.join(BASE_DIR, "secrets.json")

def _get_nc_cache_path():
    # Prefer persistent ~/.cache/quickshell to survive reboots, fallback to runtime_path
    p = os.path.expanduser("~/.cache/quickshell/nextcloud_calendar_cache.json")
    try:
        os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
        return p
    except Exception:
        return runtime_path("nextcloud_cache.json")

NC_CACHE_FILE = _get_nc_cache_path()
WEATHER_CACHE_FILE = runtime_path("weather_cache.json")
CACHE_TTL_SECONDS = 7200  # 2 hours (stale-while-revalidate)


def _write_private_json(path, data):
    """Write JSON readable only by the current user (caches hold calendar / location data)."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f)


def load_secrets():
    if not os.path.exists(SECRETS_FILE):
        return {}
    with open(SECRETS_FILE, "r") as f:
        return json.load(f)


def _unfold_ics(ics_text):
    """Unfold RFC 5545 folded lines (CRLF or LF followed by space/tab)."""
    return re.sub(r"\r?\n[ \t]", "", ics_text)


def _parse_ics_datetime(raw_val, params=""):
    """
    Parse DTSTART/DTEND value from ICS into (date_str 'YYYY-MM-DD', time_str 'HH:MM' or None),
    expressed in the LOCAL timezone: UTC values ('...Z') and TZID=... values are converted,
    floating times are kept as is. All-day values (YYYYMMDD) have no time.
    """
    val = raw_val.strip()
    m_dt = re.match(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z?)$", val)
    if m_dt:
        y, mo, d, hh, mm, ss, z = m_dt.groups()
        try:
            dt = datetime.datetime(int(y), int(mo), int(d), int(hh), int(mm), int(ss or 0))
            if z:
                dt = dt.replace(tzinfo=datetime.timezone.utc).astimezone()
            else:
                m_tz = re.search(r"TZID=([^;:]+)", params, flags=re.IGNORECASE)
                if m_tz:
                    try:
                        dt = dt.replace(tzinfo=ZoneInfo(m_tz.group(1).strip('"'))).astimezone()
                    except Exception:
                        pass  # unknown TZID: keep floating time
            return dt.strftime("%Y-%m-%d"), dt.strftime("%H:%M")
        except ValueError:
            return None, None
    m_d = re.match(r"^(\d{4})(\d{2})(\d{2})$", val)
    if m_d:
        y, mo, d = m_d.groups()
        return f"{y}-{mo}-{d}", None
    return None, None


def _unescape_ics_text(txt):
    return (
        txt.replace("\\n", " ")
        .replace("\\N", " ")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
        .strip()
    )


def parse_ics_events(ics_text):
    """Extract VEVENT blocks from raw ICS text and return a list of event dicts."""
    unfolded = _unfold_ics(ics_text)
    events = []
    blocks = re.findall(r"BEGIN:VEVENT(.*?)END:VEVENT", unfolded, flags=re.DOTALL)
    for block in blocks:
        summary = "Événement sans titre"
        location = ""
        description = ""
        dtstart_raw = ""
        dtend_raw = ""
        dtstart_params = ""
        dtend_params = ""

        for line in block.splitlines():
            line = line.strip()
            if not line or ":" not in line:
                continue
            prop, val = line.split(":", 1)
            prop_name = prop.split(";", 1)[0].upper()
            if prop_name == "SUMMARY":
                summary = _unescape_ics_text(val)
            elif prop_name == "LOCATION":
                location = _unescape_ics_text(val)
            elif prop_name == "DESCRIPTION":
                description = _unescape_ics_text(val)
            elif prop_name == "DTSTART":
                dtstart_raw = val
                dtstart_params = prop
            elif prop_name == "DTEND":
                dtend_raw = val
                dtend_params = prop

        start_date, start_time = _parse_ics_datetime(dtstart_raw, dtstart_params)
        end_date, end_time = _parse_ics_datetime(dtend_raw, dtend_params)
        if not start_date:
            continue

        if start_time and end_time:
            time_label = f"{start_time} - {end_time}"
        elif start_time:
            time_label = start_time
        else:
            time_label = "Toute la journée"

        # Expand multi-day events across each day in range
        dates = [start_date]
        if end_date and end_date > start_date:
            try:
                d0 = datetime.date.fromisoformat(start_date)
                d1 = datetime.date.fromisoformat(end_date)
                # For all-day events in ICS, DTEND is exclusive
                if start_time is None:
                    d1 = d1 - datetime.timedelta(days=1)
                cur = d0 + datetime.timedelta(days=1)
                while cur <= d1 and (cur - d0).days <= 31:
                    dates.append(cur.isoformat())
                    cur += datetime.timedelta(days=1)
            except Exception:
                pass

        for d_str in dates:
            events.append(
                {
                    "date": d_str,
                    "summary": summary,
                    "time": time_label,
                    "sort_key": start_time or "00:00",
                    "location": location,
                    "description": description,
                    "all_day": start_time is None,
                }
            )
    return events


def discover_calendars(base_url, user, auth):
    """Discover all CalDAV calendar URLs for the Nextcloud user via PROPFIND."""
    home_path = f"/remote.php/dav/calendars/{user}/"
    url = base_url.rstrip("/") + home_path
    propfind_body = """<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:resourcetype />
    <d:displayname />
  </d:prop>
</d:propfind>"""
    try:
        resp = requests.request(
            "PROPFIND",
            url,
            auth=auth,
            headers={"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
            data=propfind_body.encode("utf-8"),
            timeout=6,
        )
        if resp.status_code not in (200, 207):
            return [url + "personal/"]

        root = ET.fromstring(resp.text)
        cal_urls = []
        for response in root.findall("{DAV:}response"):
            href_el = response.find("{DAV:}href")
            if href_el is None or not href_el.text:
                continue
            href = href_el.text
            if href.rstrip("/") == home_path.rstrip("/"):
                continue
            res_types = response.findall(".//{urn:ietf:params:xml:ns:caldav}calendar")
            if res_types and "inbox" not in href and "outbox" not in href and "trashbin" not in href:
                if href.startswith("http"):
                    cal_urls.append(href)
                else:
                    cal_urls.append(base_url.rstrip("/") + href)
        return cal_urls or [url + "personal/"]
    except Exception:
        return [url + "personal/"]


def get_month_range(year, month, count_forward=5, count_backward=1):
    """Return list of (year, month) tuples from -count_backward to +count_forward."""
    months = []
    for i in range(count_backward, 0, -1):
        m = month - i
        y = year
        while m < 1:
            m += 12
            y -= 1
        months.append((y, m))
    months.append((year, month))
    for i in range(1, count_forward + 1):
        m = month + i
        y = year
        while m > 12:
            m -= 12
            y += 1
        months.append((y, m))
    return months


def get_month_events(year=None, month=None, force_refresh=False):
    """
    Fetch Nextcloud calendar events for a given (year, month).
    Pre-caches the previous month, current month, and the 5 following months (7 months total).
    Returns:
      {
        "status": "ok" | "error" | "offline" | "cached",
        "year": int,
        "month": int,
        "days": { "YYYY-MM-DD": [ { "summary", "time", "location", "all_day" }, ... ] },
        "months": { "YYYY-MM": { "YYYY-MM-DD": [...] } }
      }
    """
    now = datetime.date.today()
    year = int(year or now.year)
    month = int(month or now.month)
    cache_key = f"{year:04d}-{month:02d}"

    # Load persistent disk cache
    cache_data = {}
    if os.path.exists(NC_CACHE_FILE):
        try:
            with open(NC_CACHE_FILE, "r") as f:
                cache_data = json.load(f)
        except Exception:
            cache_data = {}

    cached_entry = cache_data.get(cache_key)

    # Collect all existing cached months to deliver to client
    all_months = {}
    for k, v in cache_data.items():
        if isinstance(v, dict) and "payload" in v and isinstance(v["payload"], dict):
            all_months[k] = v["payload"].get("days", {})

    # Check cache freshness (2 hours TTL)
    if (
        not force_refresh
        and cached_entry
        and (time.time() - cached_entry.get("timestamp", 0) < CACHE_TTL_SECONDS)
    ):
        payload = dict(cached_entry["payload"])
        payload["months"] = all_months
        return payload

    if not REQUESTS_AVAILABLE:
        if cached_entry and "payload" in cached_entry:
            fallback = dict(cached_entry["payload"])
            fallback["status"] = "cached"
            fallback["months"] = all_months
            return fallback
        return {
            "status": "error",
            "message": "Module python 'requests' manquant (installez python-requests ou python3-requests)",
            "year": year,
            "month": month,
            "days": {},
            "months": all_months,
        }

    secrets = load_secrets().get("nextcloud", {})
    base_url = secrets.get("url", "").rstrip("/")
    user = secrets.get("user", "")
    app_password = secrets.get("app_password", "")

    if not base_url or not user or not app_password:
        if cached_entry and "payload" in cached_entry:
            fallback = dict(cached_entry["payload"])
            fallback["status"] = "cached"
            fallback["months"] = all_months
            return fallback
        return {
            "status": "error",
            "message": "Identifiants Nextcloud manquants dans core/secrets.json",
            "year": year,
            "month": month,
            "days": {},
            "months": all_months,
        }

    auth = HTTPBasicAuth(user, app_password)

    # Pre-fetch a 7-month window: previous month, current month, and next 5 months in a single query
    months_window = get_month_range(year, month, count_forward=5, count_backward=1)
    start_y, start_m = months_window[0]
    end_y, end_m = months_window[-1]
    _, last_day = calendar.monthrange(end_y, end_m)
    start_str = f"{start_y:04d}{start_m:02d}01T000000Z"
    end_str = f"{end_y:04d}{end_m:02d}{last_day:02d}T235959Z"

    report_body = f"""<?xml version="1.0" encoding="utf-8" ?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag />
    <c:calendar-data>
      <c:expand start="{start_str}" end="{end_str}"/>
    </c:calendar-data>
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="{start_str}" end="{end_str}"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>"""

    try:
        cal_urls = discover_calendars(base_url, user, auth)
        days_map = {}
        failed_calendars = 0

        for cal_url in cal_urls:
            resp = requests.request(
                "REPORT",
                cal_url,
                auth=auth,
                headers={"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
                data=report_body.encode("utf-8"),
                timeout=7,
            )
            if resp.status_code in (401, 403):
                if cached_entry and "payload" in cached_entry:
                    fallback = dict(cached_entry["payload"])
                    fallback["status"] = "cached"
                    fallback["months"] = all_months
                    return fallback
                return {
                    "status": "error",
                    "message": "Authentification Nextcloud refusée (vérifier core/secrets.json)",
                    "year": year,
                    "month": month,
                    "days": {},
                    "months": all_months,
                }
            if resp.status_code not in (200, 207):
                failed_calendars += 1
                continue

            root = ET.fromstring(resp.text)
            for cal_data_el in root.findall(".//{urn:ietf:params:xml:ns:caldav}calendar-data"):
                if cal_data_el.text:
                    for ev in parse_ics_events(cal_data_el.text):
                        d_key = ev["date"]
                        days_map.setdefault(d_key, [])
                        # Avoid duplicates across calendars
                        if not any(
                            x["summary"] == ev["summary"] and x["time"] == ev["time"]
                            for x in days_map[d_key]
                        ):
                            days_map[d_key].append(ev)

        if failed_calendars and failed_calendars == len(cal_urls):
            raise RuntimeError("Aucun calendrier Nextcloud n'a répondu correctement")

        for d_key in days_map:
            days_map[d_key].sort(key=lambda x: x.get("sort_key", "00:00"))

        now_ts = time.time()
        # Partition all retrieved events into respective month caches
        for y_win, m_win in months_window:
            m_k = f"{y_win:04d}-{m_win:02d}"
            m_days = {d: evs for d, evs in days_map.items() if d.startswith(m_k)}
            m_payload = {
                "status": "ok",
                "year": y_win,
                "month": m_win,
                "days": m_days,
            }
            cache_data[m_k] = {"timestamp": now_ts, "payload": m_payload}
            all_months[m_k] = m_days

        try:
            _write_private_json(NC_CACHE_FILE, cache_data)
        except Exception:
            pass

        target_payload = dict(cache_data.get(cache_key, {}).get("payload", {
            "status": "ok",
            "year": year,
            "month": month,
            "days": {d: evs for d, evs in days_map.items() if d.startswith(cache_key)},
        }))
        target_payload["months"] = all_months
        return target_payload

    except Exception as e:
        if cached_entry and "payload" in cached_entry:
            fallback = dict(cached_entry["payload"])
            fallback["status"] = "cached"
            fallback["months"] = all_months
            return fallback
        return {
            "status": "offline",
            "message": str(e),
            "year": year,
            "month": month,
            "days": {},
            "months": all_months,
        }


def get_weather():
    """Fetch brief local weather & location for the central island hover panel."""
    if os.path.exists(WEATHER_CACHE_FILE):
        try:
            with open(WEATHER_CACHE_FILE, "r") as f:
                cached = json.load(f)
            if time.time() - cached.get("timestamp", 0) < 1800:
                return cached["data"]
        except Exception:
            pass

    if not REQUESTS_AVAILABLE:
        return {
            "location": "Météo",
            "temp": "--°C",
            "desc": "Module requests manquant",
            "icon": "⚠️",
        }

    try:
        resp = requests.get("https://wttr.in/?format=j1&lang=fr", timeout=4)
        if resp.status_code == 200:
            j = resp.json()
            cur = (j.get("current_condition") or [{}])[0]
            area = (j.get("nearest_area") or [{}])[0]
            city = ((area.get("areaName") or [{}])[0]).get("value", "Paris")
            country = ((area.get("country") or [{}])[0]).get("value", "FR")
            temp_c = cur.get("temp_C", "18")
            lang_fr = cur.get("lang_fr") or cur.get("weatherDesc") or [{"value": "Clair"}]
            desc = lang_fr[0].get("value", "Clair")
            code = int(cur.get("weatherCode", 113))
            icon = "☀️"
            if code in (116,):
                icon = "⛅"
            elif code in (119, 122, 143, 248, 260):
                icon = "☁️"
            elif code in (176, 263, 266, 293, 296, 299, 302, 305, 308, 353, 356, 359):
                icon = "🌧️"
            elif code in (200, 386, 389, 392, 395):
                icon = "⛈️"
            elif code in (179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371):
                icon = "❄️"

            data = {
                "location": f"{city}, {country}",
                "temp": f"{temp_c}°C",
                "desc": desc,
                "icon": icon,
            }
            try:
                _write_private_json(WEATHER_CACHE_FILE, {"timestamp": time.time(), "data": data})
            except Exception:
                pass
            return data
    except Exception:
        pass

    return {
        "location": "France",
        "temp": "--°C",
        "desc": "Indisponible",
        "icon": "⛅",
    }


def _escape_ics_text(txt):
    return (
        (txt or "")
        .replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\r\n", "\\n")
        .replace("\n", "\\n")
        .strip()
    )


def _parse_hhmm(time_str):
    if not time_str or not time_str.strip():
        return None
    s = time_str.strip().lower().replace("h", ":")
    m = re.match(r"^(\d{1,2})(?::(\d{1,2}))?$", s)
    if not m:
        return None
    hh = int(m.group(1))
    mm = int(m.group(2) or 0)
    if 0 <= hh <= 23 and 0 <= mm <= 59:
        return hh, mm
    return None


def add_calendar_event(date_str, summary, start_time="", end_time="", location=""):
    """
    Create a new VEVENT on the primary Nextcloud CalDAV calendar via HTTP PUT.
    date_str: 'YYYY-MM-DD'
    summary: Event title
    start_time: Optional 'HH:MM' (empty -> all-day event)
    end_time: Optional 'HH:MM' (defaults to start_time + 1 hour if start_time is set)
    location: Optional location string
    """
    summary = (summary or "").strip()
    if not summary:
        return {"success": False, "message": "Le titre de l'événement est requis"}

    try:
        ev_date = datetime.date.fromisoformat(date_str.strip())
    except Exception:
        return {"success": False, "message": f"Date invalide : {date_str}"}

    if not REQUESTS_AVAILABLE:
        return {
            "success": False,
            "message": "Module python 'requests' manquant",
        }

    secrets = load_secrets().get("nextcloud", {})
    base_url = secrets.get("url", "").rstrip("/")
    user = secrets.get("user", "")
    app_password = secrets.get("app_password", "")

    if not base_url or not user or not app_password:
        return {
            "success": False,
            "message": "Identifiants Nextcloud manquants dans core/secrets.json",
        }

    st_parsed = _parse_hhmm(start_time)
    if start_time and start_time.strip() and st_parsed is None:
        return {"success": False, "message": "Format heure début invalide (attendu HH:MM)"}

    et_parsed = _parse_hhmm(end_time)
    if end_time and end_time.strip() and et_parsed is None:
        return {"success": False, "message": "Format heure fin invalide (attendu HH:MM)"}

    local_tz = datetime.datetime.now().astimezone().tzinfo
    now_utc = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    uid = str(uuid.uuid4())

    if st_parsed is not None:
        sh, sm = st_parsed
        dt_start_local = datetime.datetime(
            ev_date.year, ev_date.month, ev_date.day, sh, sm, 0, tzinfo=local_tz
        )
        if et_parsed is not None:
            eh, em = et_parsed
            dt_end_local = datetime.datetime(
                ev_date.year, ev_date.month, ev_date.day, eh, em, 0, tzinfo=local_tz
            )
            if dt_end_local <= dt_start_local:
                dt_end_local += datetime.timedelta(days=1)
        else:
            dt_end_local = dt_start_local + datetime.timedelta(hours=1)

        dtstart_line = "DTSTART:" + dt_start_local.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        dtend_line = "DTEND:" + dt_end_local.astimezone(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    else:
        next_day = ev_date + datetime.timedelta(days=1)
        dtstart_line = f"DTSTART;VALUE=DATE:{ev_date.strftime('%Y%m%d')}"
        dtend_line = f"DTEND;VALUE=DATE:{next_day.strftime('%Y%m%d')}"

    ics_lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Portable-Station Quickshell//CalDAV Client//FR",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{now_utc}",
        dtstart_line,
        dtend_line,
        f"SUMMARY:{_escape_ics_text(summary)}",
    ]
    if location and location.strip():
        ics_lines.append(f"LOCATION:{_escape_ics_text(location)}")
    ics_lines.extend(["END:VEVENT", "END:VCALENDAR", ""])
    ics_body = "\r\n".join(ics_lines)

    auth = HTTPBasicAuth(user, app_password)
    try:
        cal_urls = discover_calendars(base_url, user, auth)
        if not cal_urls:
            return {"success": False, "message": "Aucun calendrier trouvé sur le compte Nextcloud"}
        # Prefer 'personal' calendar if present, otherwise first writable calendar
        target_cal = cal_urls[0]
        for u in cal_urls:
            if "/personal" in u.lower():
                target_cal = u
                break

        put_url = target_cal.rstrip("/") + f"/{uid}.ics"
        resp = requests.put(
            put_url,
            auth=auth,
            headers={
                "Content-Type": "text/calendar; charset=utf-8",
                "If-None-Match": "*",
            },
            data=ics_body.encode("utf-8"),
            timeout=8,
        )
        if resp.status_code in (200, 201, 204):
            # Invalidate month cache so subsequent fetch gets the new event
            cache_key = f"{ev_date.year:04d}-{ev_date.month:02d}"
            if os.path.exists(NC_CACHE_FILE):
                try:
                    with open(NC_CACHE_FILE, "r") as f:
                        cache_data = json.load(f)
                    if cache_key in cache_data:
                        del cache_data[cache_key]
                        _write_private_json(NC_CACHE_FILE, cache_data)
                except Exception:
                    pass
            return {"success": True, "uid": uid, "date": date_str, "message": "Événement ajouté"}
        if resp.status_code in (401, 403):
            return {"success": False, "message": "Authentification Nextcloud refusée"}
        return {"success": False, "message": f"Erreur CalDAV HTTP {resp.status_code}"}
    except Exception as e:
        return {"success": False, "message": f"Erreur réseau : {e}"}


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "month"
    if action == "weather":
        print(json.dumps(get_weather()))
    elif action == "month":
        y = int(sys.argv[2]) if len(sys.argv) > 2 else None
        m = int(sys.argv[3]) if len(sys.argv) > 3 else None
        force = "--force" in sys.argv
        print(json.dumps(get_month_events(y, m, force_refresh=force)))
    elif action == "add":
        d_arg = sys.argv[2] if len(sys.argv) > 2 else ""
        s_arg = sys.argv[3] if len(sys.argv) > 3 else ""
        st_arg = sys.argv[4] if len(sys.argv) > 4 else ""
        et_arg = sys.argv[5] if len(sys.argv) > 5 else ""
        loc_arg = sys.argv[6] if len(sys.argv) > 6 else ""
        print(json.dumps(add_calendar_event(d_arg, s_arg, st_arg, et_arg, loc_arg)))
    else:
        print(json.dumps(get_month_events()))
