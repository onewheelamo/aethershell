use crate::common::io::{read_json_value, write_private_json};
use crate::common::paths::{cache_dir, core_dir, runtime_dir};
use regex::Regex;
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const CACHE_TTL_SECONDS: f64 = 7200.0;

fn now_f64() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

fn nc_cache_file() -> PathBuf {
    let dir = cache_dir().join("quickshell");
    if fs::create_dir_all(&dir).is_ok() {
        dir.join("nextcloud_calendar_cache.json")
    } else {
        runtime_dir().join("nextcloud_cache.json")
    }
}

fn weather_cache_file() -> PathBuf {
    runtime_dir().join("weather_cache.json")
}

fn base64_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(((input.len() + 2) / 3) * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((n >> 18) & 63) as usize] as char);
        out.push(TABLE[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[((n >> 6) & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

fn basic_auth_header(user: &str, pass: &str) -> String {
    let raw = format!("{}:{}", user, pass);
    format!("Basic {}", base64_encode(raw.as_bytes()))
}

fn uuid_v4() -> String {
    let mut b = [0u8; 16];
    if let Ok(bytes) = fs::read("/dev/urandom").map(|v| v) {
        if bytes.len() >= 16 {
            b.copy_from_slice(&bytes[..16]);
        }
    } else {
        let t = (now_f64() * 1_000_000.0) as u128;
        b.copy_from_slice(&t.to_le_bytes());
    }
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]
    )
}

fn is_leap(y: i32) -> bool {
    (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
}

fn days_in_month(y: i32, m: i32) -> i32 {
    match m {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap(y) {
                29
            } else {
                28
            }
        }
        _ => 30,
    }
}

fn add_days_ymd(mut y: i32, mut m: i32, mut d: i32, delta: i32) -> (i32, i32, i32) {
    d += delta;
    while d > days_in_month(y, m) {
        d -= days_in_month(y, m);
        m += 1;
        if m > 12 {
            m = 1;
            y += 1;
        }
    }
    while d < 1 {
        m -= 1;
        if m < 1 {
            m = 12;
            y -= 1;
        }
        d += days_in_month(y, m);
    }
    (y, m, d)
}

fn parse_ymd(s: &str) -> Option<(i32, i32, i32)> {
    let parts: Vec<&str> = s.trim().split('-').collect();
    if parts.len() != 3 {
        return None;
    }
    let y = parts[0].parse::<i32>().ok()?;
    let m = parts[1].parse::<i32>().ok()?;
    let d = parts[2].parse::<i32>().ok()?;
    if !(1..=12).contains(&m) || !(1..=days_in_month(y, m)).contains(&d) {
        return None;
    }
    Some((y, m, d))
}

fn today_local_ym() -> (i32, i32) {
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        (tm.tm_year + 1900, tm.tm_mon + 1)
    }
}

fn utc_to_local_dt(y: i32, mo: i32, d: i32, hh: i32, mm: i32, ss: i32) -> (String, String) {
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        tm.tm_year = y - 1900;
        tm.tm_mon = mo - 1;
        tm.tm_mday = d;
        tm.tm_hour = hh;
        tm.tm_min = mm;
        tm.tm_sec = ss;
        let epoch = libc::timegm(&mut tm);
        let mut local_tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&epoch, &mut local_tm);
        (
            format!(
                "{:04}-{:02}-{:02}",
                local_tm.tm_year + 1900,
                local_tm.tm_mon + 1,
                local_tm.tm_mday
            ),
            format!("{:02}:{:02}", local_tm.tm_hour, local_tm.tm_min),
        )
    }
}

fn local_to_utc_stamp(y: i32, mo: i32, d: i32, hh: i32, mm: i32, ss: i32) -> String {
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        tm.tm_year = y - 1900;
        tm.tm_mon = mo - 1;
        tm.tm_mday = d;
        tm.tm_hour = hh;
        tm.tm_min = mm;
        tm.tm_sec = ss;
        tm.tm_isdst = -1;
        let epoch = libc::mktime(&mut tm);
        let mut utc_tm: libc::tm = std::mem::zeroed();
        libc::gmtime_r(&epoch, &mut utc_tm);
        format!(
            "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
            utc_tm.tm_year + 1900,
            utc_tm.tm_mon + 1,
            utc_tm.tm_mday,
            utc_tm.tm_hour,
            utc_tm.tm_min,
            utc_tm.tm_sec
        )
    }
}

