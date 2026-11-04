#!/usr/bin/env bash
# Installe tout le greeter en une passe sur une machine neuve.
#
#   bash dev/sddm/setup.sh                    # détecte la distribution, fait tout
#   bash dev/sddm/setup.sh --check            # diagnostic seul (aucune modification)
#   bash dev/sddm/setup.sh --deps             # installe les paquets manquants
#   bash dev/sddm/setup.sh --themes "nothing material-you" --static
#   bash dev/sddm/setup.sh --no-thumbs        # pas d'aperçu (pas de session Wayland)
#   bash dev/sddm/setup.sh --apply field      # sélectionne un thème à la fin
#
# Étapes, dans cet ordre :
#   1. prérequis   paquets, modules QML, session Wayland pour les captures
#   2. astronaut   cloné depuis l'upstream s'il est absent (pas d'AUR sur Fedora)
#   3. thèmes      qylock : récupération (fetch) dans ~/.local/share/qylock-themes
#   4. aperçus     une capture 480×270 par thème (thumbnails.sh)
#   5. pose        copie dans /usr/share/sddm/themes + helper polkit (install.sh)
#   6. panneau     copie de core/greeter_manager.py dans ~/.config/quickshell
#
# Le mot de passe n'est demandé qu'une fois : sudo sur Fedora (pas d'agent
# polkit supposé), pkexec sur Arch. --dry-run affiche les étapes privilégiées.

set -euo pipefail

SDDM_DIR="$(cd "$(dirname "$0")" && pwd)"
DEV="$(cd "$SDDM_DIR/.." && pwd)"
QS="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
SYS_THEMES="/usr/share/sddm/themes"
ASTRO_UPSTREAM="https://github.com/Keyitdev/sddm-astronaut-theme"

die()  { echo "setup.sh: $*" >&2; exit 1; }
step() { echo; echo "▶ $*"; }

usage() {
    cat <<'TXT'
Installe tout le greeter en une passe sur une machine neuve.

  bash dev/sddm/setup.sh                    # détecte la distribution, fait tout
  bash dev/sddm/setup.sh --check            # diagnostic seul (aucune modification)
  bash dev/sddm/setup.sh --deps             # installe les paquets manquants
  bash dev/sddm/setup.sh --themes "nothing material-you" --static
  bash dev/sddm/setup.sh --no-thumbs        # pas d'aperçu (pas de session Wayland)
  bash dev/sddm/setup.sh --apply field      # sélectionne un thème à la fin
  bash dev/sddm/setup.sh --dry-run           # affiche, n'exécute pas (étapes root)

Étapes, dans cet ordre :
  1. prérequis   paquets, modules QML, session Wayland pour les captures
  2. astronaut   cloné depuis l'upstream s'il est absent (pas d'AUR sur Fedora)
  3. thèmes      qylock : récupération dans ~/.local/share/qylock-themes
  4. aperçus     une capture 480×270 par thème (thumbnails.sh)
  5. pose        copie dans /usr/share/sddm/themes + helper polkit (install.sh)
  6. panneau     copie de core/greeter_manager.py dans ~/.config/quickshell

Le mot de passe n'est demandé qu'une fois : sudo sur Fedora (pas d'agent
polkit supposé), pkexec sur Arch.
TXT
}

FETCH=1; THUMBS=1; INSTALL=1; DEPLOY=1
STATIC=""; APPLY=""; SUBSET=""; DO_DEPS=0; CHECK_ONLY=0; DRY=0; FORCE_DISTRO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check)      CHECK_ONLY=1 ;;
        --deps)       DO_DEPS=1 ;;
        --static)     STATIC="--static" ;;
        --themes)     SUBSET="${2:-}"; [ -n "$SUBSET" ] || die "--themes attend des noms"; shift ;;
        --no-fetch)   FETCH=0 ;;
        --no-thumbs)  THUMBS=0 ;;
        --no-install) INSTALL=0 ;;
        --no-deploy)  DEPLOY=0 ;;
        --apply)      APPLY="${2:-}"; [ -n "$APPLY" ] || die "--apply attend un identifiant"; shift ;;
        --dry-run)    DRY=1 ;;
        --distro)     FORCE_DISTRO="${2:-}"; [ -n "$FORCE_DISTRO" ] || die "--distro attend fedora ou arch"; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "option inconnue : $1 (voir --help)" ;;
    esac
    shift
done

# ── Distribution ─────────────────────────────────────────────────────────────
# Les noms de paquets changent d'une famille à l'autre ; tout le reste du
# script ne manipule que les clés ci-dessous.
FAMILY=""
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-} ${ID_LIKE:-}" in
        *fedora*|*rhel*|*centos*) FAMILY="fedora" ;;
        *arch*)                   FAMILY="arch" ;;
    esac
