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
# « github » ne parle pas à l'autre machine : il parle au dépôt distant. Utile
# quand les deux machines ne sont pas allumées en même temps — c'est le cas dès
# qu'on travaille sur le portable puis sur le poste fixe.
GITHUB_PUSH=""
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
        --github|github)
            DIRECTION="github"
            ;;
        --github-push)
            DIRECTION="github"
            GITHUB_PUSH="1"
            ;;
        --force)
            FORCE="1"
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
  --github             Récupère depuis GitHub (git fetch + merge --ff-only)
  --github-push        Envoie sur GitHub (git push origin <branche>)

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
  --force              Avec --github : écrase les modifications locales non commitées
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

if [ "$DIRECTION" != "github" ]; then
[ -n "$REMOTE_HOST" ] || { echo "❌ Erreur : Hôte distant non spécifié." >&2; exit 1; }
fi
if [ "$DIRECTION" != "github" ] && [ -n "$LOCAL_ADDR" ] && [ "$REMOTE_HOST" = "$LOCAL_ADDR" ]; then
    echo "❌ Erreur : $REMOTE_HOST est cette machine ($LOCAL_HOST), rien à synchroniser." >&2
    exit 1
fi

# ── mode GitHub ─────────────────────────────────────────────────────────────
# Ce mode ne transfère que ce qui est *versionné*. Les fichiers gitignorés du
# projet (ce script, RESTE_A_FAIRE.md, dev/sync.sh) ne voyagent donc pas par ici :
# leur diffusion reste le rôle du mode rsync, quand les deux machines sont up.
if [ "$DIRECTION" = "github" ]; then
    cd "$PROJECT_ROOT" || exit 1
    BRANCHE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [ -n "$BRANCHE" ] || { echo "❌ Dépôt git introuvable dans $PROJECT_ROOT." >&2; exit 1; }

    echo "══════════════════════════════════════════════════════════════════"
    if [ -n "$GITHUB_PUSH" ]; then
        echo "▶ GITHUB : LOCAL ($LOCAL_HOST) ➜ origin/$BRANCHE"
    else
        echo "◀ GITHUB : origin/$BRANCHE ➜ LOCAL ($LOCAL_HOST)"
    fi
    echo "  Dépôt : $(git config --get remote.origin.url)"
    echo "══════════════════════════════════════════════════════════════════"

    # Seules les modifications de fichiers *suivis* bloquent : un fichier non
    # suivi ne peut rien écraser, et refuser pour lui rendrait le mode
    # inutilisable sur une machine où traînent quelques brouillons.
    # `grep` renvoie 1 quand il ne trouve rien : sous `set -e` + `pipefail`, la
    # substitution faisait sortir le script sans un mot. D'où le `|| true`.
    NON_SUIVIS="$(git status --porcelain | grep '^??' | wc -l || true)"
    SALE="$(git status --porcelain | grep -v '^??' || true)"
    if [ "$NON_SUIVIS" -gt 0 ]; then
        echo "  ($NON_SUIVIS fichier(s) non suivi(s) ignoré(s) par cette synchronisation)"
    fi
    if [ -n "$SALE" ] && [ -z "${FORCE:-}" ]; then
        echo "❌ Modifications locales non commitées :" >&2
        echo "$SALE" | sed 's/^/   /' >&2
        echo "   Commite-les, ou relance avec --force pour les écraser." >&2
        exit 1
    fi

    if [ -n "$DRY_RUN" ]; then
        git fetch --dry-run origin "$BRANCHE" 2>&1 | sed 's/^/   /'
        echo "🔍 Simulation terminée (aucun changement appliqué)."
        exit 0
    fi

    if [ -n "$GITHUB_PUSH" ]; then
        git push origin "$BRANCHE" || exit 1
        echo "✅ Envoi terminé : origin/$BRANCHE à jour."
        exit 0
    fi

    git fetch origin "$BRANCHE" || exit 1
    AVANT="$(git rev-parse HEAD)"
    DISTANT="$(git rev-parse "origin/$BRANCHE")"

    # Sens unique ? Non : le script regarde qui est en avance et va dans ce
    # sens-là. C'est ce qu'on veut entre deux machines qui ne sont jamais
    # allumées en même temps — le dépôt distant sert de point de rendez-vous.
    if [ "$AVANT" = "$DISTANT" ]; then
        echo "✅ Déjà à jour ($(git log --oneline -1))."
    elif git merge-base --is-ancestor "$AVANT" "$DISTANT"; then
        echo "◀ Le dépôt distant est en avance : récupération."
        git merge --ff-only "origin/$BRANCHE" || exit 1
        echo "✅ Récupéré :"
        git log --oneline "$AVANT..HEAD" | sed 's/^/   /'
        git diff --stat "$AVANT" HEAD | sed 's/^/   /'
    elif git merge-base --is-ancestor "$DISTANT" "$AVANT"; then
        echo "▶ Le dépôt local est en avance : envoi."
        git push origin "$BRANCHE" || exit 1
        echo "✅ Envoyé :"
        git log --oneline "$DISTANT..$AVANT" | sed 's/^/   /'
    else
        echo "❌ Divergence : les deux historiques ont des commits que l'autre n'a pas." >&2
        echo "   Rebase ou merge à la main, puis relance." >&2
        exit 1
    fi
    exit 0
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