fn now_utc_stamp() -> String {
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut utc_tm: libc::tm = std::mem::zeroed();
        libc::gmtime_r(&now, &mut utc_tm);
        format!(
            "{:04}{:02}{:02}T{:02}{:02}{:02}Z",
            utc_tm.tm_year + 1900,
            utc_tm.tm_mon + 1,
            utc_tm.tm_mday,
            utc_tm.tm_hour,
            utc_tm.tm_min,
            utc_tm.tm_sec
        )
    }
}

fn xml_unescape(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

fn unfold_ics(ics_text: &str) -> String {
    let re = Regex::new(r"\r?\n[ \t]").unwrap();
    re.replace_all(ics_text, "").to_string()
}

fn unescape_ics_text(txt: &str) -> String {
    txt.replace("\\n", " ")
        .replace("\\N", " ")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
        .trim()
        .to_string()
}

fn escape_ics_text(txt: &str) -> String {
    txt.replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace("\r\n", "\\n")
        .replace('\n', "\\n")
        .trim()
        .to_string()
}

fn parse_ics_datetime(raw_val: &str, _params: &str) -> (Option<String>, Option<String>) {
    let val = raw_val.trim();
    let re_dt = Regex::new(r"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z?)$").unwrap();
    if let Some(cap) = re_dt.captures(val) {
        let y: i32 = cap[1].parse().unwrap_or(0);
        let mo: i32 = cap[2].parse().unwrap_or(0);
        let d: i32 = cap[3].parse().unwrap_or(0);
        let hh: i32 = cap[4].parse().unwrap_or(0);
        let mm: i32 = cap[5].parse().unwrap_or(0);
        let ss: i32 = cap.get(6).and_then(|m| m.as_str().parse().ok()).unwrap_or(0);
        let is_z = cap.get(7).map(|m| m.as_str() == "Z").unwrap_or(false);
        if is_z {
            let (ds, ts) = utc_to_local_dt(y, mo, d, hh, mm, ss);
            return (Some(ds), Some(ts));
        }
        return (
            Some(format!("{:04}-{:02}-{:02}", y, mo, d)),
            Some(format!("{:02}:{:02}", hh, mm)),
        );
    }
    let re_d = Regex::new(r"^(\d{4})(\d{2})(\d{2})$").unwrap();
    if let Some(cap) = re_d.captures(val) {
        return (
            Some(format!("{}-{}-{}", &cap[1], &cap[2], &cap[3])),
            None,
        );
    }
    (None, None)
}

fn parse_ics_events(ics_text: &str) -> Vec<Value> {
    let unfolded = unfold_ics(ics_text);
    let block_re = Regex::new(r"(?s)BEGIN:VEVENT(.*?)END:VEVENT").unwrap();
    let mut events = Vec::new();

    for cap in block_re.captures_iter(&unfolded) {
        let block = &cap[1];
        let mut summary = "Événement sans titre".to_string();
        let mut location = String::new();
        let mut description = String::new();
        let mut dtstart_raw = String::new();
        let mut dtend_raw = String::new();
        let mut dtstart_params = String::new();
        let mut dtend_params = String::new();

        for line in block.lines() {
            let l = line.trim();
            if l.is_empty() {
                continue;
            }
            let Some((prop, val)) = l.split_once(':') else {
                continue;
            };
            let prop_name = prop.split(';').next().unwrap_or("").to_ascii_uppercase();
            match prop_name.as_str() {
                "SUMMARY" => summary = unescape_ics_text(val),
                "LOCATION" => location = unescape_ics_text(val),
                "DESCRIPTION" => description = unescape_ics_text(val),
                "DTSTART" => {
                    dtstart_raw = val.to_string();
                    dtstart_params = prop.to_string();
                }
                "DTEND" => {
                    dtend_raw = val.to_string();
                    dtend_params = prop.to_string();
                }
                _ => {}
            }
        }

        let (Some(start_date), start_time) = parse_ics_datetime(&dtstart_raw, &dtstart_params)
        else {
            continue;
        };
        let (end_date, end_time) = parse_ics_datetime(&dtend_raw, &dtend_params);

        let time_label = match (&start_time, &end_time) {
            (Some(st), Some(et)) => format!("{} - {}", st, et),
            (Some(st), None) => st.clone(),
            _ => "Toute la journée".to_string(),
        };

        let mut dates = vec![start_date.clone()];
        if let Some(ed) = &end_date {
            if ed > &start_date {
                if let (Some((y0, m0, d0)), Some((mut y1, mut m1, mut d1))) =
                    (parse_ymd(&start_date), parse_ymd(ed))
                {
                    if start_time.is_none() {
                        (y1, m1, d1) = add_days_ymd(y1, m1, d1, -1);
                    }
                    let end_cmp = format!("{:04}-{:02}-{:02}", y1, m1, d1);
                    let mut cur = add_days_ymd(y0, m0, d0, 1);
                    for _ in 0..31 {
                        let cur_s = format!("{:04}-{:02}-{:02}", cur.0, cur.1, cur.2);
                        if cur_s > end_cmp {
                            break;
                        }
                        dates.push(cur_s);
                        cur = add_days_ymd(cur.0, cur.1, cur.2, 1);
                    }
                }
            }
        }

        let sort_key = start_time.as_deref().unwrap_or("00:00");
        let all_day = start_time.is_none();
        for d_str in dates {
            events.push(json!({
                "date": d_str,
                "summary": summary,
                "time": time_label,
                "sort_key": sort_key,
                "location": location,
                "description": description,
                "all_day": all_day,
            }));
        }
    }
    events
}

fn discover_calendars(base_url: &str, user: &str, auth_hdr: &str) -> Vec<String> {
    let home_path = format!("/remote.php/dav/calendars/{}/", user);
    let url = format!("{}{}", base_url.trim_end_matches('/'), home_path);
    let propfind_body = r#"<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:resourcetype />
    <d:displayname />
  </d:prop>
</d:propfind>"#;

    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(6))
        .build();
    let Ok(resp) = agent
        .request("PROPFIND", &url)
        .set("Authorization", auth_hdr)
        .set("Depth", "1")
        .set("Content-Type", "application/xml; charset=utf-8")
        .send_string(propfind_body)
    else {
        return vec![format!("{}personal/", url)];
    };
    if !matches!(resp.status(), 200 | 207) {
        return vec![format!("{}personal/", url)];
    }
    let body = resp.into_string().unwrap_or_default();

    let resp_re =
        Regex::new(r"(?s)<(?:[a-zA-Z0-9_-]+:)?response\b[^>]*>(.*?)</(?:[a-zA-Z0-9_-]+:)?response>")
            .unwrap();
    let href_re =
        Regex::new(r"(?s)<(?:[a-zA-Z0-9_-]+:)?href\b[^>]*>(.*?)</(?:[a-zA-Z0-9_-]+:)?href>")
            .unwrap();
    let cal_re = Regex::new(r"<(?:[a-zA-Z0-9_-]+:)?calendar\b").unwrap();

    let mut cal_urls = Vec::new();
    for cap in resp_re.captures_iter(&body) {
        let block = &cap[1];
        let Some(hcap) = href_re.captures(block) else {
            continue;
        };
        let href = xml_unescape(hcap[1].trim());
        if href.trim_end_matches('/') == home_path.trim_end_matches('/') {
            continue;
        }
        if cal_re.is_match(block)
            && !href.contains("inbox")
            && !href.contains("outbox")
            && !href.contains("trashbin")
        {
            if href.starts_with("http") {
                cal_urls.push(href);
            } else {
                cal_urls.push(format!("{}{}", base_url.trim_end_matches('/'), href));
            }
        }
    }
    if cal_urls.is_empty() {
        vec![format!("{}personal/", url)]
    } else {
        cal_urls
    }
}

