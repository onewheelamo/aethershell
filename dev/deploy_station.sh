#!/bin/bash
# Station Environment Manager & Deployer (Arch Linux — Desktop Tower)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_HYPR="$HOME/.config/hypr"
BACKUP_DIR="$HOME/.config/backups_env"
DEV_DIR="$SCRIPT_DIR"
QS_DIR="$HOME/.config/quickshell"
CORE_DIR="$QS_DIR/core"
DEPS_FILE="$DEV_DIR/dependencies_station.txt"

mkdir -p "$BACKUP_DIR"

# Files edited at runtime by the config panel / onboarding (theme, apps, credentials, keyboard
# layout, shortcuts, monitors...). They are kept on re-deploy ONLY when ~/.config/hypr is already
# managed by this Quickshell environment, i.e. when the marker file below exists. Without the
# marker (first deploy, or after "Restore HN"), the files of another environment would be
# mistaken for user settings, so everything is replaced (a backup is made just before).
# `DEPLOY_OVERWRITE=1` also forces the repository version.
MARKER="$CURRENT_HYPR/.quickshell_managed"
PRESERVE_CORE="style_vars.json app_vars.json secrets.json autostart.json"
PRESERVE_HYPR="input.lua binds.lua programs.lua general.lua colors.lua"

is_preserved() {
    local name="$1" list="$2" item
    [ "${DEPLOY_OVERWRITE:-0}" = "1" ] && return 1
    [ -f "$MARKER" ] || return 1
    for item in $list; do
        [ "$name" = "$item" ] && return 0
    done
    case "$name" in hardware-*.lua) [ "$list" = "$PRESERVE_HYPR" ] && return 0 ;; esac
    return 1
}

# sync_file SRC DST : compare and update target without redundant .new duplicates
sync_file() {
    local src="$1" dst="$2"
    if [ ! -e "$dst" ]; then
        cp "$src" "$dst"
        return
    fi
    if cmp -s "$src" "$dst"; then
        rm -f "$dst.upstream" "$dst.new"
        return
    fi
    case "$(basename "$dst")" in
        secrets.json) ;;
        *)
            echo "  ↪ upstream diff detected for $dst -> saved to $dst.upstream"
            cp "$src" "$dst.upstream"
            rm -f "$dst.new"
            ;;
    esac
}

# copy_dir_files SRC DST PRESERVE_LIST : copy regular files, manage preserved ones with sync_file
copy_dir_files() {
    local src="$1" dst="$2" list="$3" f name
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        if [ -e "$dst/$name" ] && is_preserved "$name" "$list"; then
            sync_file "$f" "$dst/$name"
            continue
        fi
        cp "$f" "$dst/$name"
    done
}

# prune_target DST MANIFEST PRESERVE_LIST : remove target files not in manifest, excluding preserved/system files
prune_target() {
    local dst="$1" manifest="$2" preserve_list="${3:-}" f name
    [ -d "$dst" ] || return 0
    for f in "$dst"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        grep -qxF "$name" "$manifest" && continue
        [ -n "$preserve_list" ] && is_preserved "$name" "$preserve_list" && continue
        case "$name" in
            *.upstream) continue ;;
            hypridle.conf|hyprlock.conf|autostart_cmds.txt|.quickshell_managed) continue ;;
            secrets.json) continue ;;
        esac
        echo "  pruning obsolete target file: $dst/$name"
        rm -f "$f"
    done
}

rotate_backups() {
    local old_backups
    mapfile -t old_backups < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*_20*.tar.gz" -printf "%T@ %p\n" 2>/dev/null | sort -nr | tail -n +4 | awk '{print $2}')
    for b in "${old_backups[@]}"; do
        if [ -n "$b" ] && [ -f "$b" ]; then
            echo "  pruning old backup: $b"
            rm -f "$b"
        fi
    done
}

# Map binary names to Arch Linux package names
pkg_for_bin() {
    case "$1" in
        wpctl) echo "wireplumber" ;;
        nmcli) echo "networkmanager" ;;
        magick) echo "imagemagick" ;;
        *) echo "$1" ;;
    esac
}

