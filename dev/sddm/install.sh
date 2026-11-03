#!/usr/bin/env bash
# Installe le thème de connexion portable : sddm-astronaut re-coloré depuis
# style_vars.json, avec le wallpaper courant assombri.
#
#   bash dev/sddm/install.sh              installation complète (une invite polkit)
#   bash dev/sddm/install.sh --colors-only # palette + fond seuls, après un changement
#
# Prérequis : paquet sddm-astronaut-theme installé (AUR).
#   yay -S sddm-astronaut-theme      (ou pacman -U du paquet construit à la main)

set -euo pipefail

DEV="$(cd "$(dirname "$0")" && pwd)"
THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
CONFD="/etc/sddm.conf.d"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$HOME/.config/backups_env/sddm_$STAMP"
MODE="full"
[ "${1:-}" = "--colors-only" ] && MODE="colors"

die() { echo "install.sh: $*" >&2; exit 1; }

[ -d "$THEME" ] || die "thème absent : installer le paquet sddm-astronaut-theme (AUR)"
[ -f "$DEV/generate.py" ] || die "generate.py introuvable"

echo "▶ génération depuis style_vars.json"
python3 "$DEV/generate.py"
[ -f "$DEV/out/Themes/portable.conf" ] || die "portable.conf non généré"
[ -f "$DEV/out/Backgrounds/portable.png" ] || die "fond non généré"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

{
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo "mkdir -p '$BACKUP'"
    # Helper privilégié + règle polkit : le panneau peut alors changer de thème
    # ou rafraîchir la palette sans invite (programme root, non modifiable).
    echo "install -Dm755 '$DEV/portable-greeter' /usr/local/bin/portable-greeter"
    echo "install -Dm644 '$DEV/50-portable-greeter.rules' /etc/polkit-1/rules.d/50-portable-greeter.rules"
    echo "install -Dm644 '$DEV/out/Themes/portable.conf' '$THEME/Themes/portable.conf'"
    echo "install -Dm644 '$DEV/out/Backgrounds/portable.png' '$THEME/Backgrounds/portable.png'"
    if [ "$MODE" = "full" ]; then
        # Sauvegarde puis neutralisation des Current= locaux : sans ça trois
        # fichiers se contredisent et l'ordre lexical décide du thème affiché.
        echo "cp -n '$THEME/metadata.desktop' '$BACKUP/metadata.desktop'"
        echo "sed -i 's|^ConfigFile=.*|ConfigFile=Themes/portable.conf|' '$THEME/metadata.desktop'"
        echo "mkdir -p '$CONFD'"
        for f in "$CONFD"/*.conf; do
            [ -e "$f" ] || continue
            [ "$(basename "$f")" = "10-portable.conf" ] && continue
            echo "cp -n '$f' '$BACKUP/$(basename "$f")'"
            echo "sed -i 's|^Current=|# désactivé par dev/sddm/install.sh — Current=|' '$f'"
        done
        echo "cat > '$CONFD/10-portable.conf' <<'CONF'"
        echo '[Theme]'
        echo 'Current=sddm-astronaut-theme'
        echo 'CONF'
    fi
} > "$STAGE/root.sh"

echo "▶ installation (une invite polkit)"
pkexec bash "$STAGE/root.sh"

echo
echo "thème   : $THEME/Themes/portable.conf"
echo "fond    : $THEME/Backgrounds/portable.png"
[ "$MODE" = "full" ] && echo "sélect. : $CONFD/10-portable.conf (Current=sddm-astronaut-theme)"
echo "sauveg. : $BACKUP"
echo
echo "test    : QT_QPA_PLATFORM=wayland sddm-greeter-qt6 --test-mode --theme $THEME"