fn get_month_range(year: i32, month: i32) -> Vec<(i32, i32)> {
    let mut months = Vec::new();
    for i in (1..=1).rev() {
        let mut m = month - i;
        let mut y = year;
        while m < 1 {
            m += 12;
            y -= 1;
        }
        months.push((y, m));
    }
    months.push((year, month));
    for i in 1..=5 {
        let mut m = month + i;
        let mut y = year;
        while m > 12 {
            m -= 12;
            y += 1;
        }
        months.push((y, m));
    }
    months
}

fn get_month_events(year_in: Option<i32>, month_in: Option<i32>, force_refresh: bool) -> Value {
    let (def_y, def_m) = today_local_ym();
    let year = year_in.unwrap_or(def_y);
    let month = month_in.unwrap_or(def_m);
    let cache_key = format!("{:04}-{:02}", year, month);

    let nc_path = nc_cache_file();
    let mut cache_data = read_json_value(&nc_path)
        .as_object()
        .cloned()
        .unwrap_or_default();

    let cached_entry = cache_data.get(&cache_key).cloned();
    let mut all_months = Map::new();
    for (k, v) in &cache_data {
        if let Some(days) = v
            .get("payload")
            .and_then(|p| p.get("days"))
            .and_then(|d| d.as_object())
        {
            all_months.insert(k.clone(), Value::Object(days.clone()));
        }
    }

    if !force_refresh {
        if let Some(ce) = &cached_entry {
            let ts = ce.get("timestamp").and_then(|v| v.as_f64()).unwrap_or(0.0);
            if now_f64() - ts < CACHE_TTL_SECONDS {
                if let Some(mut payload) = ce.get("payload").and_then(|p| p.as_object()).cloned() {
                    payload.insert("months".into(), Value::Object(all_months));
                    return Value::Object(payload);
                }
            }
        }
    }

    let fallback_or = |err_payload: Value| -> Value {
        if let Some(ce) = &cached_entry {
            if let Some(mut payload) = ce.get("payload").and_then(|p| p.as_object()).cloned() {
                payload.insert("status".into(), json!("cached"));
                payload.insert("months".into(), Value::Object(all_months.clone()));
                return Value::Object(payload);
            }
        }
        err_payload
    };

    let secrets = read_json_value(&core_dir().join("secrets.json"));
    let nc = secrets.get("nextcloud").cloned().unwrap_or(Value::Null);
    let base_url = nc
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim_end_matches('/')
        .to_string();
    let user = nc
        .get("user")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let app_password = nc
        .get("app_password")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    if base_url.is_empty() || user.is_empty() || app_password.is_empty() {
        return fallback_or(json!({
            "status": "error",
            "message": "Identifiants Nextcloud manquants dans core/secrets.json",
            "year": year,
            "month": month,
            "days": {},
            "months": all_months,
        }));
    }

    let auth_hdr = basic_auth_header(&user, &app_password);
    let months_window = get_month_range(year, month);
    let (start_y, start_m) = months_window[0];
    let (end_y, end_m) = months_window[months_window.len() - 1];
    let last_day = days_in_month(end_y, end_m);
    let start_str = format!("{:04}{:02}01T000000Z", start_y, start_m);
    let end_str = format!("{:04}{:02}{:02}T235959Z", end_y, end_m, last_day);

    let report_body = format!(
        r#"<?xml version="1.0" encoding="utf-8" ?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag />
    <c:calendar-data>
      <c:expand start="{}" end="{}"/>
    </c:calendar-data>
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="{}" end="{}"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>"#,
        start_str, end_str, start_str, end_str
    );

    let cal_urls = discover_calendars(&base_url, &user, &auth_hdr);
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(7))
        .build();
    let cal_data_re = Regex::new(
        r"(?s)<(?:[a-zA-Z0-9_-]+:)?calendar-data\b[^>]*>(.*?)</(?:[a-zA-Z0-9_-]+:)?calendar-data>",
    )
    .unwrap();

    let mut days_map: HashMap<String, Vec<Value>> = HashMap::new();
    let mut failed_calendars = 0usize;

    for cal_url in &cal_urls {
        let resp = agent
            .request("REPORT", cal_url)
            .set("Authorization", &auth_hdr)
            .set("Depth", "1")
            .set("Content-Type", "application/xml; charset=utf-8")
            .send_string(&report_body);
        match resp {
            Ok(r) => {
                if !matches!(r.status(), 200 | 207) {
                    failed_calendars += 1;
                    continue;
                }
                let txt = r.into_string().unwrap_or_default();
                for cap in cal_data_re.captures_iter(&txt) {
                    let ics = xml_unescape(&cap[1]);
                    for ev in parse_ics_events(&ics) {
                        let d_key = ev
                            .get("date")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                            .to_string();
                        let sum = ev.get("summary").and_then(|v| v.as_str()).unwrap_or("");
                        let tm = ev.get("time").and_then(|v| v.as_str()).unwrap_or("");
                        let list = days_map.entry(d_key).or_default();
                        if !list.iter().any(|x| {
                            x.get("summary").and_then(|v| v.as_str()) == Some(sum)
                                && x.get("time").and_then(|v| v.as_str()) == Some(tm)
                        }) {
                            list.push(ev);
                        }
                    }
                }
            }
            Err(ureq::Error::Status(401 | 403, _)) => {
                return fallback_or(json!({
                    "status": "error",
                    "message": "Authentification Nextcloud refusée (vérifier core/secrets.json)",
                    "year": year,
                    "month": month,
                    "days": {},
                    "months": all_months,
                }));
            }
            Err(_) => {
                failed_calendars += 1;
            }
        }
    }

    if failed_calendars > 0 && failed_calendars == cal_urls.len() {
        return fallback_or(json!({
            "status": "offline",
            "message": "Aucun calendrier Nextcloud n'a répondu correctement",
            "year": year,
            "month": month,
            "days": {},
            "months": all_months,
        }));
    }

    for evs in days_map.values_mut() {
        evs.sort_by(|a, b| {
            let ka = a.get("sort_key").and_then(|v| v.as_str()).unwrap_or("00:00");
            let kb = b.get("sort_key").and_then(|v| v.as_str()).unwrap_or("00:00");
            ka.cmp(kb)
        });
    }

    let now_ts = now_f64();
    for (y_win, m_win) in months_window {
        let m_k = format!("{:04}-{:02}", y_win, m_win);
        let mut m_days = Map::new();
        for (d, evs) in &days_map {
            if d.starts_with(&m_k) {
                m_days.insert(d.clone(), Value::Array(evs.clone()));
            }
        }
        let m_payload = json!({
            "status": "ok",
            "year": y_win,
            "month": m_win,
            "days": Value::Object(m_days.clone()),
        });
        cache_data.insert(
            m_k.clone(),
            json!({ "timestamp": now_ts, "payload": m_payload }),
        );
        all_months.insert(m_k, Value::Object(m_days));
    }

    let _ = write_private_json(&nc_path, &Value::Object(cache_data.clone()));

    let mut target_payload = cache_data
        .get(&cache_key)
        .and_then(|v| v.get("payload"))
        .and_then(|p| p.as_object())
        .cloned()
        .unwrap_or_else(|| {
            let mut m_days = Map::new();
            for (d, evs) in &days_map {
                if d.starts_with(&cache_key) {
                    m_days.insert(d.clone(), Value::Array(evs.clone()));
                }
            }
            json!({
                "status": "ok",
                "year": year,
                "month": month,
                "days": Value::Object(m_days),
            })
            .as_object()
            .unwrap()
            .clone()
        });
    target_payload.insert("months".into(), Value::Object(all_months));
    Value::Object(target_payload)
}

