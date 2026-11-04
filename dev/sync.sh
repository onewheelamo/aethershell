#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Script de synchronisation bidirectionnelle du dossier de développement
# Neutre vis-à-vis des machines (Portable <-> Station ou toute autre machine)
# ══════════════════════════════════════════════════════════════════════════════
# Usage:
#   bash dev/sync.sh --push            # Envoi : Local  -> Distant (défaut)
#   bash dev/sync.sh --pull            # Récupération : Distant -> Local
#   bash dev/sync.sh --push --dry-run  # Simulation (affiche sans transférer)
#   bash dev/sync.sh --push --delete   # Propage les suppressions
#   bash dev/sync.sh --host 192.0.2.11 # Surcharge de l'adresse de la machine distante
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Résolution du chemin réel (même si appelé depuis un lien symbolique)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Détection de l'hôte local et attribution de la cible distante par défaut
LOCAL_HOST="$(cat /etc/hostname 2>/dev/null || uname -n 2>/dev/null || true)"
LOCAL_HOST="$(echo "$LOCAL_HOST" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"

# Adresses des deux machines (surchargables par l'environnement : même dépôt
# déployé ailleurs sans réécrire le script).
PORTABLE_HOST="${SYNC_PORTABLE_HOST:-192.0.2.10}"
STATION_HOST="${SYNC_STATION_HOST:-192.0.2.11}"

if [[ "$LOCAL_HOST" =~ portable ]]; then
    DEFAULT_REMOTE_HOST="$STATION_HOST" # Station (Desktop)
    DEFAULT_REMOTE_NAME="Station (Desktop)"
elif [[ "$LOCAL_HOST" =~ station ]]; then
    DEFAULT_REMOTE_HOST="$PORTABLE_HOST" # Portable (Laptop)
    DEFAULT_REMOTE_NAME="Portable (Laptop)"
else
    DEFAULT_REMOTE_HOST="$STATION_HOST"
    DEFAULT_REMOTE_NAME="Machine distante"
fi

# Adresse de la machine courante, pour refuser un envoi vers soi-même.
LOCAL_ADDR=""
if [[ "$LOCAL_HOST" =~ portable ]]; then
    LOCAL_ADDR="$PORTABLE_HOST"
elif [[ "$LOCAL_HOST" =~ station ]]; then
    LOCAL_ADDR="$STATION_HOST"
fi

REMOTE_HOST="${SYNC_REMOTE_HOST:-$DEFAULT_REMOTE_HOST}"
REMOTE_NAME="$DEFAULT_REMOTE_NAME"
REMOTE_USER="${SYNC_REMOTE_USER:-$USER}"
REMOTE_DIR="${SYNC_REMOTE_DIR:-~/dev/quickshell_todo}"

DIRECTION="push"
DRY_RUN=""
EXTRA_ARGS=()

# 2. Analyse des arguments CLI
while [ $# -gt 0 ]; do
    case "$1" in
        --portable)
            REMOTE_HOST="$PORTABLE_HOST"
            REMOTE_NAME="Portable (Laptop)"
            ;;
        --station)
            REMOTE_HOST="$STATION_HOST"
            REMOTE_NAME="Station (Desktop)"
            ;;
        --push|push)
            DIRECTION="push"
            ;;
        --pull|pull)
            DIRECTION="pull"
            ;;
        -n|--dry-run)
            DRY_RUN="1"
            EXTRA_ARGS+=("--dry-run")
            ;;
        --delete)
            EXTRA_ARGS+=("--delete")
            ;;
        --host|--target)
            shift
            REMOTE_HOST="${1:-}"
            ;;
        --user)
            shift
            REMOTE_USER="${1:-}"
            ;;
        --dir)
            shift
            REMOTE_DIR="${1:-}"
            ;;
        -h|--help)
            cat << 'HELP'
Script de synchronisation bidirectionnelle du code (rsync + SSH).

Syntaxe :
  bash dev/sync.sh [DIRECTION] [OPTIONS]

Directions :
  --push, push         Envoie les modifications locales vers la machine distante (défaut)
  --pull, pull         Récupère les modifications distantes vers la machine locale

Machines :
  --portable             Cible le laptop (192.0.2.10)
  --station          Cible le desktop (192.0.2.11)
  (sans option, la cible est l'autre machine, déduite du nom d'hôte local)

Options :
  -n, --dry-run        Mode simulation (aucun fichier modifié)
  --delete             Supprime les fichiers orphelins sur la destination
  --host <ip|nom>      Adresse IP ou hôte de la machine distante
  --user <nom>         Utilisateur SSH distant (défaut : utilisateur courant)
  --dir <chemin>       Chemin du dossier distant (défaut : ~/dev/quickshell_todo)
  -h, --help           Affiche cette aide
HELP
            exit 0
            ;;
        -*)
            echo "❌ Option inconnue : $1" >&2
            echo "   Voir --help." >&2
            exit 2
            ;;
        *)
            echo "❌ Argument inconnu : $1" >&2
            echo "   Voir --help." >&2
            exit 2
            ;;
    esac
    shift
done

[ -n "$REMOTE_HOST" ] || { echo "❌ Erreur : Hôte distant non spécifié." >&2; exit 1; }
if [ -n "$LOCAL_ADDR" ] && [ "$REMOTE_HOST" = "$LOCAL_ADDR" ]; then
    echo "❌ Erreur : $REMOTE_HOST est cette machine ($LOCAL_HOST), rien à synchroniser." >&2
    exit 1
fi

echo "══════════════════════════════════════════════════════════════════"
if [ "$DIRECTION" = "push" ]; then
    echo "▶ SYNCHRONISATION : LOCAL ($LOCAL_HOST) ➜ DISTANT ($REMOTE_USER@$REMOTE_HOST)"
    SRC="$PROJECT_ROOT/"
    DST="$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
else
    echo "◀ SYNCHRONISATION : DISTANT ($REMOTE_USER@$REMOTE_HOST) ➜ LOCAL ($LOCAL_HOST)"
    SRC="$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"
    DST="$PROJECT_ROOT/"
fi
echo "  Machine cible   : $REMOTE_NAME"
echo "  Dossier local   : $PROJECT_ROOT"
echo "  Dossier distant : $REMOTE_DIR"
[ -n "$DRY_RUN" ] && echo "  Mode simulation : ACTIF (--dry-run, aucun fichier écrit)"
echo "══════════════════════════════════════════════════════════════════"

# 3. Test de connectivité SSH rapide
echo -n "Vérification de la liaison SSH vers $REMOTE_HOST... "
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=3 "$REMOTE_USER@$REMOTE_HOST" exit 2>/dev/null; then
    echo "ÉCHEC ❌"
    echo "Erreur : Impossible de joindre $REMOTE_USER@$REMOTE_HOST via SSH." >&2
    echo "Assurez-vous que la machine est allumée et que le serveur SSH est actif." >&2
    exit 1
fi
echo "OK ✓"

# 4. Exécution de rsync
rsync -avzh --progress \
    --exclude=".git/" \
    --exclude="__pycache__/" \
    --exclude="*.pyc" \
    --exclude="*.swp" \
    --exclude="*~" \
    --exclude=".DS_Store" \
    "${EXTRA_ARGS[@]}" \
    "$SRC" \
    "$DST"

echo
if [ -n "$DRY_RUN" ]; then
    echo "🔍 Simulation terminée (aucun transfert effectué)."
else
    echo "✅ Synchronisation ($DIRECTION) terminée avec succès."
fi