check_dependencies() {
    echo "Checking dependencies for Station (Arch Linux Tower)..."
    if [ ! -f "$DEPS_FILE" ]; then
        echo "❌ Error: $DEPS_FILE not found."
        return 1
    fi

    mapfile -t deps < "$DEPS_FILE"
    local missing_bins=()
    local missing_pkgs=()
    for dep in "${deps[@]}"; do
        if [ -z "$dep" ]; then continue; fi
        if ! command -v "$dep" &> /dev/null; then
            missing_bins+=("$dep")
            missing_pkgs+=("$(pkg_for_bin "$dep")")
        fi
    done

    if [ ${#missing_bins[@]} -eq 0 ]; then
        echo "✅ All desktop dependencies installed."
        return 0
    else
        echo "⚠️ Missing system binaries: ${missing_bins[*]} (Arch packages: ${missing_pkgs[*]})"
        read -p "Do you want to try installing them now with pacman? (y/n): " choice
        if [ "$choice" == "y" ]; then
            sudo pacman -S --needed "${missing_pkgs[@]}"
            return $?
        else
            read -p "Continue deployment anyway? (y/n): " cont
            [ "$cont" == "y" ] && return 0 || return 1
        fi
    fi
}

backup_env() {
    BACKUP_OK=0
    echo "Select environment to backup:"
    echo "1 > HN (Hyprland + Noctalia)"
    echo "2 > HQ (Hyprland + Quickshell)"
    echo "s > Skip backup"
    read -p "Choice: " choice

    local stamp
    stamp=$(date +%Y%m%d_%H%M%S)

    case $choice in
        1)
            tar -czf "$BACKUP_DIR/backup_station_hn_$stamp.tar.gz" -C "$HOME/.config" hypr noctalia 2>/dev/null
            cp -f "$BACKUP_DIR/backup_station_hn_$stamp.tar.gz" "$BACKUP_DIR/backup_station_hn.tar.gz"
            echo "✅ HN backed up to $BACKUP_DIR/backup_station_hn_$stamp.tar.gz"
            rotate_backups
            BACKUP_OK=1
            ;;
        2)
            tar -czf "$BACKUP_DIR/backup_station_hq_$stamp.tar.gz" -C "$HOME/.config" hypr quickshell 2>/dev/null
            cp -f "$BACKUP_DIR/backup_station_hq_$stamp.tar.gz" "$BACKUP_DIR/backup_station_hq.tar.gz"
            echo "✅ HQ backed up to $BACKUP_DIR/backup_station_hq_$stamp.tar.gz"
            rotate_backups
            BACKUP_OK=1
            ;;
        s|S)
            echo "⏭️ Backup skipped."
            ;;
        *) echo "⚠️ Invalid choice: skipping backup." ;;
    esac
}

