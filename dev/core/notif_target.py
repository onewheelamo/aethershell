#!/usr/bin/env python3
"""Cible d'une notification : ce que le clic sur son titre ouvrira.

Une « cible » est figée **à la réception** de la notification (l'objet
QsNotification peut être détruit ensuite) puis rangée dans l'entrée du shell.
Ce programme ne lance rien : il décide, et il journalise sa décision pour qu'on
puisse la relire sans cliquer.

Cascade, on s'arrête à la première règle qui répond :
  1. hint explicite      x-aethershell-open:file:///…   (posé par nos scripts)
  2. table par application  core/notif_targets.json : appName ou desktopEntry
  3. action par défaut      la notification fournit une action « default »
  4. chemin / URL           repéré dans le texte, classé par nature
  5. application émettrice  desktopEntry → Exec de app_index.json

Les programmes ne sont jamais écrits ici : les alias viennent du tiroir
« Programmes par défaut » du panneau (core/app_vars.json, via Theme.program).

Usage :
    notif_target.py --once < payload.json     # une décision, puis sortie
    notif_target.py --serve                   # une ligne JSON par requête
"""
import json
import os
import re
import shlex
import sys
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

# Le résolveur qui sert le shell écrit aussi l'historique : c'est le seul endroit
# qui voit chaque notification avec sa cible déjà décidée. Les essais en `--once`
# n'écrivent rien, pour ne pas polluer l'historique réel.
RECORD_HISTORY = False
# Hint de notification qui désigne la cible d'un clic. L'ancien nom (x-amo-open)  # neutralite:ok
# portait celui de l'utilisateur : il reste lu tant qu'une machine n'a pas été
# redéployée, mais on écrit toujours le nom neutre.
HINTS_OUVERTURE = ("x-aethershell-open", "x-amo-open")  # neutralite:ok — ancien nom lu
CORE_DIR = Path(__file__).resolve().parent
CACHE_LOG = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell" / "notifications.log"

