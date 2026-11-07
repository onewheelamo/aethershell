#!/usr/bin/env bash
# Relance la barre d'une machine distante, après accord explicite.
#
# Rien ne s'exécute sans passer par le canal d'approbation : c'est le même
# mécanisme que pour n'importe quelle action d'agent (demande → toast + applet →
# verdict). Un clic dans le popup « flotte » ne doit pas pouvoir redémarrer le
# shell d'une autre machine en silence.
#
# Usage :
#   flotte_agir.sh <nom-de-machine> [--simuler]
set -uo pipefail

ICI="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
NOM="${1:-}"
SIMULER=0
[ "${2:-}" = "--simuler" ] && SIMULER=1

[ -n "$NOM" ] || { echo "usage : flotte_agir.sh <machine>" >&2; exit 2; }

CIBLE=$(python3 - "$ICI/flotte.json" "$NOM" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(""); raise SystemExit
for m in d.get("machines", []):
    if str(m.get("nom", "")).lower() == sys.argv[2].lower():
        print(m.get("cible", "")); raise SystemExit
print("")
PY
)
[ -n "$CIBLE" ] || { echo "machine inconnue : $NOM" >&2; exit 1; }

if [ "$SIMULER" = "1" ]; then
    echo "simulation : ssh $CIBLE 'systemctl --user restart quickshell'"
    exit 0
fi

# 1. Accord de l'utilisateur, par le canal existant. Le CLI bloque jusqu'au
#    verdict et sort en 0 seulement si l'accord est donné.
if ! python3 "$ICI/hermes_approbations.py" demander \
        "relancer la barre de $NOM" \
        --detail "systemctl --user restart quickshell sur $CIBLE" \
        --delai 120 >/dev/null 2>&1; then
    echo "refusé ou sans réponse : rien n'a été fait" >&2
    exit 1
fi

# 2. L'action, une fois l'accord obtenu.
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$CIBLE" \
       'export XDG_RUNTIME_DIR=/run/user/$(id -u); systemctl --user restart quickshell' 2>/dev/null; then
    echo "barre de $NOM relancée"
    exit 0
fi
echo "échec du redémarrage sur $NOM" >&2
exit 1