fi
# --distro sert à rejouer la branche de l'autre machine (répétition à blanc).
if [ -n "$FORCE_DISTRO" ]; then
    case "$FORCE_DISTRO" in
        fedora|arch) FAMILY="$FORCE_DISTRO" ;;
        *)           die "--distro : fedora ou arch" ;;
    esac
fi
[ -n "$FAMILY" ] || die "distribution non reconnue (Fedora et Arch sont gérées)"

# deploy.sh nomme ses cibles par machine, pas par distribution.
if [ "$FAMILY" = "fedora" ]; then DEPLOY_TARGET="portable"; else DEPLOY_TARGET="station"; fi

dep_pkg() {
    case "$FAMILY:$1" in
        fedora:qt5compat)    echo "qt6-qt5compat" ;;
        fedora:qtmultimedia) echo "qt6-qtmultimedia" ;;
        fedora:imagemagick)  echo "ImageMagick" ;;
        fedora:inter)        echo "rsms-inter-fonts" ;;
        fedora:*)            echo "$1" ;;
        arch:qt5compat)      echo "qt6-5compat" ;;
        arch:qtmultimedia)   echo "qt6-multimedia-ffmpeg" ;;
        arch:imagemagick)    echo "imagemagick" ;;
        arch:inter)          echo "inter-font" ;;
        arch:*)              echo "$1" ;;
    esac
}

if [ "$FAMILY" = "fedora" ]; then
    PKG_MGR="dnf"; PKG_IN="sudo dnf install -y"; ROOT="sudo"
else
    PKG_MGR="pacman"; PKG_IN="sudo pacman -S --needed --noconfirm"; ROOT="pkexec"
fi

# Exécute une commande en root, ou l'affiche en --dry-run.
root_run() {
    if [ "$DRY" = "1" ]; then
        echo "  [dry-run] $ROOT bash -c '$1'"
        return 0
    fi
    "$ROOT" bash -c "$1"
}

# ── 1. Prérequis ─────────────────────────────────────────────────────────────
step "prérequis ($FAMILY)"

MISSING=()
have() { command -v "$1" >/dev/null 2>&1; }

have sddm-greeter-qt6 || MISSING+=("$(dep_pkg sddm)")
have git             || MISSING+=("git")
have python3         || MISSING+=("python3")
have grim            || MISSING+=("$(dep_pkg grim)")
have magick          || MISSING+=("$(dep_pkg imagemagick)")
# fc-list | grep -q fausse le résultat sous `pipefail` : grep sort au premier
# succès, fc-list reçoit SIGPIPE et le pipeline vaut 141. fc-match répond
# directement le nom de la famille retenue pour « Inter ».
case "$(fc-match -f '%{family}' Inter 2>/dev/null || true)" in
    Inter*) : ;;
    *)      MISSING+=("$(dep_pkg inter)") ;;
esac

# Modules QML : Qt5Compat.GraphicalEffects est importé par tous les thèmes
# qylock, SddmComponents vient de sddm lui-même.
qml_has() {
    local mod="$1" d
    for d in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
        [ -d "$d/$mod" ] && return 0
    done
    return 1
}
qml_has Qt5Compat || MISSING+=("$(dep_pkg qt5compat)")
qml_has SddmComponents || MISSING+=("$(dep_pkg sddm)")

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo "  manquant : ${MISSING[*]}"
    if [ "$DO_DEPS" = "1" ]; then
        [ "$DRY" = "1" ] && echo "  [dry-run] $PKG_IN ${MISSING[*]}" || $PKG_IN "${MISSING[*]}"
    else
        echo "  → relancer avec --deps, ou : $PKG_IN ${MISSING[*]}"
    fi
else
    echo "  paquets, modules QML et police Inter : OK"
fi

if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$THUMBS" = "1" ]; then
    echo "  ⚠ pas de session Wayland : les aperçus seront sautés (--no-thumbs pour le taire)"
    THUMBS=0
fi

if [ "$CHECK_ONLY" = "1" ]; then
    echo
    echo "diagnostic terminé."
    exit 0
fi

# ── 2. Thème astronaut (socle : le script le suppose installé) ───────────────
if [ ! -d "$THEME" ]; then
    step "thème astronaut absent — clonage de l'upstream"
    if [ "$DRY" = "1" ]; then
        echo "  [dry-run] git clone $ASTRO_UPSTREAM → $THEME"
    else
        TMP="$(mktemp -d)"
        trap 'rm -rf "$TMP"' EXIT
        git clone --depth 1 "$ASTRO_UPSTREAM" "$TMP/theme"
        root_run "install -d '$SYS_THEMES' && rm -rf '$THEME' && cp -a '$TMP/theme' '$THEME' && chown -R root:root '$THEME'"
    fi
else
    echo "  thème astronaut : présent"
fi

