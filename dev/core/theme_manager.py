import json
import os
import subprocess
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STYLE_FILE = os.path.join(BASE_DIR, "style_vars.json")
ROFI_GEN_SCRIPT = os.path.join(BASE_DIR, "generate_rofi_theme.sh")


def set_theme(theme_name):
    if not os.path.exists(STYLE_FILE):
        print(f"Style file not found: {STYLE_FILE}")
        return False

    with open(STYLE_FILE, "r") as f:
        data = json.load(f)

    if theme_name in data.get("palette", {}):
        data["active_theme"] = theme_name
        with open(STYLE_FILE, "w") as f:
            json.dump(data, f, indent=4)
        if os.path.exists(ROFI_GEN_SCRIPT):
            subprocess.run(["bash", ROFI_GEN_SCRIPT], check=False)
        print(f"Theme switched to {theme_name}")
        return True
    else:
        print(f"Theme '{theme_name}' not found in style_vars.json.")
        return False


if __name__ == "__main__":
    if len(sys.argv) > 1:
        set_theme(sys.argv[1])