fn get_weather() -> Value {
    let w_path = weather_cache_file();
    let cached = read_json_value(&w_path);
    let ts = cached
        .get("timestamp")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    if now_f64() - ts < 1800.0 {
        if let Some(d) = cached.get("data") {
            if d.is_object() {
                return d.clone();
            }
        }
    }

    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(4))
        .build();
    if let Ok(resp) = agent.get("https://wttr.in/?format=j1&lang=fr").call() {
        if let Ok(j) = resp.into_json::<Value>() {
            let cur = j
                .get("current_condition")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .cloned()
                .unwrap_or_else(|| json!({}));
            let area = j
                .get("nearest_area")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .cloned()
                .unwrap_or_else(|| json!({}));
            let city = area
                .get("areaName")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|o| o.get("value"))
                .and_then(|v| v.as_str())
                .unwrap_or("Paris");
            let country = area
                .get("country")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|o| o.get("value"))
                .and_then(|v| v.as_str())
                .unwrap_or("FR");
            let temp_c = cur.get("temp_C").and_then(|v| v.as_str()).unwrap_or("18");
            let desc = cur
                .get("lang_fr")
                .or_else(|| cur.get("weatherDesc"))
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|o| o.get("value"))
                .and_then(|v| v.as_str())
                .unwrap_or("Clair");
            let code: i32 = cur
                .get("weatherCode")
                .and_then(|v| v.as_str())
                .and_then(|s| s.parse().ok())
                .unwrap_or(113);
            let icon = match code {
                116 => "⛅",
                119 | 122 | 143 | 248 | 260 => "☁️",
                176 | 263 | 266 | 293 | 296 | 299 | 302 | 305 | 308 | 353 | 356 | 359 => "🌧️",
                200 | 386 | 389 | 392 | 395 => "⛈️",
                179 | 227 | 230 | 323 | 326 | 329 | 332 | 335 | 338 | 368 | 371 => "❄️",
                _ => "☀️",
            };
            let data = json!({
                "location": format!("{}, {}", city, country),
                "temp": format!("{}°C", temp_c),
                "desc": desc,
                "icon": icon,
            });
            let _ = write_private_json(&w_path, &json!({ "timestamp": now_f64(), "data": data }));
            return data;
        }
    }

    json!({
        "location": "France",
        "temp": "--°C",
        "desc": "Indisponible",
        "icon": "⛅",
    })
}

