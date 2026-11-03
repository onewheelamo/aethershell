#!/usr/bin/env bash
# Thumbnail cache generator for the wallpaper selector.
# Reads config.json from the given project dir (arg $1), expands $HOME
# manually (no envsubst needed), and writes flat thumbnails (basename only)
# into the cache dir. Static images only: jpg / jpeg / png / webp.

set -u

CONFIG_DIR="${1:-$(dirname "$0")}"
CONFIG="$CONFIG_DIR/config.json"

expand_home() {
    case "$1" in
        '$HOME')        printf '%s\n' "$HOME" ;;
        '$HOME/'*)      printf '%s/%s\n' "$HOME" "${1#'$HOME/'}" ;;
        '~')            printf '%s\n' "$HOME" ;;
        '~/'*)          printf '%s/%s\n' "$HOME" "${1#'~/'}" ;;
        *)              printf '%s\n' "$1" ;;
    esac
}

if [ ! -f "$CONFIG" ]; then
    echo "cache.sh: config not found: $CONFIG" >&2
    exit 1
fi

wallpaper_path=$(expand_home "$(jq -r '.wallpaper_path // empty' "$CONFIG")")
cache_path=$(expand_home "$(jq -r '.cache_path // empty' "$CONFIG")")
batch_size=$(jq -r '.cache_batch_size // 20' "$CONFIG")

[ -z "$wallpaper_path" ] && wallpaper_path="$HOME/Images/wallpapers/"
[ -z "$cache_path" ] && cache_path="$HOME/.cache/quickshell/hyprquickpaper/"

# normalize trailing slashes: cache.sh appends filenames directly
wallpaper_path="${wallpaper_path%/}/"
cache_path="${cache_path%/}/"

if [ ! -d "$wallpaper_path" ]; then
    echo "cache.sh: wallpaper dir does not exist: $wallpaper_path" >&2
    exit 0
fi

mkdir -p "$cache_path"

echo "Wallpaper path: $wallpaper_path"
echo "Cache path: $cache_path"

find "$wallpaper_path" -maxdepth 2 -type f \( \
    -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
\) | while IFS= read -r img; do
    filename=$(basename "$img")
    out="$cache_path$filename"

    # skip up-to-date thumbnails (newer than the source image)
    if [ -f "$out" ] && [ "$out" -nt "$img" ]; then
        continue
    fi

    echo "Generating thumbnail for $filename"
    magick "$img" -thumbnail x500 -strip -quality 85 "$out" &

    if [ "$batch_size" -gt 0 ] 2>/dev/null; then
        while [ "$(jobs -rp | wc -l)" -ge "$batch_size" ]; do
            wait -n
        done
    fi
done

wait
echo "Thumbnail generation complete."
