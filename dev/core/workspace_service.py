import json
import subprocess

PERMANENT_WORKSPACES = {
    1: "一",
    2: "二",
    3: "三",
    4: "四",
    5: "五",
}


def get_workspaces():
    try:
        output = subprocess.check_output(["hyprctl", "workspaces", "-j"]).decode("utf-8")
        data = json.loads(output)

        active_res = subprocess.check_output(["hyprctl", "activeworkspace", "-j"]).decode("utf-8")
        active_data = json.loads(active_res)
        active_id = int(active_data.get("id", 1))

        ws_map = {}
        for ws_id, default_name in PERMANENT_WORKSPACES.items():
            ws_map[ws_id] = {
                "id": ws_id,
                "name": default_name,
                "windows": 0,
                "persistent": True,
                "active": (ws_id == active_id),
            }

        for ws in data:
            wid = int(ws.get("id", 0))
            if wid <= 0:
                continue
            win_count = int(ws.get("windows", 0))
            if wid in ws_map:
                ws_map[wid]["windows"] = win_count
            else:
                ws_map[wid] = {
                    "id": wid,
                    "name": ws.get("name") or str(wid),
                    "windows": win_count,
                    "persistent": False,
                    "active": (wid == active_id),
                }

        ordered = [ws_map[k] for k in sorted(ws_map.keys())]
        return {
            "workspaces": [w["id"] for w in ordered],
            "details": ordered,
            "active": active_id,
        }
    except Exception as e:
        fallback = [
            {
                "id": k,
                "name": v,
                "windows": 0,
                "persistent": True,
                "active": (k == 1),
            }
            for k, v in PERMANENT_WORKSPACES.items()
        ]
        return {
            "error": str(e),
            "workspaces": [1, 2, 3, 4, 5],
            "details": fallback,
            "active": 1,
        }


if __name__ == "__main__":
    print(json.dumps(get_workspaces()))
