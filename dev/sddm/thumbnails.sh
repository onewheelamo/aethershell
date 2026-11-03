#!/usr/bin/env bash
# Génère les miniatures du greeter : une capture 480×270 par configuration.
#
#   bash dev/sddm/thumbnails.sh               toutes les confs du thème
#   bash dev/sddm/thumbnails.sh palette       une seule
#
# Chaque conf est prévisualisée par sddm-greeter-qt6 en mode test, sur une copie
# jetable du thème (liens durs), puis capturée avec grim. Les fenêtres du greeter
# prennent l'écran quelques secondes : lancer la commande quand personne ne
# travaille dessus.

set -euo pipefail

THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
OUT="$HOME/.cache/quickshell/greeter-thumbs"
SIZE="480x270"

die() { echo "thumbnails.sh: $*" >&2; exit 1; }

[ -d "$THEME/Themes" ] || die "thème absent : $THEME"
command -v grim >/dev/null || die "grim requis"
command -v magick >/dev/null || die "magick requis"

mkdir -p "$OUT"

if [ "$#" -gt 0 ]; then
    ids=("$@")
else
    mapfile -t ids < <(find "$THEME/Themes" -maxdepth 1 -name '*.conf' -printf '%f\n' \
        | sed 's/\.conf$//' | sort)
fi

for id in "${ids[@]}"; do
    conf="$THEME/Themes/$id.conf"
    [ -f "$conf" ] || { echo "ignoré (conf absente) : $id"; continue; }

    # /usr est sur un autre système de fichiers que /home : les liens durs
    # échouent depuis TMPDIR, d'où /var/tmp (même volume, mktemp crée en 700).
    tmp="$(mktemp -d /var/tmp/greeter-thumb-XXXXXX)"
    # Liens durs impossibles (fichiers root, fs.protected_hardlinks=1) : copie
    # réelle, en reflink quand le volume est en copy-on-write.
    cp -a --reflink=auto "$THEME/." "$tmp/"
    # Le mode test suit metadata.desktop : on pointe la copie sur la conf voulue.
    sed -i "s|^ConfigFile=.*|ConfigFile=Themes/$id.conf|" "$tmp/metadata.desktop"

    QT_QPA_PLATFORM=wayland timeout 9 sddm-greeter-qt6 --test-mode --theme "$tmp" \
        >/dev/null 2>&1 &
    pid=$!
    sleep 4.5

    shot="$tmp/shot.png"
    if grim "$shot" 2>/dev/null; then
        magick "$shot" -resize "$SIZE" -quality 88 "$OUT/$id.png" 2>/dev/null
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
