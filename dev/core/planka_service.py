#!/usr/bin/env python3
"""Service Kanban Planka pour l'Îlot dynamique (onglet « Projets ») et l'agent.

Commandes CLI (sortie JSON sur une ligne) :
    python3 planka_service.py statut
    python3 planka_service.py board [board_id]
    python3 planka_service.py creer <list_id> <titre> [description]
    python3 planka_service.py deplacer <card_id> <target_list_id> [position]
    python3 planka_service.py toggle_checklist <item_id> <true|false>
    python3 planka_service.py supprimer <card_id>
    python3 planka_service.py agent_col <list_id> <inactif|autonome|approbation>
    python3 planka_service.py agent_demandes
"""
from __future__ import annotations

import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SECRETS_FILE = os.path.join(BASE_DIR, "secrets.json")
CACHE_TTL_SECONDS = 30
TIMEOUT_SECONDS = 4


def _cache_dir() -> str:
    p = os.path.expanduser("~/.cache/quickshell")
    try:
        os.makedirs(p, mode=0o700, exist_ok=True)
        return p
    except Exception:
        return os.environ.get("XDG_RUNTIME_DIR", "/tmp")


CACHE_FILE = os.path.join(_cache_dir(), "planka_cache.json")
AGENT_COLS_FILE = os.path.join(_cache_dir(), "planka_agent_cols.json")
ACTIVE_BOARD_FILE = os.path.join(_cache_dir(), "planka_active_board.json")


