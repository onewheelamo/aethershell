#!/usr/bin/env bash
# Installe le thème de connexion de la session : sddm-astronaut re-coloré depuis
# style_vars.json, avec le wallpaper courant assombri.
#
#   bash dev/sddm/install.sh              installation complète (une invite polkit)
#   bash dev/sddm/install.sh --colors-only # palette + fond seuls, après un changement
#   bash dev/sddm/install.sh --qylock <nom…> # thèmes qylock récupérés (qylock.py)
#   ASK_SUDO=1 bash dev/sddm/install.sh   # machine sans agent polkit (sudo à la place)
#
# Prérequis : le thème sddm-astronaut installé dans /usr/share/sddm/themes/.
#   Arch   : yay -S sddm-astronaut-theme   (ou pacman -U du paquet construit à la main)
#   Fedora : pas d'AUR — cloner https://github.com/Keyitdev/sddm-astronaut-theme
#            dans /usr/share/sddm/themes/sddm-astronaut-theme
# La police Inter doit exister : le thème la demande explicitement
#   Arch : inter-font        Fedora : rsms-inter-fonts
# La taille du greeter suit l'écran focalisé (hyprctl) ; hors session,
# forcer avec GREETER_SCREEN=WxH.

set -euo pipefail

DEV="$(cd "$(dirname "$0")" && pwd)"
THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
CONFD="/etc/sddm.conf.d"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$HOME/.config/backups_env/sddm_$STAMP"
MODE="full"
[ "${1:-}" = "--colors-only" ] && MODE="colors"

# pkexec suppose un agent polkit dans la session. Sur une machine qui n'en a pas
# (session fraîchement installée, session lancée par ssh), ASK_SUDO=1 passe par
# sudo : même script root, une invite en terminal au lieu d'une boîte de dialogue.
RUNNER="pkexec"
[ "${ASK_SUDO:-0}" = "1" ] && RUNNER="sudo"

die() { echo "install.sh: $*" >&2; exit 1; }

# --qylock : installe dans /usr/share/sddm/themes des thèmes récupérés par
# dev/sddm/qylock.py. Ne touche pas à la sélection courante — le panneau
# (onglet Connexion) le fait ensuite par le helper polkit. Les variantes d'un
# même thème (clockwork en contient trois) sont aplaties en <thème>-<variante> :
# SDDM ne sait nommer qu'un dossier de premier niveau dans Current=.
if [ "${1:-}" = "--qylock" ]; then
    shift
    [ "$#" -gt 0 ] || die "aucun thème nommé (bash dev/sddm/install.sh --qylock <nom…>)"
    QCACHE="$HOME/.local/share/qylock-themes"
    QSTAGE="$(mktemp -d)"
    trap 'rm -rf "$QSTAGE"' EXIT
    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        # Le helper et sa règle polkit : sans eux le panneau ne peut pas
        # sélectionner un thème complet (l'ancienne version ne connaissait que
        # les confs astronaut). Réinstallés à chaque fois pour rester alignés
        # sur le dépôt.
        echo "install -Dm755 '$DEV/greeter-palette' /usr/local/bin/greeter-palette"
        echo "install -Dm644 '$DEV/50-greeter-palette.rules' /etc/polkit-1/rules.d/50-greeter-palette.rules"
        for name in "$@"; do
            src="$QCACHE/$name"
            [ -d "$src" ] || die "thème non récupéré : $name (python3 dev/sddm/qylock.py fetch $name)"
            for sub in "$src"/*/; do
                [ -f "$sub/metadata.desktop" ] || continue
                dst="$name-$(basename "${sub%/}")"
                echo "rm -rf '/usr/share/sddm/themes/$dst'"
                echo "cp -a '${sub%/}' '/usr/share/sddm/themes/$dst'"
                echo "chown -R root:root '/usr/share/sddm/themes/$dst'"
            done
            if [ -f "$src/metadata.desktop" ]; then
                echo "rm -rf '/usr/share/sddm/themes/$name'"
                echo "cp -a '$src' '/usr/share/sddm/themes/$name'"
                echo "chown -R root:root '/usr/share/sddm/themes/$name'"
            fi
        done
    } > "$QSTAGE/root.sh"
    bash -n "$QSTAGE/root.sh" || die "script root invalide"
    echo "▶ installation des thèmes qylock (une invite $RUNNER)"
    "$RUNNER" bash "$QSTAGE/root.sh"
    echo
    echo "thèmes présents dans /usr/share/sddm/themes :"
    ls -1d /usr/share/sddm/themes/*/ 2>/dev/null | sed 's|.*/themes/||; s|/$||; s|^|  |'
    echo "(sélection : panneau → Connexion, ou greeter_manager.py apply <nom>)"
    exit 0
fi

