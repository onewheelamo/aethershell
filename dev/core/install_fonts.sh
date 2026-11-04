#!/usr/bin/env bash
# Installation de la police 0xProto Nerd Font pour Quickshell
# Compatible Fedora / Arch / Debian

set -euo pipefail

FONT_NAME="0xProto Nerd Font"
FONT_DIR="$HOME/.local/share/fonts/0xProto"

if fc-list : family | grep -qi "0xproto"; then
    echo "✓ Police $FONT_NAME déjà installée."
    exit 0
fi

echo "▶ Téléchargement et installation de $FONT_NAME..."
mkdir -p "$FONT_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/0xProto.tar.xz"
if command -v curl >/dev/null 2>&1; then
    curl -fLo "$TMP/0xProto.tar.xz" "$URL"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP/0xProto.tar.xz" "$URL"
else
    echo "❌ Ni curl ni wget disponibles pour télécharger la police." >&2
    exit 1
fi

tar -xf "$TMP/0xProto.tar.xz" -C "$FONT_DIR"
fc-cache -f "$FONT_DIR"

if fc-list : family | grep -qi "0xproto"; then
    echo "✅ $FONT_NAME installée avec succès dans $FONT_DIR."
else
    echo "⚠️ Police extraite mais non reconnue par fontconfig."
fi
