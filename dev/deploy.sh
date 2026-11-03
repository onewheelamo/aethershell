#!/bin/bash
# Unified Environment Deployer & Manager (Arch Linux / Fedora)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "    QUICKSHELL ENVIRONMENT DEPLOYER"
echo "=========================================="
echo "Sélectionnez votre distribution cible :"
echo "1 > Arch Linux (Tour / Station - pacman)"
echo "2 > Fedora Linux (Laptop / Portable - dnf)"
echo "q > Quitter"
echo "=========================================="
read -p "Votre choix (1 ou 2) : " distro_choice

case "$distro_choice" in
    1)
        exec "$SCRIPT_DIR/deploy_station.sh"
        ;;
    2)
        exec "$SCRIPT_DIR/deploy_portable.sh"
        ;;
    q|Q)
        echo "Déploiement annulé."
        exit 0
        ;;
    *)
        echo "Option invalide. Veuillez relancer et taper 1 ou 2."
        exit 1
        ;;
esac
