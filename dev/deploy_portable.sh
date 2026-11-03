#!/bin/bash
# Wrapper pour le déploiement unifié sur Portable (Fedora Laptop)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/deploy.sh" --portable "$@"
