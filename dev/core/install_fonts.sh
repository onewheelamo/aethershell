#!/usr/bin/env bash
# Installation de la police 0xProto Nerd Font pour Quickshell
# Compatible Fedora / Arch / Debian

set -euo pipefail

FONT_NAME="0xProto Nerd Font"
FONT_DIR="$HOME/.local/share/fonts/0xProto"

# Le test doit éviter `grep -q` : sous `set -o pipefail`, grep -q sort au premier
# match, fc-list reçoit SIGPIPE et le pipeline rend 141 — le script conclut alors
# que la police manque et la retélécharge à chaque déploiement (2,16 Mo).
# `grep ... >/dev/null` lit tout le flux et laisse le pipeline en 0.
if fc-list : family 2>/dev/null | grep -i "0xproto" >/dev/null; then
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

if fc-list : family 2>/dev/null | grep -i "0xproto" >/dev/null; then
    echo "✅ $FONT_NAME installée avec succès dans $FONT_DIR."
else
    echo "⚠️ Police extraite mais non reconnue par fontconfig."
fi