def _sortir(data: dict) -> int:
    sys.stdout.write(json.dumps(data, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    return 0


def _load_secrets() -> dict:
    if not os.path.exists(SECRETS_FILE):
        return {}
    try:
        with open(SECRETS_FILE, "r", encoding="utf-8") as f:
            return json.load(f) or {}
    except Exception:
        return {}


def _planka_config() -> dict:
    cfg = _load_secrets().get("planka")
    if not isinstance(cfg, dict):
        return {}
    return {
        "url": str(cfg.get("url") or "").strip().rstrip("/"),
        "api_key": str(cfg.get("api_key") or "").strip(),
        "default_project_id": cfg.get("default_project_id"),
        "default_board_id": cfg.get("default_board_id"),
    }


def _read_json_file(path: str, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _write_private_json(path: str, data) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def invalidate_cache() -> None:
    try:
        if os.path.exists(CACHE_FILE):
            os.remove(CACHE_FILE)
    except OSError:
        pass


def load_active_board() -> str:
    data = _read_json_file(ACTIVE_BOARD_FILE, {})
    return str(data.get("board_id") or "") if isinstance(data, dict) else ""


def set_active_board(board_id: str) -> dict:
    bid = str(board_id or "").strip()
    if not bid:
        return {"ok": False, "error": "board_id manquant"}
    _write_private_json(ACTIVE_BOARD_FILE, {"board_id": bid})
    invalidate_cache()
    return {"ok": True, "board_id": bid}


def load_agent_cols() -> dict:
    data = _read_json_file(AGENT_COLS_FILE, {})
    return data if isinstance(data, dict) else {}


def set_agent_col(list_id: str, mode: str) -> dict:
    mode = str(mode or "inactif").strip().lower()
    if mode not in ("inactif", "autonome", "approbation"):
        return {"ok": False, "error": f"Mode invalide : {mode}"}
    cols = load_agent_cols()
    if mode == "inactif":
        cols.pop(str(list_id), None)
    else:
        cols[str(list_id)] = mode
    _write_private_json(AGENT_COLS_FILE, cols)
    return {"ok": True, "list_id": str(list_id), "mode": mode, "agent_cols": cols}


def _api_request(cfg: dict, method: str, path: str, payload: dict | None = None):
    url = f"{cfg['url']}{path}"
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    base_headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
    }

    # Planka v2 utilise X-Api-Key ; on tente aussi Bearer si 401 (jeton JWT / v1).
    auth_variants = [
        {"X-Api-Key": cfg["api_key"]},
        {"Authorization": f"Bearer {cfg['api_key']}"},
    ]
    last_err = None
    for auth_hdr in auth_variants:
        headers = {**base_headers, **auth_hdr}
        req = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as e:
            if e.code == 401:
                last_err = f"HTTP 401 (authentification refusée)"
                continue
            detail = ""
            try:
                detail = e.read().decode("utf-8", errors="ignore")[:200]
            except Exception:
                pass
            raise RuntimeError(f"HTTP {e.code}: {detail or e.reason}") from e
        except urllib.error.URLError as e:
            raise ConnectionError(f"Serveur Planka inaccessible : {e.reason}") from e

    raise PermissionError(last_err or "Authentification Planka refusée")


def _due_urgency(due_date_str: str | None) -> tuple[str, float | None]:
    """Retourne ('rouge'|'orange'|'vert', heures_restantes)."""
    if not due_date_str:
        return "vert", None
    try:
        s = str(due_date_str).strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        dt = datetime.datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        now = datetime.datetime.now(datetime.timezone.utc)
        hours = (dt - now).total_seconds() / 3600.0
        if hours < 6.0:
            return "rouge", round(hours, 1)
        if hours < 24.0:
            return "orange", round(hours, 1)
        return "vert", round(hours, 1)
    except Exception:
        return "vert", None


def _pick_board(cfg: dict, requested_board_id: str | None = None) -> tuple[list, dict | None]:
    proj_resp = _api_request(cfg, "GET", "/api/projects")
    projects = proj_resp.get("items") or []
    included = proj_resp.get("included") or {}
    boards = included.get("boards") or []

    # Si /api/projects ne renvoie pas boards inclus, on tente par projet.
    if not boards and projects:
        for pr in projects:
            pid = pr.get("id")
            if not pid:
                continue
            try:
                p_detail = _api_request(cfg, "GET", f"/api/projects/{pid}")
                p_boards = (p_detail.get("included") or {}).get("boards") or []
                for b in p_boards:
                    boards.append(b)
            except Exception:
                continue

    if not boards:
        return projects, [], None

    target_id = requested_board_id or load_active_board() or cfg.get("default_board_id")
    if target_id:
        for b in boards:
            if str(b.get("id")) == str(target_id):
                return projects, boards, b

    def_pid = cfg.get("default_project_id")
    if def_pid:
        for b in boards:
            if str(b.get("projectId")) == str(def_pid):
                return projects, boards, b

    return projects, boards, boards[0]


def _fetch_board_snapshot(cfg: dict, board_id: str | None = None, force: bool = False) -> dict:
    if not cfg.get("url") or not cfg.get("api_key"):
        return {
            "ok": False,
            "statut": "non_configure",
            "error": "Planka non configuré dans core/secrets.json",
            "echeance_proche": False,
            "urgence": "none",
            "lists": [],
        }

    if not force:
        cached = _read_json_file(CACHE_FILE, None)
        if isinstance(cached, dict) and cached.get("ok"):
            age = time.time() - float(cached.get("ts") or 0)
            same_board = (not board_id) or (str(cached.get("board", {}).get("id")) == str(board_id))
            if age < CACHE_TTL_SECONDS and same_board:
                cached["agent_cols"] = load_agent_cols()
                return cached

    try:
        me_id = None
        try:
            me_resp = _api_request(cfg, "GET", "/api/users/me")
            me_id = str((me_resp.get("item") or {}).get("id") or "")
        except Exception:
            me_id = None

        projects, all_boards, board = _pick_board(cfg, board_id)
        if not board:
            return {
                "ok": True,
                "statut": "vide",
                "ts": time.time(),
                "board": None,
                "boards": [],
                "projects": projects,
                "lists": [],
                "echeance_proche": False,
                "urgence": "none",
                "agent_cols": load_agent_cols(),
            }

        bid = str(board["id"])
        b_resp = _api_request(cfg, "GET", f"/api/boards/{bid}")
        b_item = b_resp.get("item") or board
        inc = b_resp.get("included") or {}

        # Planka v2 inclut des listes système (`archive`, `trash`) sans nom ni position.
        raw_lists = sorted(
            [
                l for l in (inc.get("lists") or [])
                if (l.get("type") or "active") not in ("archive", "trash")
            ],
            key=lambda x: float(x.get("position") or 0),
        )
        raw_cards = inc.get("cards") or []
        raw_labels = {str(l["id"]): l for l in (inc.get("labels") or []) if l.get("id")}
        raw_card_labels = inc.get("cardLabels") or []
        raw_card_members = inc.get("cardMemberships") or []
        raw_task_lists = inc.get("taskLists") or []
        raw_tasks = inc.get("tasks") or []

        # Indexation des relations par carte
        labels_by_card = {}
        for cl in raw_card_labels:
            cid = str(cl.get("cardId") or "")
            lid = str(cl.get("labelId") or "")
            if cid and lid in raw_labels:
                lbl = raw_labels[lid]
                labels_by_card.setdefault(cid, []).append({
                    "id": lid,
                    "name": lbl.get("name") or "",
                    "color": lbl.get("color") or "berry-red",
                })

        members_by_card = {}
        for cm in raw_card_members:
            cid = str(cm.get("cardId") or "")
            uid = str(cm.get("userId") or "")
            if cid and uid:
                members_by_card.setdefault(cid, set()).add(uid)

        # Checklists (Planka v1: tasks directement sur cardId ou v2: taskLists -> tasks)
        task_list_to_card = {
            str(tl["id"]): str(tl.get("cardId") or "")
            for tl in raw_task_lists if tl.get("id")
        }
        tasks_by_card = {}
        for t in raw_tasks:
            cid = str(t.get("cardId") or task_list_to_card.get(str(t.get("taskListId") or ""), ""))
            if not cid:
                continue
            tasks_by_card.setdefault(cid, []).append({
                "id": str(t.get("id")),
                "name": t.get("name") or "",
                "isCompleted": bool(t.get("isCompleted")),
                "position": float(t.get("position") or 0),
            })

        agent_cols = load_agent_cols()
        cards_by_list = {str(l["id"]): [] for l in raw_lists if l.get("id")}
        worst_urgency = "none"
        open_cards = 0

        for c in sorted(raw_cards, key=lambda x: float(x.get("position") or 0)):
            cid = str(c.get("id") or "")
            lid = str(c.get("listId") or "")
            if not cid or lid not in cards_by_list:
                continue
            due = c.get("dueDate")
            urg, hours_left = _due_urgency(due)
            if urg == "rouge":
                worst_urgency = "rouge"
            elif urg == "orange" and worst_urgency != "rouge":
                worst_urgency = "orange"

            c_tasks = sorted(tasks_by_card.get(cid, []), key=lambda x: x["position"])
            done_cnt = sum(1 for x in c_tasks if x["isCompleted"])
            is_mine = bool(me_id and me_id in members_by_card.get(cid, set()))
            open_cards += 1

            cards_by_list[lid].append({
                "id": cid,
                "listId": lid,
                "name": c.get("name") or "Sans titre",
                "description": c.get("description") or "",
                "position": float(c.get("position") or 0),
                "dueDate": due,
                "urgence": urg,
                "hoursLeft": hours_left,
                "labels": labels_by_card.get(cid, []),
                "tasks": c_tasks,
                "tasksDone": done_cnt,
                "tasksTotal": len(c_tasks),
                "isMine": is_mine,
                "url": f"{cfg['url']}/cards/{cid}",
            })

        lists_out = []
        for l in raw_lists:
            lid = str(l.get("id") or "")
            if not lid:
                continue
            lists_out.append({
                "id": lid,
                "name": l.get("name") or "Liste",
                "position": float(l.get("position") or 0),
                "agentMode": agent_cols.get(lid, "inactif"),
                "cards": cards_by_list.get(lid, []),
            })

        snapshot = {
            "ok": True,
            "statut": "connecte",
            "ts": time.time(),
            "me_id": me_id,
            "board": {
                "id": bid,
                "name": b_item.get("name") or "Tableau",
                "projectId": str(b_item.get("projectId") or ""),
                "url": f"{cfg['url']}/boards/{bid}",
            },
            "boards": [
                {
                    "id": str(b.get("id")),
                    "name": b.get("name") or "Tableau",
                    "projectId": str(b.get("projectId") or ""),
                }
                for b in all_boards if b.get("id")
            ],
            "projects": [{"id": str(p.get("id")), "name": p.get("name") or "Projet"} for p in projects if p.get("id")],
            "lists": lists_out,
            "open_cards": open_cards,
            "echeance_proche": worst_urgency in ("orange", "rouge"),
            "urgence": worst_urgency,
            "agent_cols": agent_cols,
        }
        _write_private_json(CACHE_FILE, snapshot)
        return snapshot

    except Exception as e:
        cached = _read_json_file(CACHE_FILE, None)
        if isinstance(cached, dict) and cached.get("ok"):
            cached["statut"] = "deconnecte"
            cached["error"] = str(e)
            cached["agent_cols"] = load_agent_cols()
            return cached
        return {
            "ok": False,
            "statut": "deconnecte",
            "error": str(e),
            "echeance_proche": False,
            "urgence": "none",
            "lists": [],
        }


def cmd_statut() -> dict:
    cfg = _planka_config()
    snap = _fetch_board_snapshot(cfg)
    return {
        "ok": snap.get("ok", False),
        "statut": snap.get("statut", "deconnecte"),
        "error": snap.get("error", ""),
        "board_name": (snap.get("board") or {}).get("name", ""),
        "open_cards": snap.get("open_cards", 0),
        "echeance_proche": bool(snap.get("echeance_proche", False)),
        "urgence": snap.get("urgence", "none"),
    }


def cmd_creer(list_id: str, titre: str, description: str = "") -> dict:
    cfg = _planka_config()
    if not cfg.get("url") or not cfg.get("api_key"):
        return {"ok": False, "error": "Planka non configuré"}
    titre = str(titre or "").strip()
    if not titre:
        return {"ok": False, "error": "Titre vide"}
    payload = {
        "name": titre,
        "position": 65536,
        "type": "project",
    }
    if description:
        payload["description"] = description
    resp = _api_request(cfg, "POST", f"/api/lists/{list_id}/cards", payload)
    invalidate_cache()
    return {"ok": True, "card": resp.get("item") or resp}


def cmd_deplacer(card_id: str, target_list_id: str, position: float | None = None) -> dict:
    cfg = _planka_config()
    if not cfg.get("url") or not cfg.get("api_key"):
        return {"ok": False, "error": "Planka non configuré"}
    payload = {
        "listId": str(target_list_id),
        "position": float(position) if position is not None else 65536.0,
    }
    resp = _api_request(cfg, "PATCH", f"/api/cards/{card_id}", payload)
    invalidate_cache()
    return {"ok": True, "card": resp.get("item") or resp}


def cmd_toggle_checklist(item_id: str, completed: bool) -> dict:
    cfg = _planka_config()
    if not cfg.get("url") or not cfg.get("api_key"):
        return {"ok": False, "error": "Planka non configuré"}
    resp = _api_request(cfg, "PATCH", f"/api/tasks/{item_id}", {"isCompleted": bool(completed)})
    invalidate_cache()
    return {"ok": True, "task": resp.get("item") or resp}


def cmd_supprimer(card_id: str) -> dict:
    cfg = _planka_config()
    if not cfg.get("url") or not cfg.get("api_key"):
        return {"ok": False, "error": "Planka non configuré"}
    _api_request(cfg, "DELETE", f"/api/cards/{card_id}")
    invalidate_cache()
    return {"ok": True, "deleted": str(card_id)}


def cmd_agent_demandes() -> dict:
    cfg = _planka_config()
    snap = _fetch_board_snapshot(cfg, force=True)
    if not snap.get("ok"):
        return snap
    lists = snap.get("lists") or []
    demandes = []
    for idx, lst in enumerate(lists):
        mode = lst.get("agentMode", "inactif")
        if mode == "inactif":
            continue
        next_list_id = lists[idx + 1]["id"] if idx + 1 < len(lists) else None
        for card in lst.get("cards") or []:
            demandes.append({
                "id": card["id"],
                "name": card["name"],
                "description": card.get("description", ""),
                "listId": lst["id"],
                "listName": lst["name"],
                "nextListId": next_list_id,
                "mode": mode,
                "url": card.get("url", ""),
            })
    return {"ok": True, "demandes": demandes}


def main(argv: list[str]) -> int:
    action = argv[1] if len(argv) > 1 else "statut"
    try:
        if action == "statut":
            return _sortir(cmd_statut())
        if action == "board":
            bid = argv[2] if len(argv) > 2 else None
            return _sortir(_fetch_board_snapshot(_planka_config(), bid))
        if action == "set_board" and len(argv) >= 3:
            return _sortir(set_active_board(argv[2]))
        if action == "creer" and len(argv) >= 4:
            desc = argv[4] if len(argv) > 4 else ""
            return _sortir(cmd_creer(argv[2], argv[3], desc))
        if action == "deplacer" and len(argv) >= 4:
            pos = float(argv[4]) if len(argv) > 4 else None
            return _sortir(cmd_deplacer(argv[2], argv[3], pos))
        if action == "toggle_checklist" and len(argv) >= 4:
            val = str(argv[3]).lower() in ("true", "1", "yes", "oui")
            return _sortir(cmd_toggle_checklist(argv[2], val))
        if action == "supprimer" and len(argv) >= 3:
            return _sortir(cmd_supprimer(argv[2]))
        if action == "agent_col" and len(argv) >= 4:
            return _sortir(set_agent_col(argv[2], argv[3]))
        if action == "agent_demandes":
            return _sortir(cmd_agent_demandes())
        return _sortir({"ok": False, "error": f"Action inconnue : {action}"})
    except Exception as e:
        return _sortir({"ok": False, "statut": "erreur", "error": str(e)})


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