deploy_new_env() {
    echo "🚀 Deploying Station Quickshell Environment (Desktop Tower)..."

    mkdir -p "$CURRENT_HYPR"
    if [ ! -f "$MARKER" ]; then
        if [ "$BACKUP_OK" = "1" ]; then
            echo "ℹ️ No Quickshell marker in $CURRENT_HYPR: existing files will be replaced (backup done)."
        else
            echo "ℹ️ No Quickshell marker in $CURRENT_HYPR: existing files will be replaced (no backup was created)."
        fi
    fi
    copy_dir_files "$DEV_DIR/hypr_modular" "$CURRENT_HYPR" "$PRESERVE_HYPR"
    local hypr_manifest
    hypr_manifest=$(mktemp)
    (cd "$DEV_DIR/hypr_modular" && ls -1) > "$hypr_manifest"
    prune_target "$CURRENT_HYPR" "$hypr_manifest" "$PRESERVE_HYPR"
    rm -f "$hypr_manifest"
    chmod +x "$CURRENT_HYPR/"*.sh 2>/dev/null || true

    mkdir -p "$CORE_DIR"
    copy_dir_files "$DEV_DIR/core" "$CORE_DIR" "$PRESERVE_CORE"
    local core_manifest
    core_manifest=$(mktemp)
    (cd "$DEV_DIR/core" && ls -1) > "$core_manifest"
    prune_target "$CORE_DIR" "$core_manifest" "$PRESERVE_CORE"
    rm -f "$core_manifest"
    if [ ! -f "$CORE_DIR/secrets.json" ] && [ -f "$CORE_DIR/secrets.example.json" ]; then
        cp "$CORE_DIR/secrets.example.json" "$CORE_DIR/secrets.json"
    fi
    chmod +x "$CORE_DIR/"*.sh

    cp "$DEV_DIR/qmldir" "$QS_DIR/qmldir"
    cp "$DEV_DIR/Theme.qml" "$QS_DIR/Theme.qml"
    cp "$DEV_DIR/shell.qml" "$QS_DIR/shell.qml"
    cp "$DEV_DIR/main.qml" "$QS_DIR/main.qml"
    cp "$DEV_DIR/island_left.qml" "$QS_DIR/island_left.qml"
    cp "$DEV_DIR/island_center.qml" "$QS_DIR/island_center.qml"
    cp "$DEV_DIR/island_right.qml" "$QS_DIR/island_right.qml"
    cp "$DEV_DIR/config_panel.qml" "$QS_DIR/config_panel.qml"
    cp "$DEV_DIR/CollapsibleSection.qml" "$QS_DIR/CollapsibleSection.qml"
    cp "$DEV_DIR/Stepper.qml" "$QS_DIR/Stepper.qml"

    local qs_manifest
    qs_manifest=$(mktemp)
    (cd "$DEV_DIR" && ls -1 *.qml qmldir 2>/dev/null) > "$qs_manifest"
    prune_target "$QS_DIR" "$qs_manifest"
    rm -f "$qs_manifest"

    if [ -d "$DEV_DIR/hyprquickpaper" ]; then
        mkdir -p "$QS_DIR/hyprquickpaper"
        if [ ! -f "$MARKER" ] || [ ! -f "$QS_DIR/hyprquickpaper/config.json" ] || [ "${DEPLOY_OVERWRITE:-0}" = "1" ]; then
            cp "$DEV_DIR/hyprquickpaper/config.json" "$QS_DIR/hyprquickpaper/config.json"
        else
            sync_file "$DEV_DIR/hyprquickpaper/config.json" "$QS_DIR/hyprquickpaper/config.json"
        fi
        cp "$DEV_DIR/hyprquickpaper/colors.json" "$QS_DIR/hyprquickpaper/colors.json"
        cp "$DEV_DIR/hyprquickpaper/shell.qml" "$QS_DIR/hyprquickpaper/shell.qml"
        cp "$DEV_DIR/hyprquickpaper/cache.sh" "$QS_DIR/hyprquickpaper/cache.sh"
        cp "$DEV_DIR/hyprquickpaper/commands.sh" "$QS_DIR/hyprquickpaper/commands.sh"
        chmod +x "$QS_DIR/hyprquickpaper/cache.sh" "$QS_DIR/hyprquickpaper/commands.sh"
    fi

    "$CORE_DIR/generate_rofi_theme.sh"

    touch "$MARKER"

    echo "✅ Station deployment complete! Please restart Hyprland or reload config."
}

while true; do
    echo "------------------------------------------"
    echo " STATION - ENVIRONMENT MANAGER (ARCH)"
    echo "------------------------------------------"
    echo "1 > Deploy & Switch to Station Quickshell"
    echo "2 > Backup current environment"
    echo "3 > Restore HN (Hyprland + Noctalia)"
    echo "4 > Restore HQ (Hyprland + Quickshell)"
    echo "q > Quit"
    echo "------------------------------------------"
    read -p "Choice: " choice

    case $choice in
        1)
            if check_dependencies; then
                [ "${BACKUP_OK:-0}" = "1" ] || backup_env
                deploy_new_env
                exit 0
            fi
            ;;
        2) backup_env ;;
        3)
            tar -xzf "$BACKUP_DIR/backup_station_hn.tar.gz" -C "$HOME/.config" && rm -f "$MARKER"
            echo "✅ HN (Hyprland + Noctalia) restored."
            exit 0
            ;;
        4)
            rm -f "$MARKER"
            tar -xzf "$BACKUP_DIR/backup_station_hq.tar.gz" -C "$HOME/.config"
            echo "✅ HQ (Hyprland + Quickshell) restored."
            exit 0
            ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
done
