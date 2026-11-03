#!/bin/bash
# Wrapper pour le déploiement unifié sur Station (Arch Linux Desktop)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/deploy.sh" --station "$@"
