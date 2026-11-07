#!/bin/sh
# Compile core/pwscope.c dans le cache de la session, et rend le chemin.
#
# Pourquoi compiler ici plutôt qu'au déploiement : le binaire dépend des
# en-têtes PipeWire de la machine, pas du dépôt. Le cache évite de recompiler à
# chaque relance du shell ; la comparaison de dates évite de garder un binaire
# qui ne correspond plus au source.
#
# Ne compile que si nécessaire, se tait quand tout va bien (le shell lit la
# première ligne = chemin du binaire), et parle sur stderr en cas d'échec :
# l'appelant décide alors de ne rien afficher, jamais de casser la barre.
set -u

ICI=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$ICI/pwscope.c"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
BIN="$CACHE/pwscope"

[ -f "$SRC" ] || { echo "source absente : $SRC" >&2; exit 2; }
mkdir -p "$CACHE" || exit 3

if [ -x "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then
    printf '%s\n' "$BIN"
    exit 0
fi

command -v cc >/dev/null 2>&1 || { echo "cc absent (outils de compilation)" >&2; exit 4; }
if ! pkg-config --exists libpipewire-0.3 2>/dev/null; then
    echo "en-têtes libpipewire-0.3 absents (pkg-config)" >&2
    exit 5
fi

TMP="$BIN.tmp.$$"
# shellcheck disable=SC2046
if ! cc -O2 -Wall -Wextra -Wno-unused-parameter -std=gnu11 \
        $(pkg-config --cflags libpipewire-0.3) \
        -o "$TMP" "$SRC" \
        $(pkg-config --libs libpipewire-0.3) -lm; then
    rm -f "$TMP"
    echo "échec de compilation de pwscope.c" >&2
    exit 6
fi
mv -f "$TMP" "$BIN" || { rm -f "$TMP"; exit 7; }
printf '%s\n' "$BIN"