# ── 3. Thèmes qylock ─────────────────────────────────────────────────────────
if [ "$FETCH" = "1" ]; then
    step "récupération des thèmes qylock"
    NAMES="$SUBSET"
    if [ -z "$NAMES" ]; then
        # Tout le dépôt amont ; les fichiers déjà complets sont sautés.
        NAMES="$(python3 "$SDDM_DIR/qylock.py" list | python3 -c \
            'import json,sys; print(" ".join(t["name"] for t in json.load(sys.stdin)["themes"]))')" \
            || die "catalogue illisible"
    fi
    # shellcheck disable=SC2086
    python3 "$SDDM_DIR/qylock.py" fetch $STATIC $NAMES
fi

# ── 4. Aperçus ───────────────────────────────────────────────────────────────
if [ "$THUMBS" = "1" ]; then
    if [ -d "$THEME/Themes" ]; then
        step "aperçus (une fenêtre de test par thème, l'écran est pris quelques secondes)"
        bash "$SDDM_DIR/thumbnails.sh" ${SUBSET:-} >/dev/null \
            && echo "  miniatures à jour dans ~/.cache/quickshell/greeter-thumbs"
    else
        echo "  ⚠ aperçus sautés : thème astronaut absent"
    fi
fi

# ── 5. Pose dans /usr/share ──────────────────────────────────────────────────
if [ "$INSTALL" = "1" ]; then
    step "installation du socle astronaut dans $SYS_THEMES"
    if [ "$FAMILY" = "fedora" ]; then
        if [ "$DRY" = "1" ]; then
            echo "  [dry-run] ASK_SUDO=1 bash $SDDM_DIR/install.sh"
        else
            sudo -v   # une seule invite pour l'installation, puis pour le panneau
            ASK_SUDO=1 bash "$SDDM_DIR/install.sh"
        fi
    elif [ "$DRY" = "1" ]; then
        echo "  [dry-run] bash $SDDM_DIR/install.sh"
    else
        bash "$SDDM_DIR/install.sh"
    fi

    step "installation des thèmes qylock dans $SYS_THEMES"
    NAMES="$SUBSET"
    if [ -z "$NAMES" ]; then
        NAMES="$(ls -1 "$HOME/.local/share/qylock-themes" 2>/dev/null | tr '\n' ' ')"
    fi
    if [ -n "$NAMES" ]; then
        if [ "$FAMILY" = "fedora" ]; then
            if [ "$DRY" = "1" ]; then
                echo "  [dry-run] ASK_SUDO=1 bash $SDDM_DIR/install.sh --qylock $NAMES"
            else
                # shellcheck disable=SC2086
                ASK_SUDO=1 bash "$SDDM_DIR/install.sh" --qylock $NAMES
            fi
        elif [ "$DRY" = "1" ]; then
            echo "  [dry-run] bash $SDDM_DIR/install.sh --qylock $NAMES"
        else
            # shellcheck disable=SC2086
            bash "$SDDM_DIR/install.sh" --qylock $NAMES
        fi
    fi
fi

# ── 6. Panneau de configuration ──────────────────────────────────────────────
# Le panneau n'exécute jamais le dépôt : il lit sa copie dans ~/.config.
if [ "$DEPLOY" = "1" ]; then
    step "backend du panneau"
    if [ ! -d "$QS/core" ]; then
        echo "  ⚠ $QS/core absent : déployer d'abord la coquille (bash dev/deploy.sh --$DEPLOY_TARGET)"
    elif cmp -s "$DEV/core/greeter_manager.py" "$QS/core/greeter_manager.py"; then
        echo "  greeter_manager.py : déjà à jour"
    else
        cp "$DEV/core/greeter_manager.py" "$QS/core/greeter_manager.py"
        echo "  greeter_manager.py : copié dans $QS/core"
    fi
    if [ ! -f "$QS/GreeterTab.qml" ]; then
        echo "  ⚠ GreeterTab.qml absent du déploiement : l'onglet Connexion n'existera pas"
    elif ! cmp -s "$DEV/GreeterTab.qml" "$QS/GreeterTab.qml"; then
        echo "  ⚠ GreeterTab.qml diffère du dépôt : bash dev/deploy.sh --$DEPLOY_TARGET (déploiement complet)"
    fi
fi

# ── Sélection ────────────────────────────────────────────────────────────────
if [ -n "$APPLY" ]; then
    step "sélection de $APPLY"
    python3 "$QS/core/greeter_manager.py" apply "$APPLY" 2>/dev/null \
        || python3 "$DEV/core/greeter_manager.py" apply "$APPLY"
fi

echo
echo "terminé. Sélection : panneau → Connexion, ou"
echo "  python3 $QS/core/greeter_manager.py apply <thème>"
echo "Contrôle : grep Current /etc/sddm.conf.d/10-sddm-theme.conf"
