#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# TARGET CLEANUP SCRIPT (clean_targets.sh)
# ══════════════════════════════════════════════════════════════════════════════
# Usage:
#   ./dev/clean_targets.sh            -> Dry-run (lists files without removing)
#   ./dev/clean_targets.sh --apply    -> Archives and removes tier 1 + tier 3
#   ./dev/clean_targets.sh --apply --maybe -> Also archives and removes tier 2
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

DRY=1
INCLUDE_MAYBE=0

for arg in "$@"; do
    case "$arg" in
        --apply) DRY=0 ;;
        --maybe) INCLUDE_MAYBE=1 ;;
        -h|--help)
            echo "Usage: $0 [--apply] [--maybe]"
            exit 0
            ;;
    esac
done

STAMP="$(date +'%Y%m%d_%H%M%S')"
ARC="$HOME/.config/backups_env/clean_$STAMP"
QS="$HOME/.config/quickshell"
HY="$HOME/.config/hypr"

# Tier 1 : Sûrs (aucune référence, aucun rôle runtime)
SAFE=(
    "$QS/ThemeColors.qml"
    "$HY/portable.lua"
    "$HY/station.lua"
    "$HY/hardwareconfig.lua"
    "$HY/keybindings.lua"
    "$HY/keybindings.lua.bak"
    "$HY/hyprland.conf.old"
    "$HY/hyprland.lua.old"
    "$HOME/.config/rofi/config.rasi.old"
)

# Wildcards for backups and swap files
shopt -s nullglob
SAFE+=( "$HY"/hyprland.lua.mod-backup-* )
SAFE+=( "$HY"/hyprland.lua.quickshell-backup-* )
SAFE+=( "$HY"/.hyprland.conf.kate-swp )
SAFE+=( "$HY"/.hyprland.lua.kate-swp )
SAFE+=( "$HY"/scripts )
SAFE+=( "$HY"/shaders )
shopt -u nullglob

# Tier 2 : À confirmer (outils manuels / legacy)
MAYBE=(
    "$HY/rotate.sh"
    "$HY/sync_to_portable.sh"
    "$HY/sync_to_station.sh"
)

# Tier 3 : Artefacts de build et caches
BUILD=(
    "$QS/core/fuzzel.ini"
    "$QS/core/rofi_config.rasi"
    "$QS/core/__pycache__"
)

do_rm() {
    for p in "$@"; do
        [ -e "$p" ] || continue
        if [ "$DRY" -eq 1 ]; then
            echo "  [dry-run] rm $p"
        else
            echo "  [archive & rm] $p"
            mkdir -p "$ARC"
            if cp -a "$p" "$ARC/"; then
                rm -rf "$p"
            else
                echo "  ⚠️  archive impossible — $p conservé" >&2
            fi
        fi
    done
}

echo "=== TIER 1 (Fichiers morts & anciennes sauvegardes) ==="
do_rm "${SAFE[@]}"

echo "=== TIER 3 (Artefacts de build & caches dans core) ==="
do_rm "${BUILD[@]}"

if [ "$INCLUDE_MAYBE" -eq 1 ]; then
    echo "=== TIER 2 (Scripts legacy hôte) ==="
    do_rm "${MAYBE[@]}"
else
    echo "=== TIER 2 ignoré (utilisez --maybe pour inclure ${MAYBE[*]}) ==="
fi

# Gestion des fichiers .new résiduels
shopt -s nullglob
NEW_FILES=( "$HY"/*.new "$QS"/core/*.new "$QS"/hyprquickpaper/*.new )
shopt -u nullglob

if [ "${#NEW_FILES[@]}" -gt 0 ]; then
    echo "=== Fichiers *.new détectés (${#NEW_FILES[@]}) ==="
    for nf in "${NEW_FILES[@]}"; do
        # Les copies de secrets ne sont jamais archivées : suppression directe.
        if [ "$(basename "$nf")" = "secrets.json.new" ]; then
            if [ "$DRY" -eq 1 ]; then
                echo "  [dry-run] rm (secret, non archivé) $nf"
            else
                echo "  [rm] $nf (copie de secret, non archivée)"
                rm -f "$nf"
            fi
            continue
        fi
        if [ "$DRY" -eq 1 ]; then
            echo "  [dry-run] archiver & supprimer $nf"
        else
            echo "  [archive & rm] $nf"
            mkdir -p "$ARC/new_files"
            if mv "$nf" "$ARC/new_files/"; then
                :
            else
                echo "  ⚠️  déplacement impossible — $nf conservé" >&2
            fi
        fi
    done
fi

# Nettoyage dépôt git orphelin dans ~/.config/quickshell
if [ -d "$QS/.git" ]; then
    if [ "$DRY" -eq 1 ]; then
        echo "  [dry-run] rm -rf $QS/.git (dépôt vide sans commit)"
    else
        echo "  [rm] $QS/.git"
        rm -rf "$QS/.git"
    fi
fi

if [ "$DRY" -eq 1 ]; then
    echo ""
    echo "💡 Mode simulation terminé. Pour appliquer réellement les suppressions :"
    echo "   $0 --apply [--maybe]"
else
    echo ""
    echo "✅ Nettoyage terminé ! Éléments archivés dans : $ARC"
fi