fn parse_hhmm(time_str: &str) -> Option<(i32, i32)> {
    let t = time_str.trim().to_ascii_lowercase().replace('h', ":");
    if t.is_empty() {
        return None;
    }
    let re = Regex::new(r"^(\d{1,2})(?::(\d{1,2}))?$").unwrap();
    let cap = re.captures(&t)?;
    let hh: i32 = cap[1].parse().ok()?;
    let mm: i32 = cap
        .get(2)
        .and_then(|m| m.as_str().parse().ok())
        .unwrap_or(0);
    if (0..=23).contains(&hh) && (0..=59).contains(&mm) {
        Some((hh, mm))
    } else {
        None
    }
}

fn add_calendar_event(
    date_str: &str,
    summary_in: &str,
    start_time: &str,
    end_time: &str,
    location: &str,
) -> Value {
    let summary = summary_in.trim();
    if summary.is_empty() {
        return json!({ "success": false, "message": "Le titre de l'événement est requis" });
    }
    let Some((ev_y, ev_m, ev_d)) = parse_ymd(date_str) else {
        return json!({ "success": false, "message": format!("Date invalide : {}", date_str) });
    };

    let secrets = read_json_value(&core_dir().join("secrets.json"));
    let nc = secrets.get("nextcloud").cloned().unwrap_or(Value::Null);
    let base_url = nc
        .get("url")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim_end_matches('/')
        .to_string();
    let user = nc.get("user").and_then(|v| v.as_str()).unwrap_or("");
    let app_password = nc
        .get("app_password")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if base_url.is_empty() || user.is_empty() || app_password.is_empty() {
        return json!({
            "success": false,
            "message": "Identifiants Nextcloud manquants dans core/secrets.json",
        });
    }

    let st_parsed = if !start_time.trim().is_empty() {
        let Some(p) = parse_hhmm(start_time) else {
            return json!({ "success": false, "message": "Format heure début invalide (attendu HH:MM)" });
        };
        Some(p)
    } else {
        None
    };

    let et_parsed = if !end_time.trim().is_empty() {
        let Some(p) = parse_hhmm(end_time) else {
            return json!({ "success": false, "message": "Format heure fin invalide (attendu HH:MM)" });
        };
        Some(p)
    } else {
        None
    };

    let uid = uuid_v4();
    let now_utc = now_utc_stamp();
    let (dtstart_line, dtend_line) = if let Some((sh, sm)) = st_parsed {
        let dt_start_utc = local_to_utc_stamp(ev_y, ev_m, ev_d, sh, sm, 0);
        let (ey, em, ed, eh, emin) = if let Some((eh, emin)) = et_parsed {
            if (eh, emin) <= (sh, sm) {
                let (ny, nm, nd) = add_days_ymd(ev_y, ev_m, ev_d, 1);
                (ny, nm, nd, eh, emin)
            } else {
                (ev_y, ev_m, ev_d, eh, emin)
            }
        } else if sh + 1 >= 24 {
            let (ny, nm, nd) = add_days_ymd(ev_y, ev_m, ev_d, 1);
            (ny, nm, nd, (sh + 1) - 24, sm)
        } else {
            (ev_y, ev_m, ev_d, sh + 1, sm)
        };
        let dt_end_utc = local_to_utc_stamp(ey, em, ed, eh, emin, 0);
        (
            format!("DTSTART:{}", dt_start_utc),
            format!("DTEND:{}", dt_end_utc),
        )
    } else {
        let (ny, nm, nd) = add_days_ymd(ev_y, ev_m, ev_d, 1);
        (
            format!("DTSTART;VALUE=DATE:{:04}{:02}{:02}", ev_y, ev_m, ev_d),
            format!("DTEND;VALUE=DATE:{:04}{:02}{:02}", ny, nm, nd),
        )
    };

    let mut ics_lines = vec![
        "BEGIN:VCALENDAR".to_string(),
        "VERSION:2.0".to_string(),
        "PRODID:-//Quickshell//CalDAV Client//FR".to_string(),
        "BEGIN:VEVENT".to_string(),
        format!("UID:{}", uid),
        format!("DTSTAMP:{}", now_utc),
        dtstart_line,
        dtend_line,
        format!("SUMMARY:{}", escape_ics_text(summary)),
    ];
    if !location.trim().is_empty() {
        ics_lines.push(format!("LOCATION:{}", escape_ics_text(location)));
    }
    ics_lines.push("END:VEVENT".to_string());
    ics_lines.push("END:VCALENDAR".to_string());
    ics_lines.push(String::new());
    let ics_body = ics_lines.join("\r\n");

    let auth_hdr = basic_auth_header(user, app_password);
    let cal_urls = discover_calendars(&base_url, user, &auth_hdr);
    if cal_urls.is_empty() {
        return json!({ "success": false, "message": "Aucun calendrier trouvé sur le compte Nextcloud" });
    }
    let target_cal = cal_urls
        .iter()
        .find(|u| u.to_ascii_lowercase().contains("/personal"))
        .unwrap_or(&cal_urls[0]);
    let put_url = format!("{}/{}.ics", target_cal.trim_end_matches('/'), uid);

    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(8))
        .build();
    match agent
        .put(&put_url)
        .set("Authorization", &auth_hdr)
        .set("Content-Type", "text/calendar; charset=utf-8")
        .set("If-None-Match", "*")
        .send_string(&ics_body)
    {
        Ok(r) if matches!(r.status(), 200 | 201 | 204) => {
            let cache_key = format!("{:04}-{:02}", ev_y, ev_m);
            let nc_path = nc_cache_file();
            if let Some(mut map) = read_json_value(&nc_path).as_object().cloned() {
                if map.remove(&cache_key).is_some() {
                    let _ = write_private_json(&nc_path, &Value::Object(map));
                }
            }
            json!({ "success": true, "uid": uid, "date": date_str, "message": "Événement ajouté" })
        }
        Ok(r) => json!({ "success": false, "message": format!("Erreur CalDAV HTTP {}", r.status()) }),
        Err(ureq::Error::Status(401 | 403, _)) => {
            json!({ "success": false, "message": "Authentification Nextcloud refusée" })
        }
        Err(ureq::Error::Status(code, _)) => {
            json!({ "success": false, "message": format!("Erreur CalDAV HTTP {}", code) })
        }
        Err(e) => json!({ "success": false, "message": format!("Erreur réseau : {}", e) }),
    }
}

pub fn run(args: &[String]) -> i32 {
    let action = args.first().map(|s| s.as_str()).unwrap_or("month");
    let out = match action {
        "weather" => get_weather(),
        "month" => {
            let y = args.get(1).and_then(|s| s.parse::<i32>().ok());
            let m = args.get(2).and_then(|s| s.parse::<i32>().ok());
            let force = args.iter().any(|a| a == "--force");
            get_month_events(y, m, force)
        }
        "add" => add_calendar_event(
            args.get(1).map(|s| s.as_str()).unwrap_or(""),
            args.get(2).map(|s| s.as_str()).unwrap_or(""),
            args.get(3).map(|s| s.as_str()).unwrap_or(""),
            args.get(4).map(|s| s.as_str()).unwrap_or(""),
            args.get(5).map(|s| s.as_str()).unwrap_or(""),
        ),
        _ => get_month_events(None, None, false),
    };
    println!("{}", out);
    0
}
