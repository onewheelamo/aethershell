#!/usr/bin/env python3
"""Bascule toutes les fenêtres du workspace actif entre flottant et tiling."""

import json
import subprocess
import sys


def hypr_json(cmd):
    res = subprocess.run(["hyprctl", "-j", cmd], capture_output=True, text=True, check=True)
    return json.loads(res.stdout)


def main():
    try:
        ws = hypr_json("activeworkspace")
        ws_id = ws.get("id")
        if ws_id is None:
            return 0
        clients = hypr_json("clients")
    except Exception as exc:
        print(f"workspace_float_toggle: {exc}", file=sys.stderr)
        return 1

    in_ws = [
        c for c in clients
        if c.get("workspace", {}).get("id") == ws_id
        and c.get("mapped", True)
        and not c.get("hidden", False)
        and c.get("address")
    ]
    if not in_ws:
        return 0

    want_float = any(not c.get("floating", False) for c in in_ws)
    targets = [
        c["address"] for c in in_ws
        if bool(c.get("floating", False)) != want_float
    ]
    if not targets:
        return 0

    lua = "; ".join(
        f'hl.dispatch(hl.dsp.window.float({{ action = "toggle", window = "address:{addr}" }}))'
        for addr in targets
    )
    subprocess.run(["hyprctl", "eval", lua], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