KIND_BY_EXT = {
    "video": {"mp4", "mkv", "webm", "mov", "m4v", "avi", "m2ts", "mpg", "mpeg"},
    "image": {"png", "jpg", "jpeg", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff"},
    "text": {"txt", "md", "log", "json", "yaml", "yml", "toml", "conf", "ini", "sh",
             "py", "qml", "lua", "desktop", "csv", "org"},
}

FILE_URI_RE = re.compile(r"file://[^\s\"'<>«»]+")
URL_RE = re.compile(r"https?://[^\s\"'<>«»]+")
PATH_RE = re.compile(r"(?:^|[\s(\[«\"'])((?:~|/)[^\s\"'<>()\[\]«»]+)")
TRAILING = ".,;:!?…»"


def load_json(name, default):
    try:
        with open(CORE_DIR / name, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


def expand(path):
    if path.startswith("~"):
        return os.path.expanduser(path)
    return path


def path_kind(path):
    """Nature d'un chemin : dossier, vidéo, image, texte — ou « inconnu ».

    L'existence tranche quand elle est disponible (un dossier ne se devine pas
    à son extension) ; sinon l'extension seule décide, et une extension
    inconnue ne produit aucune cible plutôt qu'une ouverture au hasard.
    """
    p = expand(path)
    try:
        if os.path.isdir(p):
            return "folder"
    except OSError:
        pass
    ext = Path(p).suffix.lstrip(".").lower()
    for kind, exts in KIND_BY_EXT.items():
        if ext in exts:
            return kind
    if not ext and not os.path.splitext(p)[1]:
        return "folder"
    return ""


def candidates(text):
    """Chemins et URL cités dans le texte, dans l'ordre d'apparition.

    Les URI `file://` passent avant les chemins nus : un expéditeur qui prend la
    peine d'encoder une URI mérite la priorité.
    """
    out = []
    for match in FILE_URI_RE.finditer(text):
        raw = match.group(0)
        try:
            path = unquote(urlparse(raw).path)
        except Exception:
            path = raw[len("file://"):]
        out.append(path)
    for match in PATH_RE.finditer(text):
        out.append(match.group(1).rstrip(TRAILING))
    return out


def alias_command(alias_cmd, target):
    """Commande d'alias + cible en argument, jamais concaténée dans la chaîne.

    La commande vient de la configuration de l'utilisateur, la cible du texte
    d'une notification : elle arrive donc en `$1`. Sans cible (règle qui demande
    seulement de lancer l'application), l'alias part tel quel : lui passer `""`
    ferait ouvrir à Thunar ou Gwenview un fichier dont le nom est vide.
    """
    if not target:
        return shlex.split(alias_cmd)
    return ["sh", "-c", alias_cmd + ' "$1"', "_", target]


def terminal_command(term, run):
    """`kitty <cmd>` pour kitty, `<term> -e <cmd>` pour les autres.

    Un seul endroit porte cette différence — la table, elle, ne nomme qu'un
    alias de terminal.
    """
    parts = shlex.split(term) if term else ["ghostty"]
    binary = os.path.basename(parts[0]) if parts else ""
    if binary == "kitty":
        return parts + shlex.split(run)
    return parts + ["-e"] + shlex.split(run)


def resolve(req):
    """Rend la cible d'une notification, ou un dict vide (aucune affordance)."""
    targets = load_json("notif_targets.json", {})
    apps = load_json("app_vars.json", {})
    index = load_json("app_index.json", [])

    summary = str(req.get("summary") or "")
    body = str(req.get("body") or "")
    app_name = str(req.get("appName") or "")
    desktop = str(req.get("desktopEntry") or "")
    hints = req.get("hints") or {}
    actions = req.get("actions") or []

    def program(name):
        value = apps.get(name)
        return str(value).strip() if value else ""

    def open_with_alias(alias, target, rule, kind):
        alias = alias or ""
        cmd = program(alias)
        if not cmd:
            return {"rule": rule + "-repli", "kind": kind, "alias": alias,
                    "cmd": alias_command("xdg-open", target),
                    "display": "xdg-open " + shlex.quote(target) if target else "xdg-open",
                    "label": target, "missingAlias": alias}
        return {"rule": rule, "kind": kind, "alias": alias, "cmd": alias_command(cmd, target),
                "display": (cmd + " " + shlex.quote(target)) if target else cmd,
                "label": target}

    # Le hint qui désigne la cible porte un nom neutre. L'ancien (x-amo-open)  # neutralite:ok
    # nommait l'utilisateur : il reste lu pour les notifications déjà en vol et
    # pour les scripts d'une machine pas encore redéployée.
    # 1. hint explicite (nos propres scripts)
    for key, value in hints.items():
        if str(key).lower().endswith(HINTS_OUVERTURE) and isinstance(value, str) and value:
            path = value[len("file://"):] if value.startswith("file://") else value
            path = unquote(path)
            res = open_with_alias((targets.get("types") or {}).get(path_kind(path)) or "",
                                  path, "hint", "file")
            if not res:
                continue
            res["label"] = os.path.basename(path)
            return res

    # 2. table par application (appName ou desktopEntry, sans distinction)
    for key in (app_name, desktop):
        rule = (targets.get("apps") or {}).get(key) if key else None
        if not rule:
            continue
        if isinstance(rule, str):
            return {"rule": "table", "kind": "app", "cmd": shlex.split(rule),
                    "display": rule, "label": key}
        if isinstance(rule, dict) and rule.get("run"):
            run = str(rule["run"])
            if rule.get("terminal"):
                term = program((targets.get("terminal_alias") or "Terminal"))
                cmd = terminal_command(term, run)
            else:
                cmd = shlex.split(run)
            return {"rule": "table", "kind": "app", "cmd": cmd,
                    "display": rule.get("label") or " ".join(cmd), "label": key}
        if isinstance(rule, dict) and rule.get("open"):
            return open_with_alias(rule["open"], "", "table", "app")

    # 3. action par défaut fournie par l'application
    for action in actions:
        if str(action.get("identifier", "")).lower() in ("default", "0"):
            return {"rule": "action", "kind": "action", "actionId": action.get("identifier"),
                    "cmd": [], "display": str(action.get("text") or "Ouvrir"),
                    "label": str(action.get("text") or "Ouvrir")}

    # 4. chemin puis URL cités dans le texte
    text = summary + "\n" + body
    found = [p for p in candidates(text) if p]
    found.sort(key=lambda p: 0 if os.path.exists(expand(p)) else 1)
    for path in found:
        kind = path_kind(path)
        if not kind:
            continue
        if not os.path.exists(expand(path)):
            continue
        res = open_with_alias((targets.get("types") or {}).get(kind) or "", path, "chemin", kind)
        res["label"] = os.path.basename(path.rstrip("/")) or path
        return res

    url = URL_RE.search(text)
    if url:
        return open_with_alias(targets.get("url") or "", url.group(0), "url", "url")

    # 5. application émettrice, par son entrée de bureau
    entry = desktop_entry_for(index, desktop, app_name)
    if entry:
        # `focus` : de quoi retrouver la fenêtre déjà ouverte. Un « il faut
        # autoriser » vient d'une application qui tourne — la lancer une seconde
        # fois ouvrirait un doublon au lieu de montrer celle qui attend.
        return {"rule": "app", "kind": "app", "focus": focus_motifs(entry, desktop, app_name),
                "cmd": shlex.split(entry.get("exec") or ""),
                "display": entry.get("exec") or "", "label": entry.get("name") or app_name}

    # Aucune règle : on garde au moins l'application émettrice pour un focus.
    if app_name or desktop:
        return {"rule": "focus", "kind": "focus", "cmd": [],
                "focus": focus_motifs(None, desktop, app_name),
                "display": desktop or app_name, "label": app_name or desktop}

    return {}


def _sans_ext(valeur):
    v = str(valeur or "").strip().lower()
    return v[:-len(".desktop")] if v.endswith(".desktop") else v


def desktop_entry_for(index, desktop, app_name):
    """Entrée de bureau de l'application émettrice, avec de la tolérance.

    Une notification annonce rarement l'identifiant exact : « code » pour
    `code-oss.desktop`, « Antigravity » pour une extension de VS Code. On essaie
    donc l'identifiant tel quel, puis sans `.desktop`, puis par préfixe — et
    seulement ensuite par le nom.
    """
    if not isinstance(index, list):
        return None
    wanted = _sans_ext(desktop)
    if wanted:
        for entry in index:
            if _sans_ext(entry.get("desktop")) == wanted:
                return entry
    if wanted:
        for entry in index:
            candidat = _sans_ext(entry.get("desktop"))
            if candidat and (candidat.startswith(wanted) or wanted.startswith(candidat)):
                return entry
    if app_name:
        for entry in index:
            if _sans_ext(entry.get("name")) == _sans_ext(app_name):
                return entry
    if app_name:
        for entry in index:
            nom = _sans_ext(entry.get("name"))
            if nom and (app_name.lower() in nom or nom in app_name.lower()):
                return entry
    return None


def focus_motifs(entry, desktop, app_name):
    """Motifs pour retrouver la fenêtre : du plus sûr au plus large.

    Le nom du binaire d'abord (c'est la classe Wayland dans la majorité des cas),
    puis l'identifiant de bureau, puis le nom affiché.
    """
    motifs = []
    if isinstance(entry, dict):
        motifs.append(os.path.basename(str(entry.get("exec") or "").split()[0]) if entry.get("exec") else "")
        motifs.append(_sans_ext(entry.get("desktop")))
        motifs.append(_sans_ext(entry.get("name")))
    motifs.append(_sans_ext(desktop))
    motifs.append(_sans_ext(app_name))
    vus, out = set(), []
    for m in motifs:
        m = (m or "").strip()
        if len(m) < 3 or m in vus:
            continue
        vus.add(m)
        out.append(m)
    return out[:4]


def log_line(req, res):
    """Une ligne par notification : de quoi relire la décision sans cliquer."""
    CACHE_LOG.parent.mkdir(parents=True, exist_ok=True)
    try:
        if CACHE_LOG.exists() and CACHE_LOG.stat().st_size > 200_000:
            keep = CACHE_LOG.read_text(encoding="utf-8", errors="replace").splitlines()[-400:]
            CACHE_LOG.write_text("\n".join(keep) + "\n", encoding="utf-8")
    except OSError:
        pass

    def clean(value, limit=90):
        text = re.sub(r"\s+", " ", str(value or "")).strip()
        return (text[:limit] + "…") if len(text) > limit else text

    fields = [
        "app=" + (clean(req.get("appName")) or "-"),
        "desktop=" + (clean(req.get("desktopEntry")) or "-"),
        "regle=" + (res.get("rule") or "aucune"),
        "cible=" + (clean(res.get("display"), 120) or "-"),
        "resume=" + json.dumps(clean(req.get("summary"), 70), ensure_ascii=False),
        "actions=" + str(len(req.get("actions") or [])),
    ]
    if res.get("missingAlias"):
        fields.append("alias_manquant=" + res["missingAlias"])
    if not res:
        fields.append("hints=" + clean(",".join(sorted(str(k) for k in (req.get("hints") or {}))), 120))
    stamp = __import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(CACHE_LOG, "a", encoding="utf-8") as fh:
        fh.write(stamp + " | " + " ".join(fields) + "\n")


def remember(req, res):
    """Trace l'entrée dans l'historique, cible comprise (elle peut être vide)."""
    try:
        import notif_history
        notif_history.add({
            "ts": time.strftime("%Y-%m-%d %H:%M:%S"),
            "ts_ms": int(time.time() * 1000),
            "app": str(req.get("appName") or ""),
            "desktop": str(req.get("desktopEntry") or ""),
            "summary": str(req.get("summary") or ""),
            "body": str(req.get("body") or ""),
            "actions": req.get("actions") or [],
            "target": res or {},
        })
    except Exception as exc:
        print(f"historique non écrit : {exc}", file=sys.stderr)


def answer(req):
    try:
        res = resolve(req)
    except Exception as exc:  # une notification ne doit jamais casser le shell
        res = {"rule": "erreur", "kind": "error", "cmd": [], "display": str(exc), "label": ""}
    try:
        log_line(req, res)
    except Exception:
        pass
    if RECORD_HISTORY:
        remember(req, res)
    out = dict(res)
    if "id" in req:
        out["id"] = req["id"]
    return out


def main():
    global RECORD_HISTORY
    if "--serve" in sys.argv:
        RECORD_HISTORY = True
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except Exception:
                continue
            print(json.dumps(answer(req), ensure_ascii=False), flush=True)
        return
    payload = sys.stdin.read()
    req = json.loads(payload) if payload.strip() else {}
    print(json.dumps(answer(req), ensure_ascii=False))


if __name__ == "__main__":
    main()
