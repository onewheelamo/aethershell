#!/bin/bash
# Installe l'action polkit et le helper de la limite de charge. Root requis :
#
#   sudo bash dev/charge-limit/install.sh
#
# Appelé par deploy.sh à travers pkexec, et **idempotent** : chaque fichier est
# comparé avant d'être posé, donc une machine déjà à jour ne demande aucune
# élévation et n'écrit rien. C'est ce qui évite une invite polkit à chaque
# déploiement.
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" = "0" ] || {
    echo "install.sh : root requis (sudo bash $ICI/install.sh)" >&2
    exit 3
}

change=0

poser() { # poser SRC DEST MODE
    local src="$1" dst="$2" mode="$3"
    if [ -f "$dst" ] && cmp -s "$src" "$dst" && [ "$(stat -c %a "$dst")" = "$mode" ]; then
        return 0
    fi
    install -Dm"$mode" "$src" "$dst"
    echo "  ↪ installé : $dst"
    change=1
}

poser "$ICI/aether-charge-limit" /usr/local/bin/aether-charge-limit 755
poser "$ICI/org.aethershell.charge.policy" \
      /usr/share/polkit-1/actions/org.aethershell.charge.policy 644
poser "$ICI/50-aethershell-charge.rules" \
      /etc/polkit-1/rules.d/50-aethershell-charge.rules 644

if [ "$change" = "1" ]; then
    # polkitd surveille ses dossiers de règles et d'actions : rien à redémarrer.
    echo "  ✓ limite de charge : action org.aethershell.charge.limit en place"
else
    echo "  ✓ limite de charge : déjà à jour"
fi
