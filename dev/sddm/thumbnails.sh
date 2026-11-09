#!/usr/bin/env bash
# Génère les miniatures du greeter : une capture 480×270 par thème.
#
#   bash dev/sddm/thumbnails.sh              tout ce que le panneau liste
#   bash dev/sddm/thumbnails.sh palette      une seule configuration
#   bash dev/sddm/thumbnails.sh nothing      un thème qylock
#
# Le panneau liste deux familles : les configurations du thème astronaut
# (couleurs/police dans Themes/*.conf) et les thèmes complets récupérés par
# dev/sddm/qylock.py (un dossier QML autonome, miniatures lues dans le cache
# ou dans /usr/share). core/greeter_manager.py `sources` donne la liste —
# c'est lui qui décide de l'identifiant affiché, donc les noms de fichiers ici
# correspondent exactement à ceux que le panneau cherche.
#
# Chaque thème est prévisualisé par sddm-greeter-qt6 en mode test, sur une copie
# jetable, puis capturé avec grim. Les fenêtres du greeter prennent l'écran
# quelques secondes : lancer la commande quand personne ne travaille dessus.

set -euo pipefail

DEV="$(cd "$(dirname "$0")/.." && pwd)"
THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
OUT="$HOME/.cache/quickshell/greeter-thumbs"
SIZE="480x270"

die() { echo "thumbnails.sh: $*" >&2; exit 1; }

[ -d "$THEME/Themes" ] || die "thème absent : $THEME"
command -v grim >/dev/null || die "grim requis"
command -v magick >/dev/null || die "magick requis"

mkdir -p "$OUT"

# sources : une ligne « id<TAB>dossier<TAB>astronaut|qylock » par thème.
mapfile -t rows < <(python3 "$DEV/core/greeter_manager.py" sources "$@")
[ "${#rows[@]}" -gt 0 ] || die "aucun thème à prévisualiser${*:+ : $*}"

for row in "${rows[@]}"; do
    IFS=$'\t' read -r id src kind <<< "$row"

    # /usr est sur un autre système de fichiers que /home : les liens durs
    # échouent depuis TMPDIR, d'où /var/tmp (même volume, mktemp crée en 700).
    tmp="$(mktemp -d /var/tmp/greeter-thumb-XXXXXX)"
    # Liens durs impossibles (fichiers root, fs.protected_hardlinks=1) : copie
    # réelle, en reflink quand le volume est en copy-on-write.
    cp -a --reflink=auto "$src/." "$tmp/"

    # Le mode test suit metadata.desktop. Un thème qylock n'a qu'une conf : sa
    # metadata la nomme déjà. Les confs astronaut partagent un dossier, c'est
    # donc la copie qu'on pointe sur celle que l'on veut capturer.
    if [ "$kind" = "astronaut" ]; then
        sed -i "s|^ConfigFile=.*|ConfigFile=Themes/$id.conf|" "$tmp/metadata.desktop"
    fi

    QT_QPA_PLATFORM=wayland timeout 9 sddm-greeter-qt6 --test-mode --theme "$tmp" \
        >/dev/null 2>&1 &
    pid=$!
    sleep 4.5

    shot="$tmp/shot.png"
    # Sur configuration multi-écrans, grim sans option capture l'ensemble du bureau
    # (ex: 3840×1080), produisant des miniatures écrasées et coupées en deux.
    # On cible explicitement l'écran focalisé où s'ouvre la fenêtre de test.
    OUT_MON="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null || true)"
    [ -z "$OUT_MON" ] && OUT_MON="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null || true)"
    GRIM_ARGS=()
    [ -n "$OUT_MON" ] && GRIM_ARGS=(-o "$OUT_MON")

    if grim "${GRIM_ARGS[@]}" "$shot" 2>/dev/null; then
        magick "$shot" -resize "$SIZE^" -gravity center -extent "$SIZE" -quality 88 "$OUT/$id.png" 2>/dev/null
        echo "miniature : $id → $OUT/$id.png"
    else
        echo "échec de capture pour $id" >&2
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
done

# Le panneau relit ce fichier pour dater les miniatures.
date +%s > "$OUT/.generated"
echo "terminé : $(find "$OUT" -maxdepth 1 -name '*.png' | wc -l) miniature(s)"
