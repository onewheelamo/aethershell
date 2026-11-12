#!/bin/sh
# ══════════════════════════════════════════════════════════════════════════════
# AetherShell — installation et mise à jour en une seule ligne
# ══════════════════════════════════════════════════════════════════════════════
#
#   curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | sh
#
# Ce que fait le script, dans cet ordre :
#
#   1. lit la distribution dans /etc/os-release (Arch et Fedora, comme deploy.sh) ;
#   2. clone le dépôt, ou le met à jour en avance rapide s'il est déjà là ;
#   3. lance dev/deploy.sh, qui sauvegarde l'environnement puis déploie le shell.
#
# Rien n'est demandé à l'écran : le déploiement est déjà non interactif, et
# deploy.sh liste les binaires manquants au lieu des les installer à l'aveugle.
#
# Options — à passer après `sh -s --` quand on utilise le lien :
#
#   --dir CHEMIN      dossier du dépôt (défaut : $AETHERSHELL_DIR, sinon
#                     ~/dev/quickshell_todo s'il existe, sinon ~/dev/aethershell)
#   --arch|--fedora   force la cible au lieu de la lire dans /etc/os-release
#   --branche NOM     branche à suivre (défaut : master)
#   --check           montre l'état (dépôt, version, cible) et s'arrête, sans rien
#                     déployer — le même rapport que le panneau affiche
#   --no-deploy       clone ou met à jour le dépôt, sans déployer
#   --help
#
# Ce fichier est écrit en POSIX sh **exprès** : il est destiné à être lu par
# `sh` depuis un tube, donc pas de tableaux, pas de pipefail, pas de `[[ ]]`.

set -eu

DEPOT="onewheelamo/aethershell"
URL_GIT="https://github.com/$DEPOT.git"
LIEN="https://raw.githubusercontent.com/$DEPOT/master/install.sh"

BRANCHE="master"
CIBLE="${AETHERSHELL_DIR:-}"
DISTRO=""
FAIRE_DEPLOI=1
MODE_CHECK=0

usage() {
    sed -n '6,30p' "$0" 2>/dev/null || cat <<'TXT'
AetherShell — installation et mise à jour en une seule ligne

  curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | sh

Options : --dir CHEMIN, --arch, --fedora, --branche NOM, --check, --no-deploy, --help
TXT
}

etape()  { printf '\n▶ %s\n' "$*"; }
dire()   { printf '%s\n' "$*"; }
mourir() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# ── Arguments ────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            shift
            [ $# -gt 0 ] || mourir "--dir attend un chemin"
            CIBLE="$1"
            ;;
        --dir=*)      CIBLE="${1#*=}" ;;
        --arch)       DISTRO="arch" ;;
        --fedora)     DISTRO="fedora" ;;
        --branche)
            shift
            [ $# -gt 0 ] || mourir "--branche attend un nom"
            BRANCHE="$1"
            ;;
        --branche=*)  BRANCHE="${1#*=}" ;;
        --check)      MODE_CHECK=1; FAIRE_DEPLOI=0 ;;
        --no-deploy)  FAIRE_DEPLOI=0 ;;
        -h|--help)    usage; exit 0 ;;
        *)            mourir "option inconnue : $1 (voir --help)" ;;
    esac
    shift
done

[ -n "$BRANCHE" ] || mourir "nom de branche vide"

# ── Distribution ─────────────────────────────────────────────────────────────
detecter_distro() {
    [ -r /etc/os-release ] || return 1
    ident="$(sed -n 's/^ID=//p' /etc/os-release | head -n 1 | tr -d '"' \
             | tr '[:upper:]' '[:lower:]')"
    case "$ident" in
        arch|archarm|endeavouros|manjaro|garuda|cachyos) printf 'arch\n' ;;
        fedora|nobara|bazzite)                          printf 'fedora\n' ;;
        *)                                              return 1 ;;
    esac
}

if [ -z "$DISTRO" ]; then
    DISTRO="$(detecter_distro)" \
        || mourir "distribution non reconnue (attendu : Arch Linux ou Fedora ; force avec --arch ou --fedora)"
fi

