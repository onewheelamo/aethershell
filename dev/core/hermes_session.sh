#!/usr/bin/env bash
# Enveloppe une tâche Hermes pour que l'applet la voie vivre.
#
# Le shell lit un fichier d'état ; il faut donc que quelqu'un l'écrive aux bons
# moments. Ce script le fait autour d'une commande, sans que la tâche ait à s'en
# occuper :
#
#   hermes_session.sh "veille des prix" -- python3 ~/bin/veille.py
#   hermes_session.sh "revue des commits" --cron "revue quotidienne" -- git fetch
#
# Ordre des opérations, et pourquoi :
#   1. `debut` AVANT la commande — sinon l'applet affiche encore l'état précédent
#      pendant toute la durée de la tâche, c'est-à-dire exactement quand on la regarde ;
#   2. un `battement` toutes les 60 s — au-delà de cinq minutes sans écriture le
#      shell considère l'état comme périmé, et une tâche longue paraîtrait morte ;
#   3. `fin` avec le code de sortie réel, et la durée mesurée.
#
# Le code de sortie de la commande est rendu tel quel : envelopper ne doit jamais
# changer le verdict d'un script.
set -uo pipefail

PUBLIEUR="$(dirname "$(readlink -f "$0")")/hermes_publier.py"
[ -x "$PUBLIEUR" ] || PUBLIEUR="python3 $PUBLIEUR"

if [ $# -lt 3 ] || [ "$2" != "--" ] && [ "$2" != "--cron" ]; then
    cat >&2 <<'USAGE'
Usage :
  hermes_session.sh "<libellé>" -- <commande...>
  hermes_session.sh "<libellé>" --cron "<nom de la planification>" -- <commande...>
USAGE
    exit 2
fi

LIBELLE="$1"
shift
NOM_CRON=""
if [ "$1" = "--cron" ]; then
    NOM_CRON="${2:-}"
    shift 2
fi
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "hermes_session.sh : aucune commande à lancer" >&2; exit 2; }

# $PUBLIEUR peut contenir « python3 /chemin » : on le garde tel quel via un tableau.
read -r -a PUB <<< "$PUBLIEUR"

"${PUB[@]}" debut "$LIBELLE" >/dev/null 2>&1 || true

debut_s=$(date +%s)
( while sleep 60; do "${PUB[@]}" battement >/dev/null 2>&1 || true; done ) &
BATTEMENT=$!

"$@"
CODE=$?

kill "$BATTEMENT" 2>/dev/null || true
duree=$(( $(date +%s) - debut_s ))

if [ "$CODE" -eq 0 ]; then
    "${PUB[@]}" fin ok --duree "$duree" >/dev/null 2>&1 || true
    [ -n "$NOM_CRON" ] && "${PUB[@]}" cron "$NOM_CRON" \
        --dernier ok --quand "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
else
    "${PUB[@]}" fin echec --duree "$duree" --motif "code $CODE" >/dev/null 2>&1 || true
    [ -n "$NOM_CRON" ] && "${PUB[@]}" cron "$NOM_CRON" \
        --dernier echec --quand "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
fi

exit "$CODE"