if [ ! -d "$THEME" ]; then
    if command -v dnf >/dev/null; then
        die "thème absent : pas d'AUR sur Fedora — cloner https://github.com/Keyitdev/sddm-astronaut-theme dans $THEME, puis relancer"
    fi
    die "thème absent : installer sddm-astronaut-theme (AUR : yay -S, ou pacman -U du paquet construit à la main)"
fi
[ -f "$DEV/generate.py" ] || die "generate.py introuvable"

# La police est demandée en dur par palette.conf (Font="Inter") : sans elle le
# thème se rabat sur une autre fonte, sans message. fc-match plutôt que
# `fc-list | grep -q` : sous `pipefail`, grep sort au premier succès et le
# SIGPIPE de fc-list fait échouer le pipeline (faux « police absente »).
case "$(fc-match -f '%{family}' Inter 2>/dev/null || true)" in
    Inter*) : ;;
    *)
        echo "⚠ police Inter absente : le thème retombera sur une autre fonte" >&2
        command -v pacman >/dev/null && echo "  Arch   : sudo pacman -S inter-font" >&2
        command -v dnf    >/dev/null && echo "  Fedora : sudo dnf install rsms-inter-fonts" >&2
        ;;
esac

echo "▶ génération depuis style_vars.json"
python3 "$DEV/generate.py"
[ -f "$DEV/out/Themes/palette.conf" ] || die "palette.conf non généré"
[ -f "$DEV/out/Backgrounds/wallpaper.png" ] || die "fond non généré"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

{
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo "mkdir -p '$BACKUP'"
    # Helper privilégié + règle polkit : le panneau peut alors changer de thème
    # ou rafraîchir la palette sans invite (programme root, non modifiable).
    echo "install -Dm755 '$DEV/greeter-palette' /usr/local/bin/greeter-palette"
    echo "install -Dm644 '$DEV/50-greeter-palette.rules' /etc/polkit-1/rules.d/50-greeter-palette.rules"
    echo "install -Dm644 '$DEV/out/Themes/palette.conf' '$THEME/Themes/palette.conf'"
    echo "install -Dm644 '$DEV/out/Backgrounds/wallpaper.png' '$THEME/Backgrounds/wallpaper.png'"
    # Reprise d'un renommage : la nomenclature précédente portait le nom de
    # l'hôte du laptop, on retire les artefacts qu'elle a laissés.
    echo "rm -f /usr/local/bin/portable-greeter /etc/polkit-1/rules.d/50-portable-greeter.rules '$THEME/Themes/portable.conf' '$THEME/Backgrounds/portable.png'"
    if [ "$MODE" = "full" ]; then
        # Sauvegarde puis neutralisation des Current= locaux : sans ça trois
        # fichiers se contredisent et l'ordre lexical décide du thème affiché.
        echo "cp -n '$THEME/metadata.desktop' '$BACKUP/metadata.desktop'"
        echo "sed -i 's|^ConfigFile=.*|ConfigFile=Themes/palette.conf|' '$THEME/metadata.desktop'"
        echo "mkdir -p '$CONFD'"
        for f in "$CONFD"/*.conf; do
            [ -e "$f" ] || continue
            [ "$(basename "$f")" = "10-sddm-theme.conf" ] && continue
            echo "cp -n '$f' '$BACKUP/$(basename "$f")' 2>/dev/null || true"
            echo "sed -i 's|^Current=|# désactivé par dev/sddm/install.sh — Current=|' '$f'"
        done
        # Fedora garde son Current=breeze dans /etc/sddm.conf, hors de conf.d :
        # sans cette ligne deux Current= cohabitent après l'installation.
        if [ -f /etc/sddm.conf ] && grep -q '^Current=' /etc/sddm.conf; then
            echo "cp -n '/etc/sddm.conf' '$BACKUP/sddm.conf' 2>/dev/null || true"
            echo "sed -i 's|^Current=|# désactivé par dev/sddm/install.sh — Current=|' '/etc/sddm.conf'"
        fi
        # Nomenclature précédente : supprimée après sauvegarde, sinon SDDM lit
        # deux Current= et l'ordre lexical décide.
        echo "rm -f '$CONFD/10-portable.conf'"
        echo "cat > '$CONFD/10-sddm-theme.conf' <<'CONF'"
        echo '[Theme]'
        echo 'Current=sddm-astronaut-theme'
        echo 'CONF'
    fi
} > "$STAGE/root.sh"

echo "▶ installation (une invite $RUNNER)"
"$RUNNER" bash "$STAGE/root.sh"

echo
echo "thème   : $THEME/Themes/palette.conf"
echo "fond    : $THEME/Backgrounds/wallpaper.png"
[ "$MODE" = "full" ] && echo "sélect. : $CONFD/10-sddm-theme.conf (Current=sddm-astronaut-theme)"
echo "sauveg. : $BACKUP"
echo
echo "test    : QT_QPA_PLATFORM=wayland sddm-greeter-qt6 --test-mode --theme $THEME  (Échap pour fermer ; la connexion y est désactivée)"