# ── Dossier du dépôt ─────────────────────────────────────────────────────────
if [ -z "$CIBLE" ]; then
    if [ -d "$HOME/dev/quickshell_todo/.git" ]; then
        CIBLE="$HOME/dev/quickshell_todo"
    else
        CIBLE="$HOME/dev/aethershell"
    fi
fi
CIBLE="${CIBLE%/}"

# ── Outils de base ───────────────────────────────────────────────────────────
absents=""
for b in git python3; do
    command -v "$b" >/dev/null 2>&1 || absents="$absents $b"
done
[ -z "$absents" ] || mourir "binaires requis absents :$absents — installe-les puis relance."

# ── Clone ou mise à jour ─────────────────────────────────────────────────────
etape "Dépôt : $CIBLE"

if [ -d "$CIBLE/.git" ]; then
    origine="$(git -C "$CIBLE" remote get-url origin 2>/dev/null || true)"
    case "$origine" in
        *"$DEPOT"*) ;;
        *) mourir "$CIBLE n'est pas un clone de $DEPOT (origine : ${origine:-aucune})" ;;
    esac

    courante="$(git -C "$CIBLE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$courante" != "$BRANCHE" ]; then
        dire "  branche ${courante:-détachée} → $BRANCHE"
        git -C "$CIBLE" checkout "$BRANCHE" >/dev/null 2>&1 \
            || mourir "impossible de passer sur la branche $BRANCHE"
    fi

    avant="$(git -C "$CIBLE" rev-parse --short HEAD)"
    # --ff-only --autostash : préserve les modifications locales (ex. tests ou synchro rsync)
    # et évite d'échouer sur un arbre localement modifié.
    if ! git -C "$CIBLE" -c advice.diverging=false pull --ff-only --autostash --quiet origin "$BRANCHE"; then
        mourir "mise à jour impossible : le clone a des modifications locales divergentes (voir « git -C $CIBLE status »)"
    fi
    apres="$(git -C "$CIBLE" rev-parse --short HEAD)"
    if [ "$avant" = "$apres" ]; then
        dire "  déjà à jour ($apres)"
    else
        dire "  mis à jour : $avant → $apres"
    fi
elif [ -e "$CIBLE" ] && [ -n "$(ls -A "$CIBLE" 2>/dev/null || true)" ]; then
    mourir "$CIBLE existe, n'est pas vide et n'est pas un dépôt git — choisis un autre dossier avec --dir"
else
    etape "Premier clone de $DEPOT"
    mkdir -p "$(dirname "$CIBLE")"
    git clone --branch "$BRANCHE" --quiet "$URL_GIT" "$CIBLE" \
        || mourir "clone impossible (dépôt inaccessible ?)"
    dire "  cloné dans $CIBLE"
fi

VERSION="$(git -C "$CIBLE" describe --tags --always --dirty 2>/dev/null || echo inconnue)"

# ── État seul ────────────────────────────────────────────────────────────────
if [ "$MODE_CHECK" = "1" ]; then
    dire ""
    dire "Dépôt        : $CIBLE"
    dire "Version      : $VERSION"
    dire "Distribution : $DISTRO"
    for d in "$HOME/.config/quickshell" "$HOME/.config/hypr"; do
        if [ -d "$d" ]; then
            dire "Déployé      : $d"
        else
            dire "Absent       : $d"
        fi
    done
    exit 0
fi

# ── Déploiement ──────────────────────────────────────────────────────────────
if [ "$FAIRE_DEPLOI" = "1" ]; then
    [ -f "$CIBLE/dev/deploy.sh" ] || mourir "dev/deploy.sh introuvable dans $CIBLE"
    etape "Déploiement de $VERSION (cible : $DISTRO)"
    # Entrée standard fermée : le script est lu depuis un tube, aucun `read` de
    # deploy.sh ne doit pouvoir y mordre. --deploy fait la sauvegarde puis copie.
    if ! bash "$CIBLE/dev/deploy.sh" "--$DISTRO" --deploy < /dev/null; then
        mourir "le déploiement a échoué — à relancer à la main : bash $CIBLE/dev/deploy.sh --$DISTRO"
    fi
    etape "Terminé — AetherShell $VERSION"
else
    etape "Dépôt prêt, déploiement non demandé (--no-deploy)"
fi

dire "Pour revenir à cette page de commande :  $LIEN"
