#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# AetherShell — installation, mise à jour, déploiement & sauvegardes
# ══════════════════════════════════════════════════════════════════════════════
#
# Usage distant (installation ou mise à jour en une ligne) :
#   curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | bash
#
# Usage local (depuis le dépôt) :
#   bash install.sh --yes              # pré-vol + sauvegarde HQ + déploiement
#   bash install.sh --install-deps     # vérifier et installer les dépendances
#   bash install.sh --diff             # comparer dépôt et fichiers déployés
#   bash install.sh --deps             # lister les dépendances de la distro
#   bash install.sh --check            # état du dépôt et de l'installation
#   bash install.sh --snapshots        # lister les snapshots
#   bash install.sh --restore-file P   # restaurer un fichier depuis un snapshot
#
# Options bootstrap (utilisées si hors dépôt ou avec --sync / --check / --no-deploy) :
#   --dir CHEMIN                dossier du dépôt (défaut : $AETHERSHELL_DIR, sinon
#                               ~/dev/quickshell_todo s'il existe, sinon ~/dev/aethershell)
#   --branche NOM               branche à suivre (défaut : master)
#   --check                     montre l'état (dépôt, version, cible) et s'arrête
#   --no-deploy                 clone ou met à jour le dépôt, sans déployer
#   --sync                      force la synchronisation git avant de déployer
#   --offline|--no-sync         n'interroge pas GitHub, utilise les sources locales
#   --install-deps              installe les dépendances système manquantes
#   --arch|--fedora|--debian    force la distribution au lieu de la lire dans /etc/os-release
#   --laptop|--desktop          force le type de poste (auto par batterie/châssis sinon)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

DEPOT="onewheelamo/aethershell"
URL_GIT="https://github.com/$DEPOT.git"
LIEN="https://raw.githubusercontent.com/$DEPOT/master/install.sh"

BRANCHE="master"
CIBLE="${AETHERSHELL_DIR:-}"
MODE_CHECK=0
NO_DEPLOY=0
SYNC_REMOTE=0
OFFLINE_MODE=0
OFFLINE_FALLBACK=0
MISSING_DEPS_WARN=0
SOURCES_MAJ=0
ORIG_ARGS=("$@")

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

CURRENT_HYPR="$HOME/.config/hypr"
BACKUP_DIR="$HOME/.config/backups_env"
SNAPSHOT_DIR="$BACKUP_DIR/snapshots"
QS_DIR="$HOME/.config/quickshell"
CORE_DIR="$QS_DIR/core"

mkdir -p "$BACKUP_DIR" "$SNAPSHOT_DIR"

etape()  { printf '\n▶ %s\n' "$*"; }
dire()   { printf '%s\n' "$*"; }
mourir() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '6,26p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null || cat <<'TXT'
AetherShell — installation et déploiement unifiés
  curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | bash
  bash install.sh [--yes|--install-deps|--diff|--deps|--check|--no-deploy|--arch|--fedora|--debian|--laptop|--desktop]
TXT
}
if [ -t 1 ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_GREEN="\033[0;32m"
    C_YELLOW="\033[0;33m"
    C_BLUE="\033[0;34m"
    C_RED="\033[0;31m"
    C_CYAN="\033[0;36m"
    C_DIM="\033[0;2m"
else
    C_RESET=""
    C_BOLD=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_RED=""
    C_CYAN=""
    C_DIM=""
fi

# Dépendances applicables à une cible, d'après les portées du fichier :
#   #: commun                 → tous les postes et distributions
#   #: laptop|desktop         → facteur de forme (portable ou tour)
#   #: arch|fedora|debian     → famille de distribution
# Un binaire par ligne ; le reste est commentaire. Sert au contrôle avant
# déploiement et à `--deps`, qui affiche la liste résolue sans rien installer.
deps_pour_cible() {
    local cible="$1" forme="${2:-${FORM_FACTOR:-desktop}}" portee="commun" ligne dep ok
    [ -f "$DEPS_FILE" ] || return 1
    while IFS= read -r ligne || [ -n "$ligne" ]; do
        case "$ligne" in
            "#:"*)
                portee="$(printf '%s' "${ligne#\#:}" | tr -d '[:space:]')"
                continue
                ;;
            ""|\#*) continue ;;
        esac
        dep="$(printf '%s' "${ligne%%#*}" | tr -d '[:space:]')"
        [ -z "$dep" ] && continue
        ok=0
        case "$portee" in
            commun|"$cible") ok=1 ;;
            laptop|portable) [ "$forme" = "laptop" ] && ok=1 ;;
            desktop|fixe)    [ "$forme" = "desktop" ] && ok=1 ;;
        esac
        [ "$ok" -eq 1 ] && printf '%s\n' "$dep"
    done < "$DEPS_FILE"
}

detect_form_factor() {
    if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1; then
        echo "laptop"
        return 0
    fi
    if [ -r /sys/class/dmi/id/chassis_type ]; then
        local ctype
        ctype="$(tr -d '[:space:]' < /sys/class/dmi/id/chassis_type 2>/dev/null || true)"
        case "$ctype" in
            8|9|10|14|30|31|32) echo "laptop"; return 0 ;;
        esac
    fi
    echo "desktop"
}

FORM_FACTOR="$(detect_form_factor)"

# 1. Détection de la distribution (argument > /etc/os-release > historique)
DISTRO=""
IDENT=""
ID_LIKE=""
if [ -f /etc/os-release ]; then
    IDENT="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]' || true)"
    ID_LIKE="$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2- | tr -d '"' | tr '[:upper:]' '[:lower:]' || true)"
fi
case "$IDENT" in
    arch|archarm|endeavouros|manjaro|garuda|cachyos) DISTRO="arch" ;;
    fedora|nobara|bazzite) DISTRO="fedora" ;;
    debian|ubuntu|linuxmint|pop|elementary|zorin|kali) DISTRO="debian" ;;
esac
if [ -z "$DISTRO" ] && [ -n "$ID_LIKE" ]; then
    case " $ID_LIKE " in
        *" arch "*) DISTRO="arch" ;;
        *" fedora "*) DISTRO="fedora" ;;
        *" debian "*|*" ubuntu "*) DISTRO="debian" ;;
    esac
fi

PRINT_DEPS=0
INSTALL_DEPS_ONLY=0
YES_MODE=0
DIFF_ONLY=0
DRY_RUN=0
AUTO_DEPLOY=0
DO_BACKUP=0
NO_BACKUP=0
SNAPSHOTS_ACTION=""
RESTORE_FILE=""
RESTORE_SNAP=""
HQ_ACTION=""
HQ_ARG1=""
HQ_ARG2=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            shift
            [ $# -gt 0 ] || mourir "--dir attend un chemin"
            CIBLE="$1"
            SYNC_REMOTE=1
            shift
            ;;
        --dir=*)      CIBLE="${1#*=}"; SYNC_REMOTE=1; shift ;;
        --branche)
            shift
            [ $# -gt 0 ] || mourir "--branche attend un nom"
            BRANCHE="$1"
            SYNC_REMOTE=1
            shift
            ;;
        --branche=*)  BRANCHE="${1#*=}"; SYNC_REMOTE=1; shift ;;
        --check)      MODE_CHECK=1; NO_DEPLOY=1; shift ;;
        --no-deploy)  NO_DEPLOY=1; SYNC_REMOTE=1; shift ;;
        --sync)       SYNC_REMOTE=1; shift ;;
        --offline|--no-sync) OFFLINE_MODE=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        --arch|arch) DISTRO="arch"; shift ;;
        --fedora|fedora) DISTRO="fedora"; shift ;;
        --debian|debian|--ubuntu|ubuntu) DISTRO="debian"; shift ;;
        --laptop|--portable|laptop|portable) FORM_FACTOR="laptop"; shift ;;
        --desktop|--tour|desktop|tour) FORM_FACTOR="desktop"; shift ;;
        --target=*)
            case "${1#*=}" in
                arch|fedora|debian) DISTRO="${1#*=}"; shift ;;
                ubuntu) DISTRO="debian"; shift ;;
                *) echo "❌ Cible inconnue : ${1#*=} (attendu : arch | fedora | debian)" >&2; exit 2 ;;
            esac
            ;;
        --target)
            shift
            case "${1:-}" in
                arch|fedora|debian) DISTRO="${1:-}"; shift ;;
                ubuntu) DISTRO="debian"; shift ;;
                *) echo "❌ Cible inconnue : ${1:-} (attendu : arch | fedora | debian)" >&2; exit 2 ;;
            esac
            ;;
        --deps) PRINT_DEPS=1; shift ;;
        --install-deps) INSTALL_DEPS_ONLY=1; shift ;;
        --diff) DIFF_ONLY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --backup) DO_BACKUP=1; shift ;;
        --no-backup|--skip-backup) NO_BACKUP=1; shift ;;
        --deploy-only) AUTO_DEPLOY=1; NO_BACKUP=1; shift ;;
        --deploy) AUTO_DEPLOY=1; shift ;;
        -y|--yes) AUTO_DEPLOY=1; YES_MODE=1; shift ;;
        --snapshots) SNAPSHOTS_ACTION="list"; shift ;;
        --restore-file)
            shift
            RESTORE_FILE="${1:-}"
            [ -n "$RESTORE_FILE" ] && shift
            RESTORE_SNAP="${1:-}"
            [ -n "$RESTORE_SNAP" ] && shift
            SNAPSHOTS_ACTION="restore_file"
            ;;
        --hq-list)
            shift
            HQ_ACTION="list"
            HQ_ARG1="${1:-}"
            [ -n "$HQ_ARG1" ] && [[ ! "$HQ_ARG1" =~ ^-- ]] && shift
            ;;
        --hq-diff)
            shift
            HQ_ACTION="diff"
            HQ_ARG1="${1:-}"
            [ -n "$HQ_ARG1" ] && [[ ! "$HQ_ARG1" =~ ^-- ]] && shift
            ;;
        --hq-get)
            shift
            HQ_ACTION="get"
            HQ_ARG1="${1:-}"
            [ -n "$HQ_ARG1" ] && shift
            HQ_ARG2="${1:-}"
            [ -n "$HQ_ARG2" ] && shift
            ;;
        *)
            shift
            ;;
    esac
done

FORM_TITLE="Desktop"
[ "$FORM_FACTOR" = "laptop" ] && FORM_TITLE="Laptop"

# ── Bootstrap distant / récupération GitHub / repli local (hors-ligne / USB) ──
LOCAL_REPO=0
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/dev/dependencies.txt" ]; then
    LOCAL_REPO=1
fi

synchroniser_sources() {
    if [ -z "$CIBLE" ]; then
        if [ "$LOCAL_REPO" -eq 1 ]; then
            CIBLE="$SCRIPT_DIR"
        elif [ -d "$HOME/dev/quickshell_todo/.git" ]; then
            CIBLE="$HOME/dev/quickshell_todo"
        else
            CIBLE="$HOME/dev/aethershell"
        fi
    fi
    CIBLE="${CIBLE%/}"

    local has_local=0
    [ -f "$CIBLE/dev/dependencies.txt" ] && has_local=1

    local pure_local_action=0
    if [ "${PRINT_DEPS:-0}" = "1" ] || [ "${DIFF_ONLY:-0}" = "1" ] || [ "${DO_BACKUP:-0}" = "1" ] \
       || [ -n "${SNAPSHOTS_ACTION:-}" ] || [ -n "${HQ_ACTION:-}" ]; then
        pure_local_action=1
    fi

    local try_remote=1
    if [ "${OFFLINE_MODE:-0}" = "1" ] || [ "${AETHER_REEXEC:-0}" = "1" ]; then
        try_remote=0
    elif [ "$pure_local_action" -eq 1 ] && { [ "$LOCAL_REPO" -eq 1 ] || [ "$has_local" -eq 1 ]; }; then
        try_remote=0
    fi
    if [ "$has_local" -eq 0 ] && [ "$LOCAL_REPO" -eq 0 ]; then
        try_remote=1
    fi

    local distant_sha="" retard=0
    if [ "$try_remote" -eq 1 ] && command -v git >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            distant_sha="$(GIT_TERMINAL_PROMPT=0 timeout 6 git ls-remote --heads "$URL_GIT" "$BRANCHE" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
        else
            distant_sha="$(GIT_TERMINAL_PROMPT=0 git ls-remote --heads "$URL_GIT" "$BRANCHE" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
        fi
    fi

    if [ -n "$distant_sha" ]; then
        if [ -d "$CIBLE/.git" ]; then
            local origine local_sha courante avant apres
            origine="$(git -C "$CIBLE" remote get-url origin 2>/dev/null || true)"
            case "$origine" in
                *"$DEPOT"*)
                    local_sha="$(git -C "$CIBLE" rev-parse HEAD 2>/dev/null || true)"
                    if [ "$local_sha" != "$distant_sha" ] || [ "$SYNC_REMOTE" -eq 1 ]; then
                        GIT_TERMINAL_PROMPT=0 git -C "$CIBLE" fetch --quiet origin "$BRANCHE" 2>/dev/null || true
                        retard="$(git -C "$CIBLE" rev-list --count "HEAD..origin/$BRANCHE" 2>/dev/null || echo 0)"
                        if [ "${retard:-0}" -gt 0 ] && [ "$MODE_CHECK" -eq 0 ]; then
                            etape "Dépôt GitHub plus récent ($retard commit(s) d'avance) : mise à jour de $CIBLE"
                            courante="$(git -C "$CIBLE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
                            if [ "$courante" != "$BRANCHE" ]; then
                                git -C "$CIBLE" checkout "$BRANCHE" >/dev/null 2>&1 || true
                            fi
                            avant="$(git -C "$CIBLE" rev-parse --short HEAD)"
                            if git -C "$CIBLE" -c advice.diverging=false pull --ff-only --autostash --quiet origin "$BRANCHE"; then
                                apres="$(git -C "$CIBLE" rev-parse --short HEAD)"
                                dire "  mis à jour : $avant → $apres"
                                SOURCES_MAJ=1
                            else
                                dire "⚠️  Mise à jour git impossible (modifications locales divergentes) : poursuite avec les sources locales ($CIBLE)."
                            fi
                        fi
                    fi
                    ;;
                *)
                    if [ "$SYNC_REMOTE" -eq 1 ]; then
                        mourir "$CIBLE n'est pas un clone de $DEPOT (origine : ${origine:-aucune})"
                    fi
                    ;;
            esac
        elif [ "$MODE_CHECK" -eq 0 ] && { [ "$pure_local_action" -eq 0 ] || [ "$has_local" -eq 0 ]; }; then
            # Aucune source git locale (ex. exécution via curl|bash ou copie depuis clé USB)
            local clone_dest="$CIBLE"
            if [ -e "$clone_dest" ] && [ -n "$(ls -A "$clone_dest" 2>/dev/null || true)" ]; then
                clone_dest="$HOME/dev/aethershell"
            fi
            if [ -d "$clone_dest/.git" ]; then
                etape "Mise à jour du clone existant : $clone_dest"
                GIT_TERMINAL_PROMPT=0 git -C "$clone_dest" -c advice.diverging=false pull --ff-only --autostash --quiet origin "$BRANCHE" 2>/dev/null || true
                if [ -f "$clone_dest/dev/dependencies.txt" ]; then
                    CIBLE="$clone_dest"
                    SOURCES_MAJ=1
                fi
            elif [ ! -e "$clone_dest" ] || [ -z "$(ls -A "$clone_dest" 2>/dev/null || true)" ]; then
                etape "Récupération des sources depuis GitHub ($DEPOT)"
                mkdir -p "$(dirname "$clone_dest")"
                if GIT_TERMINAL_PROMPT=0 git clone --branch "$BRANCHE" --quiet "$URL_GIT" "$clone_dest" 2>/dev/null; then
                    dire "  cloné dans $clone_dest"
                    CIBLE="$clone_dest"
                    SOURCES_MAJ=1
                elif [ "$has_local" -eq 1 ] || [ "$LOCAL_REPO" -eq 1 ]; then
                    [ "$has_local" -eq 0 ] && CIBLE="$SCRIPT_DIR"
                    OFFLINE_FALLBACK=1
                else
                    mourir "clone impossible depuis $URL_GIT et aucune source locale trouvée."
                fi
            fi
        fi
    elif [ "$try_remote" -eq 1 ]; then
        if [ "$has_local" -eq 1 ] || { [ "$LOCAL_REPO" -eq 1 ] && [ -f "$SCRIPT_DIR/dev/dependencies.txt" ]; }; then
            [ "$has_local" -eq 0 ] && CIBLE="$SCRIPT_DIR"
            OFFLINE_FALLBACK=1
            echo "⚠️  Dépôt GitHub inaccessible (mode hors-ligne / clé USB) : poursuite de l'installation avec les sources locales ($CIBLE)."
            echo "ℹ️  Note : si certaines dépendances manquent et ne peuvent pas être téléchargées maintenant,"
            echo "    vous pourrez les installer plus tard depuis le panneau de configuration (onglet « Apps & Alertes »)."
        else
            mourir "aucune source locale trouvée dans $CIBLE et dépôt GitHub ($URL_GIT) inaccessible."
        fi
    fi

    [ -f "$CIBLE/dev/dependencies.txt" ] || [ "$LOCAL_REPO" -eq 0 ] || CIBLE="$SCRIPT_DIR"
    [ -f "$CIBLE/dev/dependencies.txt" ] || mourir "sources introuvables dans $CIBLE."

    VERSION="$(git -C "$CIBLE" describe --tags --always --dirty 2>/dev/null || echo "locale")"

    if [ "$MODE_CHECK" -eq 1 ]; then
        dire ""
        dire "Dépôt        : $CIBLE"
        dire "Version      : $VERSION"
        [ "${retard:-0}" -gt 0 ] && dire "GitHub       : $retard commit(s) d'avance disponibles sur $BRANCHE"
        dire "Distribution : ${DISTRO:-inconnue}"
        dire "Profil       : $FORM_FACTOR ($FORM_TITLE)"
        for d in "$HOME/.config/quickshell" "$HOME/.config/hypr"; do
            if [ -d "$d" ]; then
                dire "Déployé      : $d"
            else
                dire "Absent       : $d"
            fi
        done
        exit 0
    fi

    if [ "$NO_DEPLOY" -eq 1 ]; then
        etape "Dépôt prêt, déploiement non demandé (--no-deploy)"
        dire "Pour revenir à cette page de commande :  $LIEN"
        exit 0
    fi

    # Ré-exécution propre depuis le disque après pipe (curl|bash) ou mise à jour GitHub
    if [ "${AETHER_REEXEC:-0}" != "1" ] && { [ "$LOCAL_REPO" -eq 0 ] || [ "${SOURCES_MAJ:-0}" = "1" ]; } && [ -f "$CIBLE/install.sh" ]; then
        if [ "$LOCAL_REPO" -eq 0 ]; then
            local -a reexec_args=(--yes "--$FORM_FACTOR")
            [ -n "$DISTRO" ] && reexec_args+=("--$DISTRO")
            [ "${NO_BACKUP:-0}" = "1" ] && reexec_args+=(--no-backup)
            [ "${INSTALL_DEPS_ONLY:-0}" = "1" ] && reexec_args+=(--install-deps)
            if ( : </dev/tty ) 2>/dev/null; then
                exec env AETHER_REEXEC=1 bash "$CIBLE/install.sh" "${reexec_args[@]}" </dev/tty
            else
                exec env AETHER_REEXEC=1 bash "$CIBLE/install.sh" "${reexec_args[@]}" </dev/null
            fi
        elif [ "${#ORIG_ARGS[@]}" -gt 0 ]; then
            exec env AETHER_REEXEC=1 bash "$CIBLE/install.sh" "${ORIG_ARGS[@]}"
        else
            exec env AETHER_REEXEC=1 bash "$CIBLE/install.sh"
        fi
    fi

    DEV_DIR="$CIBLE/dev"
    [ "$LOCAL_REPO" -eq 0 ] && AUTO_DEPLOY=1
    return 0
}

synchroniser_sources

DEPS_FILE="$DEV_DIR/dependencies.txt"
if [ -z "$DISTRO" ]; then
    if [ -f "$BACKUP_DIR/backup_fedora_hq.tar.gz" ]; then
        DISTRO="fedora"
    elif [ -f "$BACKUP_DIR/backup_arch_hq.tar.gz" ]; then
        DISTRO="arch"
    elif [ -f "$BACKUP_DIR/backup_debian_hq.tar.gz" ]; then
        DISTRO="debian"
    fi
fi

if [ -z "$DISTRO" ]; then
    echo "❌ Distribution non reconnue (ID='${IDENT:-absent}')." >&2
    echo "   Forcer la cible : $0 --arch | --fedora | --debian" >&2
    exit 2
fi

# 2. Réglages liés à la famille de distribution
case "$DISTRO" in
    fedora)
        DISTRO_TITLE="Fedora"
        PKG_MGR="dnf"
        ;;
    arch)
        DISTRO_TITLE="Arch Linux"
        PKG_MGR="pacman"
        ;;
    debian)
        DISTRO_TITLE="Debian / Ubuntu"
        PKG_MGR="apt"
        ;;
esac
# Sauvegardes : un nom par famille de distribution, sans rien qui nomme la machine.
# HQ seulement : l'environnement Noctalia n'est plus utilise, et une sauvegarde qui
# ne sert jamais ne fait que brouiller le choix au moment de restaurer.
HQ_ALIAS="$BACKUP_DIR/backup_${DISTRO}_hq.tar.gz"
HQ_RETENTION=5

# `--deps` : la liste que ce fichier donne pour la cible, sans rien toucher.
if [ "${PRINT_DEPS:-0}" = "1" ]; then
    deps_pour_cible "$DISTRO" "$FORM_FACTOR" || { echo "❌ $DEPS_FILE introuvable." >&2; exit 1; }
    exit 0
fi

# 3. Preservation logic
MARKER="$CURRENT_HYPR/.quickshell_managed"
# llm_providers.json : adresses et références de clés choisies par l'utilisateur,
# préservé comme secrets.json — le dépôt n'en fournit que le modèle initial.
# État de l'utilisateur : le déploiement n'y touche JAMAIS quand le fichier
# existe déjà. La distinction compte : `PRESERVE_CORE` empêche l'élagage mais
# laisse `sync_file` écraser la cible par la version du dépôt — c'est ainsi que
# la composition de la barre (15 applets) a été remplacée par la version minimale
# du dépôt (2 applets), vidant la barre.
# Fichiers .json de core/ qui sont du **code ou des données livrées** : eux seuls
# sont déployés. Tout le reste est un état de cette machine-là — composition de la
# barre, palette, caches, secrets, cibles distantes — et ne doit jamais être
# écrasé. La règle est structurelle : elle couvre les fichiers futurs sans qu'on
# ait à les inscrire un par un (deux incidents successifs ont montré le coût de
# la liste au cas par cas).
JSON_DEPLOYES="applets_catalogue.json emoji.json tray_icons.json secrets.example.json"

PRESERVE_CORE="style_vars.json app_vars.json secrets.json autostart.json widgets.json notif_targets.json llm_providers.json bar_applets.json homelab.json launch_history.json todo.json"
# colors.lua est *généré* par generate_rofi_theme.sh depuis style_vars.json :
# il n'est ni préservé ni comparé (sinon .upstream à chaque changement de palette).
# programs.lua est *généré* depuis core/app_vars.json (sync_programs_lua) et
# autostart_cmds.txt depuis core/autostart.json : ils ne sont ni préservés ni
# comparés, et sont réécrits juste après la copie (aucun .upstream possible).
PRESERVE_HYPR="input.lua binds.lua general.lua"

# dossier_de DST : la famille d'un répertoire cible, pour est_etat_machine.
dossier_de() {
    case "$(basename "$1")" in
        core) echo core ;;
        hypr|hypr_modular) echo hypr ;;
        *) echo "" ;;
    esac
}

# est_etat_machine NOM DOSSIER : ce fichier appartient-il à CETTE machine ?
#
# Règle **unique**, appelée par le pré-vol, la copie et l'élagage. Elle remplace
# trois jeux qui avaient divergé : le pré-vol protégeait tout `.json` de core/
# non livré, la copie ne protégeait que `PRESERVE_CORE`, et l'élagage avait sa
# propre liste. Un fichier pouvait donc être annoncé « protégé » puis élagué —
# `dependencies.txt` était encore le cas au dernier pré-vol.
est_etat_machine() {
    local name="$1" dossier="${2:-}"
    [ "${DEPLOY_OVERWRITE:-0}" = "1" ] && return 1
    [ -f "$MARKER" ] || return 1

    case "$name" in
        *.upstream|*.new|*.tmp|*.tmp.*) return 0 ;;
        secrets.json|*_cache.json) return 0 ;;
    esac

    case "$dossier" in
        core)
            case " $PRESERVE_CORE " in *" $name "*) return 0 ;; esac
            # Copié après l'élagage depuis la racine du dépôt : sa place est
            # décidée par le déploiement, pas par un inventaire.
            [ "$name" = "dependencies.txt" ] && return 0
            # Tout .json de core/ qui n'est pas livré est un état de la machine :
            # composition de la barre, palette, flotte, index du lanceur…
            case "$name" in
                *.json)
                    case " $JSON_DEPLOYES " in *" $name "*) return 1 ;; esac
                    return 0
                    ;;
            esac
            ;;
        hypr)
            # Uniquement l'état : les fichiers d'entrée de l'utilisateur et la
            # configuration matérielle de cette machine. Les fichiers *régénérés*
            # par le déploiement (`colors.lua`, `programs.lua`,
            # `autostart_cmds.txt`, `hypridle.conf`…) ne sont pas de l'état : le
            # déploiement les réécrit lui-même, et les traiter comme préservés
            # laisserait un `.upstream` orphelin à chaque passage.
            case " $PRESERVE_HYPR " in *" $name "*) return 0 ;; esac
            case "$name" in
                hardware-*.lua) return 0 ;;
            esac
            ;;
    esac
    return 1
}

is_preserved() {
    local name="$1" list="$2" item
    [ "${DEPLOY_OVERWRITE:-0}" = "1" ] && return 1
    [ -f "$MARKER" ] || return 1
    for item in $list; do
        [ "$name" = "$item" ] && return 0
    done
    case "$name" in hardware-*.lua) [ "$list" = "$PRESERVE_HYPR" ] && return 0 ;; esac
    return 1
}

# sync_file SRC DST : compare and update target without redundant .new duplicates
sync_file() {
    local src="$1" dst="$2"
    if [ ! -e "$dst" ]; then
        cp "$src" "$dst"
        return
    fi
    if cmp -s "$src" "$dst"; then
        rm -f "$dst.upstream" "$dst.new"
        return
    fi
    case "$(basename "$dst")" in
        secrets.json) ;;
        *)
            echo "  ↪ upstream diff detected for $dst -> saved to $dst.upstream"
            cp "$src" "$dst.upstream"
            rm -f "$dst.new"
            ;;
    esac
}

# copy_dir_files SRC DST PRESERVE_LIST : copy regular files, manage preserved ones with sync_file
copy_dir_files() {
    local src="$1" dst="$2" list="$3" f name
    for f in "$src"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        # État de cette machine (voir est_etat_machine) : dans core/ on n'y touche
        # pas du tout ; ailleurs on garde le fichier et on dépose .upstream.
        if [ -e "$dst/$name" ]; then
            local doss
            doss="$(dossier_de "$dst")"
            if est_etat_machine "$name" "$doss"; then
                [ "$doss" = "core" ] && continue
                sync_file "$f" "$dst/$name"
                continue
            fi
        fi
        if [ -e "$dst/$name" ] && [[ " ${NON_ECRASABLES:-} " == *" $name "* ]]; then
            continue
        fi
        cp "$f" "$dst/$name"
    done
}

# prune_target DST MANIFEST PRESERVE_LIST : remove target files not in manifest, excluding preserved/system files
prune_target() {
    local dst="$1" manifest="$2" preserve_list="${3:-}" f name
    [ -d "$dst" ] || return 0
    for f in "$dst"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        grep -qxF "$name" "$manifest" && continue
        est_etat_machine "$name" "$(dossier_de "$dst")" && continue
        [ -n "$preserve_list" ] && is_preserved "$name" "$preserve_list" && continue
        case "$name" in
            *.upstream) continue ;;
            hypridle.conf|hyprlock.conf|hyprlock-colors.conf|autostart_cmds.txt|.quickshell_managed) continue ;;
            secrets.json) continue ;;
            # Copié après l'élagage depuis la racine du dépôt : sans cette ligne,
            # chaque déploiement l'archivait puis le reposait.
            dependencies.txt) continue ;;
            # Caches écrits à l'exécution par les services : absents du dépôt par
            # construction, donc jamais « obsolètes ». Sans cette ligne, chaque
            # déploiement les archivait et le shell repartait d'un cache vide.
            *_cache.json) continue ;;
        esac
        if [ "${PRUNE_DRY:-0}" = "1" ]; then
            echo "  [dry-run] would prune: $dst/$name"
            continue
        fi
        # Jamais de suppression sèche : copie de sauvegarde horodatée.
        mkdir -p "$BACKUP_DIR/pruned_$(date +%Y%m%d)"
        cp -a "$f" "$BACKUP_DIR/pruned_$(date +%Y%m%d)/" || {
            echo "  ⚠️  archivage impossible, $f conservé" >&2; continue; }
        echo "  pruning obsolete target file: $dst/$name (archivé)"
        rm -f "$f"
    done
}

rotate_backups() {
    local old_backups
    # On garde plusieurs versions : « revenir a une version anterieure » suppose
    # d'en avoir ou choisir.
    mapfile -t old_backups < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*_20*.tar.gz" -printf "%T@ %p\n" 2>/dev/null | sort -nr | tail -n +$((HQ_RETENTION + 1)) | awk '{print $2}')
    for b in "${old_backups[@]}"; do
        if [ -n "$b" ] && [ -f "$b" ]; then
            echo "  pruning old backup: $b"
            rm -f "$b"
        fi
    done
}

bin_present() {
    local bin="$1"
    if command -v "$bin" >/dev/null 2>&1; then
        return 0
    fi
    if [ "$bin" = "magick" ] && [ "$DISTRO" = "debian" ] && command -v convert >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

pkg_for_bin() {
    local bin="$1"
    case "$PKG_MGR" in
        dnf)
            case "$bin" in
                wpctl) echo "wireplumber" ;;
                nmcli) echo "NetworkManager" ;;
                powerprofilesctl) echo "power-profiles-daemon" ;;
                monitor-sensor) echo "iio-sensor-proxy" ;;
                magick) echo "ImageMagick" ;;
                inotifywait) echo "inotify-tools" ;;
                notify-send) echo "libnotify" ;;
                pactl) echo "pulseaudio-utils" ;;
                wl-copy) echo "wl-clipboard" ;;
                bluetoothctl) echo "bluez" ;;
                cc) echo "gcc" ;;
                *) echo "$bin" ;;
            esac
            ;;
        apt)
            case "$bin" in
                wpctl) echo "wireplumber" ;;
                nmcli) echo "network-manager" ;;
                powerprofilesctl) echo "power-profiles-daemon" ;;
                monitor-sensor) echo "iio-sensor-proxy" ;;
                magick) echo "imagemagick" ;;
                inotifywait) echo "inotify-tools" ;;
                notify-send) echo "libnotify-bin" ;;
                pactl) echo "pulseaudio-utils" ;;
                wl-copy) echo "wl-clipboard" ;;
                bluetoothctl) echo "bluez" ;;
                cc) echo "gcc" ;;
                *) echo "$bin" ;;
            esac
            ;;
        *)
            case "$bin" in
                wpctl) echo "wireplumber" ;;
                nmcli) echo "networkmanager" ;;
                powerprofilesctl) echo "power-profiles-daemon" ;;
                monitor-sensor) echo "iio-sensor-proxy" ;;
                magick) echo "imagemagick" ;;
                inotifywait) echo "inotify-tools" ;;
                notify-send) echo "libnotify" ;;
                pactl) echo "libpulse" ;;
                wl-copy) echo "wl-clipboard" ;;
                bluetoothctl) echo "bluez-utils" ;;
                cc) echo "gcc" ;;
                matugen) echo "matugen-bin" ;;
                *) echo "$bin" ;;
            esac
            ;;
    esac
}

build_pwscope_if_ready() {
    [ "${DRY_RUN:-0}" != "1" ] || return 0
    [ -f "$DEV_DIR/core/pwscope_make.sh" ] || return 0
    if command -v cc >/dev/null 2>&1 && pkg-config --exists libpipewire-0.3 2>/dev/null; then
        sh "$DEV_DIR/core/pwscope_make.sh" >/dev/null 2>&1 || echo "⚠️ Compilation de pwscope ignorée/échouée."
    fi
}

install_arch_aur_helper() {
    if command -v yay >/dev/null 2>&1; then echo "yay"; return 0; fi
    if command -v paru >/dev/null 2>&1; then echo "paru"; return 0; fi
    if [ "$(id -u)" -eq 0 ]; then
        echo "⚠️ Exécution en root : impossible de compiler yay automatiquement via makepkg." >&2
        return 1
    fi
    local ans="n"
    if [ "${YES_MODE:-0}" = "1" ]; then
        ans="y"
    elif [ -t 0 ]; then
        read -p "Aucun assistant AUR (yay/paru) trouvé. Installer yay-bin automatiquement ? (o/n) : " ans
    fi
    case "$ans" in
        o|O|y|Y)
            local tmp_aur
            tmp_aur="$(mktemp -d)"
            local -a pflags=(--needed)
            [ "${YES_MODE:-0}" = "1" ] && pflags+=(--noconfirm)
            sudo pacman -S "${pflags[@]}" base-devel git
            if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp_aur/yay-bin"; then
                if [ "${YES_MODE:-0}" = "1" ]; then
                    (cd "$tmp_aur/yay-bin" && makepkg -si --noconfirm)
                else
                    (cd "$tmp_aur/yay-bin" && makepkg -si)
                fi
            fi
            rm -rf "$tmp_aur"
            command -v yay >/dev/null 2>&1 && { echo "yay"; return 0; }
            ;;
    esac
    return 1
}

install_debian_extra_bins() {
    local -a extras=("$@")
    [ "${#extras[@]}" -gt 0 ] || return 0
    mkdir -p "$HOME/.local/bin"

    local item
    local -a rust_tools=() manual_tools=()
    for item in "${extras[@]}"; do
        case "$item" in
            hyprshot)
                if command -v curl >/dev/null 2>&1; then
                    echo "▶ Téléchargement de hyprshot dans $HOME/.local/bin/hyprshot..."
                    if curl -fsSL "https://raw.githubusercontent.com/Gustash/Hyprshot/main/hyprshot" -o "$HOME/.local/bin/hyprshot"; then
                        chmod +x "$HOME/.local/bin/hyprshot"
                        echo "✅ hyprshot installé dans $HOME/.local/bin/hyprshot"
                    else
                        manual_tools+=("hyprshot")
                    fi
                else
                    manual_tools+=("hyprshot")
                fi
                ;;
            matugen|awww)
                rust_tools+=("$item")
                ;;
            *)
                manual_tools+=("$item")
                ;;
        esac
    done

    if [ "${#rust_tools[@]}" -gt 0 ]; then
        if ! command -v cargo >/dev/null 2>&1; then
            local ans_rust="n"
            if [ "${YES_MODE:-0}" = "1" ]; then
                ans_rust="y"
            elif [ -t 0 ]; then
                read -p "Installer cargo/rustc via apt pour compiler (${rust_tools[*]}) ? (o/n) : " ans_rust
            fi
            case "$ans_rust" in
                o|O|y|Y) sudo apt-get install -y cargo rustc pkg-config liblz4-dev || true ;;
            esac
        fi
        if command -v cargo >/dev/null 2>&1; then
            for item in "${rust_tools[@]}"; do
                echo "▶ Installation Cargo : $item..."
                if [ "$item" = "awww" ]; then
                    cargo install --git https://codeberg.org/LGFae/awww awww 2>/dev/null \
                        || cargo install awww 2>/dev/null \
                        || manual_tools+=("$item")
                else
                    cargo install "$item" || manual_tools+=("$item")
                fi
            done
        else
            manual_tools+=("${rust_tools[@]}")
        fi
    fi

    if [ "${#manual_tools[@]}" -gt 0 ]; then
        echo ""
        echo "⚠️ Outils absents des dépôts APT standard (${manual_tools[*]}) :"
        for item in "${manual_tools[@]}"; do
            case "$item" in
                quickshell) echo "   - quickshell : installer depuis OBS / dépôt tiers Debian-Ubuntu ou compiler depuis https://quickshell.org" ;;
                hyprsunset) echo "   - hyprsunset : compiler depuis https://github.com/hyprwm/hyprsunset (cmake)" ;;
                matugen)    echo "   - matugen    : 'cargo install matugen' ou binaire GitHub -> ~/.local/bin/matugen" ;;
                awww)       echo "   - awww       : compiler depuis https://codeberg.org/LGFae/awww -> ~/.local/bin/awww" ;;
                hyprshot)   echo "   - hyprshot   : copier le script dans ~/.local/bin/hyprshot" ;;
                *)          echo "   - $item     : installer manuellement dans ~/.local/bin/" ;;
            esac
        done
    fi
}

install_missing_dependencies() {
    local -a req_pkgs=("$@")
    local -A seen=()
    local -a unique_pkgs=()
    local p
    for p in "${req_pkgs[@]}"; do
        [ -n "$p" ] || continue
        if [ -z "${seen[$p]:-}" ]; then
            seen["$p"]=1
            unique_pkgs+=("$p")
        fi
    done

    case "$PKG_MGR" in
        pacman)
            local -a official_pkgs=("python-pillow" "python-numpy" "pipewire")
            local -a aur_pkgs=()
            for p in "${unique_pkgs[@]}"; do
                if pacman -Si "$p" >/dev/null 2>&1; then
                    official_pkgs+=("$p")
                else
                    aur_pkgs+=("$p")
                fi
            done
            local -a pflags=(--needed)
            [ "${YES_MODE:-0}" = "1" ] && pflags+=(--noconfirm)
            if [ "${#official_pkgs[@]}" -gt 0 ]; then
                echo "▶ Pacman (dépôts officiels) : ${official_pkgs[*]}"
                sudo pacman -S "${pflags[@]}" "${official_pkgs[@]}" || return 1
            fi
            if [ "${#aur_pkgs[@]}" -gt 0 ]; then
                echo "▶ Paquets AUR détectés : ${aur_pkgs[*]}"
                local aur_helper=""
                aur_helper="$(install_arch_aur_helper || true)"
                if [ -n "$aur_helper" ]; then
                    "$aur_helper" -S "${pflags[@]}" "${aur_pkgs[@]}" || return 1
                else
                    echo "⚠️ Assistant AUR absent : installe manuellement ${aur_pkgs[*]} avec yay/paru."
                    return 1
                fi
            fi
            ;;
        dnf)
            local need_copr=0
            for p in "${unique_pkgs[@]}"; do
                case "$p" in
                    quickshell|matugen|awww|hyprshot|hyprsunset) need_copr=1 ;;
                esac
            done
            if [ "$need_copr" -eq 1 ] && dnf copr --help >/dev/null 2>&1; then
                local ans_copr="y"
                if [ "${YES_MODE:-0}" != "1" ] && [ -t 0 ]; then
                    read -p "Activer les dépôts COPR (errornointernet/quickshell, solopasha/hyprland) si nécessaires ? (o/n) [o] : " ans_copr
                fi
                case "${ans_copr:-o}" in
                    o|O|y|Y|"")
                        sudo dnf copr enable -y errornointernet/quickshell || true
                        sudo dnf copr enable -y solopasha/hyprland || true
                        ;;
                esac
            fi
            sudo dnf install -y "${unique_pkgs[@]}" python3-pillow python3-numpy pipewire-devel || return 1
            ;;
        apt)
            if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
                if ! grep -qsE '^\s*(deb|Components).*universe' /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null; then
                    echo "▶ Activation du dépôt Ubuntu 'universe'..."
                    sudo apt-get update
                    sudo apt-get install -y software-properties-common
                    sudo add-apt-repository -y universe || true
                fi
            fi
            sudo apt-get update
            local -a apt_pkgs=("python3-venv" "python3-pip" "python3-pil" "python3-numpy" "libpipewire-0.3-dev" "curl" "git")
            local -a non_apt_pkgs=()
            for p in "${unique_pkgs[@]}"; do
                if apt-cache show "$p" >/dev/null 2>&1; then
                    apt_pkgs+=("$p")
                else
                    non_apt_pkgs+=("$p")
                fi
            done
            if [ "${#apt_pkgs[@]}" -gt 0 ]; then
                echo "▶ APT : ${apt_pkgs[*]}"
                sudo apt-get install -y "${apt_pkgs[@]}" || return 1
            fi
            if [ "${#non_apt_pkgs[@]}" -gt 0 ]; then
                install_debian_extra_bins "${non_apt_pkgs[@]}"
            fi
            ;;
    esac
    if [ "$FORM_FACTOR" = "laptop" ] && command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable --now power-profiles-daemon.service >/dev/null 2>&1 || true
    fi
    return 0
}

check_dependencies() {
    echo "Checking dependencies for $DISTRO_TITLE ($FORM_TITLE)..."
    if [ ! -f "$DEPS_FILE" ]; then
        echo "❌ Error: $DEPS_FILE not found."
        return 1
    fi

    local deps=()
    mapfile -t deps < <(deps_pour_cible "$DISTRO" "$FORM_FACTOR")
    local missing=()
    local missing_pkgs=()
    for dep in "${deps[@]}"; do
        if [ -z "$dep" ]; then continue; fi
        if ! bin_present "$dep"; then
            missing+=("$dep")
            missing_pkgs+=("$(pkg_for_bin "$dep")")
        fi
    done

    # `grep -q` serait un faux négatif ici : sous `set -o pipefail`, grep sort au
    # premier match, fc-list prend SIGPIPE et le pipeline rend 141 → la police
    # paraît manquante à chaque déploiement et se réinstalle.
    if ! fc-list : family 2>/dev/null | grep -i "0xproto" >/dev/null; then
        echo "⚠️ Police d'icônes manquante : 0xProto Nerd Font"
        if [ "${DRY_RUN:-0}" != "1" ] && [ -x "$DEV_DIR/core/install_fonts.sh" ]; then
            bash "$DEV_DIR/core/install_fonts.sh" || echo "⚠️ Échec de l'installation automatique de la police."
        fi
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        echo "✅ All dependencies installed."
        build_pwscope_if_ready
        return 0
    else
        echo "⚠️ Missing binaries: ${missing[*]} ($PKG_MGR packages: ${missing_pkgs[*]})"
        MISSING_DEPS_WARN=1
        echo "ℹ️  Vous pourrez installer les dépendances manquantes ultérieurement depuis le panneau de configuration :"
        echo "    SUPER + SHIFT + H  ➜  onglet « Apps & Alertes »  ➜  « Installer les paquets manquants »"

        if [ "${OFFLINE_FALLBACK:-0}" = "1" ]; then
            echo "⚠️  Mode hors-ligne / clé USB actif : poursuite de l'installation locale sans télécharger les paquets."
            build_pwscope_if_ready
            return 0
        fi
        if [ "${INSTALL_DEPS_ONLY:-0}" != "1" ] && { [ "${DRY_RUN:-0}" = "1" ] || [ ! -t 0 ] || [ "${AUTO_DEPLOY:-0}" = "1" ]; }; then
            echo "ℹ️ Déploiement non interactif : continuation malgré les binaires signalés."
            return 0
        fi
        local choice="n"
        if [ "${INSTALL_DEPS_ONLY:-0}" = "1" ] && [ "${YES_MODE:-0}" = "1" ]; then
            choice="y"
        elif [ -t 0 ]; then
            read -p "Voulez-vous installer les dépendances manquantes maintenant ($PKG_MGR) ? (o/n) : " choice
        fi
        case "$choice" in
            o|O|y|Y)
                local rc=0
                install_missing_dependencies "${missing_pkgs[@]}" || rc=$?
                build_pwscope_if_ready
                if [ "$rc" -ne 0 ] && [ "${INSTALL_DEPS_ONLY:-0}" != "1" ]; then
                    echo "⚠️  L'installation des dépendances a échoué (réseau indisponible ?)."
                    echo "ℹ️  Vous pourrez relancer l'installation depuis SUPER + SHIFT + H ➜ onglet « Apps & Alertes »."
                    local cont_err="o"
                    if [ "${YES_MODE:-0}" != "1" ] && [ -t 0 ]; then
                        read -p "Continuer le déploiement des fichiers locaux malgré tout ? (o/n) [o] : " cont_err
                    fi
                    case "${cont_err:-o}" in
                        o|O|y|Y|"") return 0 ;;
                        *) return 1 ;;
                    esac
                fi
                if [ "$rc" -eq 0 ]; then
                    MISSING_DEPS_WARN=0
                fi
                return $rc
                ;;
            *)
                if [ "${INSTALL_DEPS_ONLY:-0}" = "1" ]; then
                    return 1
                fi
                read -p "Continue deployment anyway? (o/n): " cont
                case "$cont" in
                    o|O|y|Y|"") return 0 ;;
                    *) return 1 ;;
                esac
                ;;
        esac
    fi
}

# ── Snapshot fin granulaire ──────────────────────────────────────────────────
# Au lieu d'une archive monolithique opaque, le snapshot fin conserve l'arborescence
# décompressée sous ~/.config/backups_env/snapshots/<horodatage>/ avec manifest.json
# et index sha256. Permet d'inspecter ou de restaurer un seul fichier en un instant.

detect_origin_type() {
    if [ -f "$MARKER" ]; then
        echo "quickshell_managed"
    elif [ -f "$CURRENT_HYPR/hyprland.conf" ] || [ -f "$CURRENT_HYPR/hyprland.lua" ]; then
        echo "foreign_hyprland"
    elif [ -d "$CURRENT_HYPR" ] || [ -d "$QS_DIR" ]; then
        echo "existing_partial"
    else
        echo "fresh_install"
    fi
}

rotate_snapshots() {
    local old_snaps
    mapfile -t old_snaps < <(find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "latest" -printf "%T@ %p\n" 2>/dev/null | sort -nr | tail -n +$((HQ_RETENTION + 1)) | awk '{print $2}')
    for s in "${old_snaps[@]}"; do
        if [ -n "$s" ] && [ -d "$s" ]; then
            case "$s" in
                "$SNAPSHOT_DIR/"*) rm -rf -- "$s" ;;
            esac
        fi
    done
}

create_fine_snapshot() {
    local stamp="${1:-$(date +%Y%m%d_%H%M%S)}" snap_dest origin git_rev count_hypr=0 count_qs=0
    snap_dest="$SNAPSHOT_DIR/$stamp"
    mkdir -p "$snap_dest/hypr" "$snap_dest/quickshell"

    origin="$(detect_origin_type)"
    git_rev="$(git -C "$DEV_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

    if [ -d "$CURRENT_HYPR" ]; then
        cp -a "$CURRENT_HYPR/." "$snap_dest/hypr/" 2>/dev/null || true
        count_hypr=$(find "$snap_dest/hypr" -type f 2>/dev/null | wc -l)
    fi
    if [ -d "$QS_DIR" ]; then
        cp -a "$QS_DIR/." "$snap_dest/quickshell/" 2>/dev/null || true
        count_qs=$(find "$snap_dest/quickshell" -type f 2>/dev/null | wc -l)
    fi

    cat > "$snap_dest/manifest.json" <<EOF
{
  "timestamp": "$stamp",
  "distro": "$DISTRO",
  "form_factor": "$FORM_FACTOR",
  "origin": "$origin",
  "git_commit": "$git_rev",
  "files_hypr": $count_hypr,
  "files_quickshell": $count_qs,
  "created_at": "$(date --iso-8601=seconds 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
}
EOF

    (
        cd "$snap_dest" && find hypr quickshell -type f -print0 2>/dev/null \
            | sort -z | xargs -0 sha256sum 2>/dev/null
    ) > "$snap_dest/checksums.sha256" 2>/dev/null || true

    ln -sfn "$stamp" "$SNAPSHOT_DIR/latest"
    rotate_snapshots
    echo "✅ Snapshot fin créé : $(basename "$snap_dest") ($((count_hypr + count_qs)) fichiers, origine: $origin)"
}

snapshots_lister() {
    local snaps=()
    mapfile -t snaps < <(find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "latest" -printf "%T@ %p\n" 2>/dev/null | sort -nr | awk '{print $2}')
    if [ "${#snaps[@]}" -eq 0 ]; then
        echo "ℹ️ Aucun snapshot fin dans $SNAPSHOT_DIR"
        return 0
    fi
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_CYAN}${C_BOLD}Snapshots fins disponibles ($SNAPSHOT_DIR) :${C_RESET}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"
    local i snap nom origin distro files_count files_h files_q human_date
    for i in "${!snaps[@]}"; do
        snap="${snaps[$i]}"
        nom="$(basename "$snap")"
        if [ -f "$snap/manifest.json" ]; then
            origin=$(grep -oE '"origin": "[^"]+"' "$snap/manifest.json" | cut -d'"' -f4)
            distro=$(grep -oE '"distro": "[^"]+"' "$snap/manifest.json" | cut -d'"' -f4)
            files_h=$(grep -oE '"files_hypr": [0-9]+' "$snap/manifest.json" | cut -d' ' -f2)
            files_q=$(grep -oE '"files_quickshell": [0-9]+' "$snap/manifest.json" | cut -d' ' -f2)
            files_count=$(( ${files_h:-0} + ${files_q:-0} ))
            human_date=$(grep -oE '"created_at": "[^"]+"' "$snap/manifest.json" | cut -d'"' -f4)
        else
            origin="inconnu"
            distro="inconnu"
            files_count=$(find "$snap" -type f 2>/dev/null | wc -l)
            human_date="$nom"
        fi
        printf ' %2d > %-18s | %-8s | %-18s | %3d fichiers | %s\n' \
            "$((i+1))" "$nom" "${distro:-inconnu}" "${origin:-inconnu}" "$files_count" "${human_date:-$nom}"
    done
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"
}

restore_snapshot_file() {
    local file_input="${1:-}" snap_choice="${2:-latest}"
    if [ -z "$file_input" ]; then
        echo "❌ Usage : restore_snapshot_file <chemin_fichier> [snapshot_timestamp|latest]" >&2
        return 1
    fi

    local snap_dir=""
    if [ "$snap_choice" = "latest" ]; then
        if [ -L "$SNAPSHOT_DIR/latest" ] || [ -d "$SNAPSHOT_DIR/latest" ]; then
            snap_dir="$(cd -P "$SNAPSHOT_DIR/latest" 2>/dev/null && pwd)"
        else
            snap_dir=$(find "$SNAPSHOT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "latest" -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -1 | awk '{print $2}')
        fi
    elif [ -d "$SNAPSHOT_DIR/$snap_choice" ]; then
        snap_dir="$SNAPSHOT_DIR/$snap_choice"
    else
        echo "❌ Snapshot introuvable : $snap_choice" >&2
        return 1
    fi

    [ -d "$snap_dir" ] || { echo "❌ Aucun snapshot valide trouvé." >&2; return 1; }

    local clean_path="${file_input#$HOME/.config/}"
    clean_path="${clean_path#/}"

    local src_file="" dst_file=""
    if [ -f "$snap_dir/$clean_path" ]; then
        src_file="$snap_dir/$clean_path"
        dst_file="$HOME/.config/$clean_path"
    elif [ -f "$snap_dir/quickshell/$clean_path" ]; then
        src_file="$snap_dir/quickshell/$clean_path"
        dst_file="$QS_DIR/$clean_path"
    elif [ -f "$snap_dir/hypr/$clean_path" ]; then
        src_file="$snap_dir/hypr/$clean_path"
        dst_file="$CURRENT_HYPR/$clean_path"
    elif [ -f "$snap_dir/quickshell/core/$clean_path" ]; then
        src_file="$snap_dir/quickshell/core/$clean_path"
        dst_file="$CORE_DIR/$clean_path"
    else
        local found
        found=$(find "$snap_dir" -type f -name "$(basename "$clean_path")" | head -1)
        if [ -n "$found" ]; then
            local rel="${found#$snap_dir/}"
            src_file="$found"
            dst_file="$HOME/.config/$rel"
        fi
    fi

    if [ -z "$src_file" ] || [ ! -f "$src_file" ]; then
        echo "❌ Fichier '$file_input' introuvable dans le snapshot $(basename "$snap_dir")" >&2
        return 1
    fi

    local safety_dir="$BACKUP_DIR/restores_replaced_$(date +%Y%m%d_%H%M%S)"
    if [ -f "$dst_file" ]; then
        mkdir -p "$safety_dir"
        cp -a "$dst_file" "$safety_dir/"
        echo "  ℹ️ Copie de sécurité de l'existant : $safety_dir/$(basename "$dst_file")"
    fi

    mkdir -p "$(dirname "$dst_file")"
    cp -a "$src_file" "$dst_file"
    echo "✅ Fichier restauré avec succès : $dst_file"
    echo "   Source : $src_file"
    return 0
}

compute_diff_stats() {
    local src="$1" dst="$2"
    (diff -u "$src" "$dst" 2>/dev/null || true) | awk '/^\+[^+]/ {add++} /^-[^-]/ {del++} END {printf "+%d / -%d", add, del}'
}

# ── Crochets git : le dernier rempart avant un commit ───────────────────────
# `.gitignore` écarte les maquettes et les états locaux, mais `git add -f` passe
# outre. Le crochet versionné (`dev/hooks/pre-commit`) refuse les chemins
# interdits et vérifie la neutralité du dépôt. Il ne sert que si `core.hooksPath`
# pointe dessus — une configuration qui ne suit pas le clone, d'où ce passage à
# chaque déploiement, sur chaque machine.
installer_crochets_git() {
    local racine
    racine="$(git -C "$DEV_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 0
    [ -f "$racine/dev/hooks/pre-commit" ] || return 0
    chmod +x "$racine/dev/hooks/pre-commit" 2>/dev/null || true

    if [ "$(git -C "$racine" config --get core.hooksPath 2>/dev/null)" != "dev/hooks" ]; then
        git -C "$racine" config core.hooksPath dev/hooks
        echo "  ↪ crochets git installés (core.hooksPath = dev/hooks)"
    fi

    # Un hooksPath qui pointe dans le vide ne dit rien et laisse tout passer :
    # c'est le piège que le crochet documente. On le vérifie donc, pas seulement
    # la configuration.
    local pose
    pose="$(git -C "$racine" config --get core.hooksPath 2>/dev/null)"
    if [ ! -x "$racine/${pose:-.git/hooks}/pre-commit" ]; then
        echo "  ⚠️  crochets git inopérants : ${pose:-.git/hooks}/pre-commit absent ou non exécutable"
    fi
}

# ── Neutralité : ni nom d'utilisateur ni nom de machine en dur ──────────────
# Le dépôt doit s'installer chez quelqu'un d'autre. `core/neutralite.py` lit les
# fichiers suivis et cherche le nom de la personne qui lance le déploiement, son
# nom d'hôte, et tout `/home/<nom>` qui n'est pas un espace réservé. Avertissement
# seulement : un déploiement ne doit pas être bloqué par une ligne de commentaire.
verifier_neutralite() {
    local sortie
    if ! sortie="$(python3 "$DEV_DIR/core/neutralite.py" 2>&1)"; then
        echo
        echo "⚠️  Neutralité du dépôt — à corriger avant de publier :"
        echo "$sortie" | sed 's/^/    /'
        echo
    fi
}

# ── Pré-vol : Analyse comparative (Dépôt ➜ Vivant) ──────────────────────────
preflight_diff() {
    verifier_neutralite

    local git_rev origin
    git_rev="$(git -C "$DEV_DIR" rev-parse --short HEAD 2>/dev/null || echo "inconnu")"
    origin="$(detect_origin_type)"

    local -a list_preserved=()
    local -a list_modified=()
    local -a list_added=()
    local -a list_pruned=()
    local -a list_regen=()
    local count_ident=0

    # 1. Hypr modular
    local f name dst stats
    for f in "$DEV_DIR/hypr_modular"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        dst="$CURRENT_HYPR/$name"
        if [ -f "$dst" ]; then
            if est_etat_machine "$name" hypr; then
                if cmp -s "$f" "$dst"; then
                    list_preserved+=("hypr/$name (protégé, identique)")
                else
                    list_preserved+=("hypr/$name (protégé localement, non écrasé)")
                fi
            elif cmp -s "$f" "$dst"; then
                count_ident=$((count_ident + 1))
            else
                case "$name" in
                    colors.lua|programs.lua|autostart_cmds.txt)
                        list_regen+=("hypr/$name (régénéré après déploiement)")
                        ;;
                    *)
                        stats=$(compute_diff_stats "$dst" "$f")
                        list_modified+=("hypr/$name ($stats)")
                        ;;
                esac
            fi
        else
            list_added+=("hypr/$name")
        fi
    done

    # Élagage potentiel dans Hyprland
    if [ -d "$CURRENT_HYPR" ]; then
        for f in "$CURRENT_HYPR"/*; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            [ -f "$DEV_DIR/hypr_modular/$name" ] && continue
            est_etat_machine "$name" hypr && continue
            case "$name" in
                *.upstream|hypridle.conf|hyprlock.conf|hyprlock-colors.conf|autostart_cmds.txt|.quickshell_managed|secrets.json|*_cache.json) continue ;;
            esac
            list_pruned+=("hypr/$name")
        done
    fi

    # 2. Core
    for f in "$DEV_DIR/core"/*; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        dst="$CORE_DIR/$name"
        if [ -f "$dst" ]; then
            if est_etat_machine "$name" core; then
                list_preserved+=("quickshell/core/$name (état local protégé)")
            elif cmp -s "$f" "$dst"; then
                count_ident=$((count_ident + 1))
            else
                stats=$(compute_diff_stats "$dst" "$f")
                list_modified+=("quickshell/core/$name ($stats)")
            fi
        else
            list_added+=("quickshell/core/$name")
        fi
    done

    # Élagage potentiel dans Core
    if [ -d "$CORE_DIR" ]; then
        for f in "$CORE_DIR"/*; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            [ -f "$DEV_DIR/core/$name" ] && continue
            est_etat_machine "$name" core && continue
            case "$name" in
                *.upstream|secrets.json|*_cache.json|flotte.json|app_index.json) continue ;;
            esac
            list_pruned+=("quickshell/core/$name")
        done
    fi

    # 2 bis. Greeter (dev/sddm → quickshell/sddm)
    if [ -d "$DEV_DIR/sddm" ]; then
        for f in "$DEV_DIR/sddm"/*; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            dst="$QS_DIR/sddm/$name"
            if [ -f "$dst" ]; then
                if cmp -s "$f" "$dst"; then
                    count_ident=$((count_ident + 1))
                else
                    stats=$(compute_diff_stats "$dst" "$f")
                    list_modified+=("quickshell/sddm/$name ($stats)")
                fi
            else
                list_added+=("quickshell/sddm/$name")
            fi
        done
        if [ -d "$QS_DIR/sddm" ]; then
            for f in "$QS_DIR/sddm"/*; do
                [ -f "$f" ] || continue
                name="$(basename "$f")"
                [ -f "$DEV_DIR/sddm/$name" ] && continue
                list_pruned+=("quickshell/sddm/$name")
            done
        fi
    fi

    # 3. Root QML & qmldir
    for f in "$DEV_DIR"/*.qml "$DEV_DIR"/qmldir; do
        [ -f "$f" ] || continue
        name="$(basename "$f")"
        dst="$QS_DIR/$name"
        if [ -f "$dst" ]; then
            if cmp -s "$f" "$dst"; then
                count_ident=$((count_ident + 1))
            else
                stats=$(compute_diff_stats "$dst" "$f")
                list_modified+=("quickshell/$name ($stats)")
            fi
        else
            list_added+=("quickshell/$name")
        fi
    done

    # Élagage potentiel dans racine quickshell
    if [ -d "$QS_DIR" ]; then
        for f in "$QS_DIR"/*.qml "$QS_DIR"/qmldir; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            [ -f "$DEV_DIR/$name" ] && continue
            list_pruned+=("quickshell/$name")
        done
    fi

    # 4. Widgets
    if [ -d "$DEV_DIR/widgets" ]; then
        for f in "$DEV_DIR/widgets"/*.qml; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            dst="$QS_DIR/widgets/$name"
            if [ -f "$dst" ]; then
                if cmp -s "$f" "$dst"; then
                    count_ident=$((count_ident + 1))
                else
                    stats=$(compute_diff_stats "$dst" "$f")
                    list_modified+=("quickshell/widgets/$name ($stats)")
                fi
            else
                list_added+=("quickshell/widgets/$name")
            fi
        done
        if [ -d "$QS_DIR/widgets" ]; then
            for f in "$QS_DIR/widgets"/*.qml; do
                [ -f "$f" ] || continue
                name="$(basename "$f")"
                [ -f "$DEV_DIR/widgets/$name" ] && continue
                list_pruned+=("quickshell/widgets/$name")
            done
        fi
    fi

    # 5. Hyprquickpaper
    if [ -d "$DEV_DIR/shaders" ]; then
        mkdir -p "$QS_DIR/shaders"
        cp -f "$DEV_DIR/shaders/"* "$QS_DIR/shaders/" 2>/dev/null || true
    fi

    if [ -d "$DEV_DIR/hyprquickpaper" ]; then
        for f in "$DEV_DIR/hyprquickpaper"/*; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            dst="$QS_DIR/hyprquickpaper/$name"
            if [ -f "$dst" ]; then
                if [ "$name" = "config.json" ] && [ -f "$MARKER" ] && [ "${DEPLOY_OVERWRITE:-0}" != "1" ]; then
                    list_preserved+=("quickshell/hyprquickpaper/config.json (config utilisateur protégée)")
                elif cmp -s "$f" "$dst"; then
                    count_ident=$((count_ident + 1))
                else
                    stats=$(compute_diff_stats "$dst" "$f")
                    list_modified+=("quickshell/hyprquickpaper/$name ($stats)")
                fi
            else
                list_added+=("quickshell/hyprquickpaper/$name")
            fi
        done
    fi

    # 6. Systemd services
    if [ -d "$DEV_DIR/systemd" ]; then
        for f in "$DEV_DIR/systemd"/*.service; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            dst="$HOME/.config/systemd/user/$name"
            if [ -f "$dst" ]; then
                if cmp -s "$f" "$dst"; then
                    count_ident=$((count_ident + 1))
                else
                    stats=$(compute_diff_stats "$dst" "$f")
                    list_modified+=("systemd/user/$name ($stats)")
                fi
            else
                list_added+=("systemd/user/$name")
            fi
        done
    fi

    # ── AFFICHAGE DU RAPPORT ────────────────────────────────────────────────
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_CYAN}${C_BOLD}PRÉ-VOL : ANALYSE DES MODIFICATIONS (Dépôt ➜ Vivant)${C_RESET}"
    echo -e "  Cible : ${DISTRO_TITLE} (${FORM_TITLE}) | Origine : ${origin} | Git : ${git_rev}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"

    if [ ${#list_preserved[@]} -gt 0 ]; then
        echo -e "${C_GREEN}${C_BOLD}  🟢 Fichiers préservés (états locaux protégés, non écrasés) :${C_RESET}"
        for item in "${list_preserved[@]}"; do
            echo -e "     ${C_GREEN}✓${C_RESET} $item"
        done
    fi

    if [ ${#list_modified[@]} -gt 0 ]; then
        echo -e "${C_YELLOW}${C_BOLD}  🟡 Fichiers modifiés (seront mis à jour) :${C_RESET}"
        for item in "${list_modified[@]}"; do
            echo -e "     ${C_YELLOW}⤾${C_RESET} $item"
        done
    fi

    if [ ${#list_added[@]} -gt 0 ]; then
        echo -e "${C_BLUE}${C_BOLD}  🔵 Nouveaux fichiers (seront créés/installés) :${C_RESET}"
        for item in "${list_added[@]}"; do
            echo -e "     ${C_BLUE}+${C_RESET} $item"
        done
    fi

    if [ ${#list_regen[@]} -gt 0 ]; then
        echo -e "${C_CYAN}${C_BOLD}  ⚙️  Fichiers régénérés automatiquement (post-déploiement) :${C_RESET}"
        for item in "${list_regen[@]}"; do
            echo -e "     ${C_CYAN}⚙${C_RESET} $item"
        done
    fi

    if [ ${#list_pruned[@]} -gt 0 ]; then
        echo -e "${C_RED}${C_BOLD}  🔴 Fichiers orphelins (seront archivés dans backups_env/pruned_*) :${C_RESET}"
        for item in "${list_pruned[@]}"; do
            echo -e "     ${C_RED}✗${C_RESET} $item"
        done
    else
        echo -e "${C_DIM}  ⚪ Aucun fichier orphelin à élaguer.${C_RESET}"
    fi

    echo -e "${C_BOLD}──────────────────────────────────────────────────────────────────────────────${C_RESET}"
    printf "  ${C_BOLD}Bilan :${C_RESET} %d identiques | ${C_YELLOW}%d modifiés${C_RESET} | ${C_BLUE}%d nouveaux${C_RESET} | ${C_GREEN}%d préservés${C_RESET} | ${C_RED}%d à élaguer${C_RESET}\n" \
        "$count_ident" "${#list_modified[@]}" "${#list_added[@]}" "${#list_preserved[@]}" "${#list_pruned[@]}"
    echo -e "${C_BOLD}══════════════════════════════════════════════════════════════════════════════${C_RESET}"
}

BACKUP_OK=0
backup_env() {
    BACKUP_OK=0
    local stamp archive contenu
    stamp=$(date +%Y%m%d_%H%M%S)
    archive="$BACKUP_DIR/backup_${DISTRO}_hq_$stamp.tar.gz"
    if ! tar -czf "$archive" -C "$HOME/.config" hypr quickshell 2>/dev/null; then
        rm -f "$archive"
        echo "⚠️ Backup failed, nothing written."
        return 1
    fi
    # Une sauvegarde doit contenir les DEUX arbres : un « HQ » reduit a Hyprland
    # restaurerait une moitie de configuration, et l'alias pointerait dessus.
    # Listing dans une variable : sous `set -o pipefail`, un `tar | grep -q`
    # renvoie 141 des que grep sort, donc un faux negatif.
    contenu=$(tar -tzf "$archive" 2>/dev/null || true)
    if ! grep -q '^hypr/' <<<"$contenu" || ! grep -q '^quickshell/' <<<"$contenu"; then
        rm -f "$archive"
        echo "⚠️ Backup incomplete (hypr ou quickshell manquant), archive retiree."
        return 1
    fi
    # Manifeste a côté de l'archive : liste des fichiers et leur empreinte, pour
    # pouvoir comparer sans extraire ni restaurer. Le tar reste la source de
    # vérité ; le manifeste n'est qu'un index lisible.
    ( cd "$HOME/.config" && find hypr quickshell -type f -print0 2>/dev/null \
        | sort -z | xargs -0 sha256sum 2>/dev/null ) > "$archive.manifeste" || true

    cp -f "$archive" "$HQ_ALIAS"
    echo "✅ HQ saved: $(basename "$archive") ($(du -h "$archive" | cut -f1))"
    rotate_backups

    # Création simultanée du snapshot fin décompressé
    create_fine_snapshot "$stamp"

    BACKUP_OK=1
}

# ── inspecter une sauvegarde sans la restaurer ──────────────────────────────
# Le déploiement archivait tout ou rien : impossible de savoir ce qui changeait,
# ni de récupérer un seul fichier. Ces trois fonctions ouvrent l'archive.
hq_derniere() {
    find "$BACKUP_DIR" -maxdepth 1 -name "backup_*_hq_20*.tar.gz" -printf "%T@ %p\n" 2>/dev/null \
        | sort -nr | head -1 | awk '{print $2}'
}

hq_lister() {
    local arch="${1:-$(hq_derniere)}"
    [ -f "$arch" ] || { echo "❌ Archive introuvable : ${arch:-aucune}" >&2; return 1; }
    tar -tzf "$arch" 2>/dev/null | grep -v '/$'
}

hq_diff() {
    local arch="${1:-$(hq_derniere)}" manifeste
    [ -f "$arch" ] || { echo "❌ Archive introuvable : ${arch:-aucune}" >&2; return 1; }
    manifeste="$arch.manifeste"

    # Avec le manifeste, on compare des empreintes : rien à décompresser, donc
    # instantané et sans écrire des centaines de fichiers dans un dossier
    # temporaire. Sans manifeste (archives antérieures), on retombe sur
    # l'extraction — le résultat est le même, seulement plus lent.
    if [ -f "$manifeste" ]; then
        echo "Comparaison avec $HOME/.config (archive ➜ vivant) :"
        local somme chemin vue
        while read -r somme chemin; do
            [ -n "$chemin" ] || continue
            if [ ! -f "$HOME/.config/$chemin" ]; then
                echo "  $chemin : absent du vivant"
            elif [ "$(sha256sum "$HOME/.config/$chemin" 2>/dev/null | cut -d' ' -f1)" != "$somme" ]; then
                echo "  $chemin : différent"
            fi
        done < "$manifeste"
        # Et l'inverse : ce qui existe aujourd'hui sans être dans la sauvegarde.
        ( cd "$HOME/.config" && find hypr quickshell -type f -print0 2>/dev/null \
            | sort -z | xargs -0 sha256sum 2>/dev/null ) \
        | while read -r _somme _chemin; do
            grep -qF "  $_chemin" "$manifeste" || echo "  $_chemin : absent de l archive"
        done
        return 0
    fi

    local tmp
    tmp=$(mktemp -d)
    tar -xzf "$arch" -C "$tmp" || { rm -rf "$tmp"; return 1; }
    echo "Comparaison avec $HOME/.config (archive ➜ vivant) :"
    for arbre in hypr quickshell; do
        diff -rq "$tmp/$arbre" "$HOME/.config/$arbre" 2>/dev/null \
            | sed -E "s#^Les fichiers $tmp/(.*) et .* sont différents#\1 : différent#; s#^Only in $HOME/.config/(.*)#\1 : absent de l archive#" \
            | sed 's/^/  /'
    done
    rm -rf "$tmp"
}

hq_get() {
    local arch="${1:-$(hq_derniere)}" chemin="$2"
    [ -f "$arch" ] || { echo "❌ Archive introuvable : $arch" >&2; return 1; }
    [ -n "$chemin" ] || { echo "❌ Chemin manquant (ex. quickshell/Theme.qml)" >&2; return 1; }
    case "$chemin" in
        /*|*..*) echo "❌ Chemin refusé : $chemin" >&2; return 1 ;;
    esac
    # Listing capturé AVANT le grep : `tar | grep -q` renvoie 141 sous
    # `set -o pipefail` dès que grep sort, donc un faux « absent ».
    local contenu
    contenu=$(tar -tzf "$arch" 2>/dev/null || true)
    grep -qxF "$chemin" <<<"$contenu" \
        || { echo "❌ $chemin n'est pas dans l'archive" >&2; return 1; }
    # Rien n'est écrit dans ~/.config : on extrait sous BACKUP_DIR pour que
    # l'utilisateur voie le fichier et décide lui-même de le remettre en place.
    mkdir -p "$BACKUP_DIR/extrait"
    tar -xzf "$arch" -C "$BACKUP_DIR/extrait" "$chemin" \
        && echo "✅ $chemin extrait dans $BACKUP_DIR/extrait/$chemin"
}

# Retour a une version anterieure de HQ : on liste les sauvegardes datees, on
# demande laquelle, et on sauvegarde l'etat courant avant d'ecraser — un retour
# en arriere qui ne pourrait pas etre annule ne serait pas un filet de securite.
restore_hq() {
    local -a archives=()
    # Tri par date de fichier, pas par nom : les sauvegardes ne portent pas toutes
    # le meme prefixe de distribution, et « arch » passerait apres « station ».
    mapfile -t archives < <(find "$BACKUP_DIR" -maxdepth 1 -name "backup_*_hq_20*.tar.gz" -printf "%T@ %p\n" 2>/dev/null | sort -nr | awk '{print $2}')
    if [ "${#archives[@]}" -eq 0 ]; then
        echo "⚠️ No dated HQ backup in $BACKUP_DIR."
        return 1
    fi
    echo "HQ backups, newest first:"
    local i nom brut lisible
    for i in "${!archives[@]}"; do
        nom=$(basename "${archives[$i]}")
        brut="${nom##*_hq_}"; brut="${brut%.tar.gz}"
        lisible=$(date -d "${brut:0:8} ${brut:9:2}:${brut:11:2}:${brut:13:2}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$brut")
        printf ' %2d > %s  %6s  %s\n' "$((i+1))" "$lisible" \
            "$(du -h "${archives[$i]}" | cut -f1)" "$nom"
    done
    echo "  s > Cancel"
    read -p "Restore which version ? " choice
    case "$choice" in
        s|S|"") echo "⏭️ Cancelled."; return 0 ;;
    esac
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#archives[@]}" ]; then
        echo "⚠️ Invalid choice, nothing done."
        return 1
    fi
    local cible="${archives[$((choice - 1))]}"
    # Pas d'ecrasement sans filet : si la sauvegarde de l'etat courant echoue, on
    # ne restaure rien.
    if ! backup_env; then
        echo "⚠️ Restore annule : l'etat courant n'a pas pu etre sauvegarde."
        return 1
    fi
    echo "↪ restoring $(basename "$cible")..."
    tar -xzf "$cible" -C "$HOME/.config" || { echo "⚠️ Restore failed."; return 1; }
    touch "$MARKER"
    echo "✅ HQ restored from $(basename "$cible")."
    # Hyprland surveille ses fichiers : pendant l'extraction il peut recharger une
    # configuration a moitie reecrite (d'ou un « cannot open hyprland.lua » sans
    # consequence). On recharge proprement a la fin pour laisser un etat net.
    if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
        echo "   Hyprland reloaded."
    else
        echo "   Reload Hyprland yourself: hyprctl reload"
    fi
    echo "   Quickshell keeps the old code until you restart it."
    rotate_backups
    return 0
}


# Ghostty n'est pas géré par le dépôt : Ryoku pose sa configuration et sa palette
# (matugen). Mais le flou derrière la fenêtre dépend d'un réglage que Ghostty ne
# demande pas de lui-même, et `user.conf` est le seul fichier inclus en dernier —
# donc celui qui survit aux régénérations de palette. On l'assure à chaque
# déploiement pour que le réglage existe aussi sur l'autre machine, sans écraser
# les lignes déjà personnalisées.
deploy_ghostty_overrides() {
    command -v ghostty >/dev/null 2>&1 || return 0
    local source="$DEV_DIR/ghostty/user.conf"
    [ -f "$source" ] || return 0
    local dir="$HOME/.config/ghostty"
    local cible="$dir/user.conf"
    mkdir -p "$dir"

    if [ ! -f "$cible" ]; then
        cp "$source" "$cible"
        echo "  ↪ ghostty : user.conf créé (flou derrière la fenêtre)"
        return 0
    fi
    grep -qE '^[[:space:]]*background-blur[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$cible" || {
        if grep -qE '^[[:space:]]*background-blur' "$cible"; then
            sed -i -E 's/^[[:space:]]*background-blur.*/background-blur = true/' "$cible"
            echo "  ↪ ghostty : background-blur remis à true"
        else
            echo "background-blur = true" >> "$cible"
            echo "  ↪ ghostty : background-blur ajouté à user.conf"
        fi
    }

    if ! grep -qE '^[[:space:]]*theme[[:space:]]*=' "$cible"; then
        echo "theme = aethershell" >> "$cible"
        echo "  ↪ ghostty : theme = aethershell ajouté à user.conf"
    fi
}

# Flou des fenêtres GTK4 → ~/.config/gtk-4.0/aethershell-flou.css.
#
# Depuis GTK 4.24, GTK déclare une région de flou **vide** pour chaque surface
# (ext-background-effect-v1) : Hyprland lit cela comme « ne me floute pas » et
# cesse de flouter toutes les fenêtres GTK4. Le fichier livré ne fait que
# déclarer la région (`backdrop-filter`) ; l'intensité reste celle du
# compositeur. Détail complet dans core/gtk4-flou.css.
#
# Le gtk.css de la session n'est **jamais réécrit** : on y ajoute un `@import`
# s'il manque, une seule fois. Un fichier absent est créé vide.
poser_flou_gtk4() {
    local source="$DEV_DIR/core/gtk4-flou.css"
    local dossier="$HOME/.config/gtk-4.0"
    local css="$dossier/gtk.css"
    [ -f "$source" ] || return 0
    mkdir -p "$dossier"
    cp -f "$source" "$dossier/aethershell-flou.css" || return 0
    [ -f "$css" ] || : > "$css"
    if ! grep -qF "aethershell-flou.css" "$css"; then
        printf "\n@import 'aethershell-flou.css';\n" >> "$css"
        echo "  ↪ flou GTK4 : @import ajouté à ~/.config/gtk-4.0/gtk.css"
    fi
}

# Version déployée → $CORE_DIR/version.json.
#
# Le dossier cible n'est pas un dépôt git : déployé, le shell ne peut pas
# répondre seul à « quelle version tourne ? ». Le panneau (« Écrans & Système »)
# l'affiche et `core/maj_shell.py` la compare au dernier tag publié sur GitHub.
# C'est un état de la machine, comme les autres .json non livrés de core/ :
# `est_etat_machine` le protège, donc aucune version ultérieure ne l'écrase ni
# ne l'élague — il est réécrit à chaque déploiement, et c'est voulu.
ecrire_version_deployee() {
    local tag="" commit="" decrite=""
    if git -C "$DEV_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        commit="$(git -C "$DEV_DIR" rev-parse --short HEAD 2>/dev/null || true)"
        tag="$(git -C "$DEV_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
        decrite="$(git -C "$DEV_DIR" describe --tags --always --dirty 2>/dev/null || true)"
    fi
    printf '{"version": "%s", "tag": "%s", "commit": "%s", "deploye_le": "%s"}\n' \
        "$decrite" "$tag" "$commit" "$(date -Iseconds)" \
        > "$CORE_DIR/version.json.new" || return 0
    mv -f "$CORE_DIR/version.json.new" "$CORE_DIR/version.json" || true
}

# Action polkit + helper root de la limite de charge (dev/charge-limit).
#
# Ils vivent hors de ~/.config : /usr/local/bin, /usr/share/polkit-1/actions,
# /etc/polkit-1/rules.d — donc root, donc pkexec. L'élévation n'est demandée que
# si les trois sources ont changé depuis la dernière installation : une machine
# à jour ne voit aucune invite à chaque déploiement. L'empreinte est retenue
# dans le cache, pas dans ~/.config/quickshell (que l'élagage nettoierait).
installer_charge_limit() {
    [ "$FORM_FACTOR" = "laptop" ] || return 0
    local dir="$DEV_DIR/charge-limit"
    [ -f "$dir/install.sh" ] || return 0

    local stamp="$HOME/.cache/quickshell/charge-limit.stamp" courant
    courant=$(cat "$dir/aether-charge-limit" \
                  "$dir/org.aethershell.charge.policy" \
                  "$dir/50-aethershell-charge.rules" | sha256sum | cut -d' ' -f1)
    if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$courant" ]; then
        return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
        echo "  ⚙ charge-limit : action polkit et helper à installer (root)"
        return 0
    fi
    if command -v pkexec >/dev/null 2>&1; then
        if pkexec bash "$dir/install.sh"; then
            mkdir -p "$(dirname "$stamp")" \
                && printf '%s\n' "$courant" > "$stamp"
        else
            echo "  ⚠ limite de charge non installée — à lancer à la main : sudo bash $dir/install.sh"
        fi
    else
        echo "  ⚠ pkexec absent : limite de charge non installée (sudo bash $dir/install.sh)"
    fi
}

deploy_new_env() {
    echo "🚀 Deploying $DISTRO_TITLE ($FORM_TITLE)..."

    mkdir -p "$CURRENT_HYPR"
    if [ ! -f "$MARKER" ]; then
        if [ "$BACKUP_OK" = "1" ]; then
            echo "ℹ️ Aucun marqueur Quickshell dans $CURRENT_HYPR : sauvegarde effectuée (backup done)."
        else
            echo "ℹ️ Aucun marqueur Quickshell dans $CURRENT_HYPR : configuration initiale."
        fi
        echo "   Les fichiers d'état existants (style_vars, general.lua, binds.lua...) restent préservés."
    fi

    copy_dir_files "$DEV_DIR/hypr_modular" "$CURRENT_HYPR" "$PRESERVE_HYPR"
    local hypr_manifest
    hypr_manifest=$(mktemp)
    (cd "$DEV_DIR/hypr_modular" && ls -1) > "$hypr_manifest"
    prune_target "$CURRENT_HYPR" "$hypr_manifest" "$PRESERVE_HYPR"
    rm -f "$hypr_manifest"
    chmod +x "$CURRENT_HYPR/"*.sh 2>/dev/null || true

    mkdir -p "$CORE_DIR"
    copy_dir_files "$DEV_DIR/core" "$CORE_DIR" "$PRESERVE_CORE"
    local core_manifest
    core_manifest=$(mktemp)
    (cd "$DEV_DIR/core" && ls -1) > "$core_manifest"
    prune_target "$CORE_DIR" "$core_manifest" "$PRESERVE_CORE"
    rm -f "$core_manifest"

    # Le greeter part avec le shell (`~/.config/quickshell/sddm`) : le module le
    # cherchait dans le clone et, à défaut, parcourait tout le home. Sur une
    # machine où le shell est seulement déployé, refresh de palette, miniatures,
    # installation et désinstallation échouaient. Seuls les fichiers sont copiés :
    # `out/`, `preview/` et `__pycache__` sont des sorties de l'outil.
    if [ -d "$DEV_DIR/sddm" ]; then
        mkdir -p "$QS_DIR/sddm/out/Themes" "$QS_DIR/sddm/out/Backgrounds"
        for f in "$DEV_DIR/sddm"/*; do
            [ -f "$f" ] || continue
            cp -f "$f" "$QS_DIR/sddm/"
        done
        chmod +x "$QS_DIR/sddm/install.sh" "$QS_DIR/sddm/greeter-palette" 2>/dev/null || true
    fi
    # La liste des dépendances part avec le shell : le panneau (« Installer les
    # paquets manquants », onglet Apps & Alertes) la lit à l'exécution dans
    # core/dependencies.txt, sans savoir où le dépôt a été cloné. Copiée **après**
    # l'élagage : elle ne vit plus dans core/ au dépôt, une seule source à la
    # racine, et l'élagage l'aurait retirée de la cible juste après la copie.
    cp -f "$DEPS_FILE" "$CORE_DIR/dependencies.txt" || true
    # Quelle version vient d'être posée : le dossier déployé n'est pas un dépôt
    # git, le panneau et core/maj_shell.py n'ont que ce fichier pour le savoir.
    ecrire_version_deployee
    # Flou des fenêtres GTK4 (région `backdrop-filter` demandée au compositeur).
    poser_flou_gtk4
    # Index des applications de la pilule spotlight : données de la machine,
    # pas du dépôt — régénérées à chaque déploiement (et à chaque ouverture).
    if [ -f "$CORE_DIR/app_index.py" ]; then
        python3 "$CORE_DIR/app_index.py" --quiet || true
    fi
    build_pwscope_if_ready

    # Fichiers générés à partir des JSON préservés (app_vars.json, autostart.json) :
    # la copie ci-dessus peut poser la version du dépôt, on réécrit la vraie.
    if [ -f "$CORE_DIR/config_manager.py" ]; then
        python3 "$CORE_DIR/config_manager.py" sync_generated >/dev/null 2>&1 \
            || echo "  ⚠️  régénération de programs.lua / autostart_cmds.txt impossible"
    fi
    if [ ! -f "$CORE_DIR/secrets.json" ] && [ -f "$CORE_DIR/secrets.example.json" ]; then
        cp "$CORE_DIR/secrets.example.json" "$CORE_DIR/secrets.json"
    fi
    chmod +x "$CORE_DIR/"*.sh

    # Tous les composants de la racine, en bloc. La liste fixe oubliait chaque
    # nouveau fichier (Popup.qml, HermesPopup.qml) alors que le qmldir, lui,
    # était copié : la barre tombait au redémarrage sur « Popup is not a type ».
    # `prune_target` juste en dessous retire ce qui a disparu du dépôt.
    cp -f "$DEV_DIR/"*.qml "$QS_DIR/"
    cp -f "$DEV_DIR/qmldir" "$QS_DIR/qmldir"

    # Icônes de substitution du systray (core/tray_icons.json y renvoie).
    if [ -d "$DEV_DIR/assets/tray" ]; then
        mkdir -p "$QS_DIR/assets/tray"
        cp -f "$DEV_DIR/assets/tray/"* "$QS_DIR/assets/tray/" 2>/dev/null || true
    fi

    # Widgets de bureau : un composant par type, chargés par URL depuis
    # `widgets/<type>.qml` — donc copiés en bloc, et sans entrée qmldir.
    if [ -d "$DEV_DIR/widgets" ]; then
        mkdir -p "$QS_DIR/widgets"
        cp -f "$DEV_DIR/widgets/"*.qml "$QS_DIR/widgets/" 2>/dev/null || true
        # Un composant retiré du dépôt doit disparaître de la cible : il n'est
        # plus chargé, mais un fichier orphelin se relit comme s'il servait
        # encore (les widgets deepseek/ollama/antigravity sont devenus llm.qml).
        local w_manifest
        w_manifest=$(mktemp)
        (cd "$DEV_DIR/widgets" && ls -1 *.qml 2>/dev/null) > "$w_manifest"
        prune_target "$QS_DIR/widgets" "$w_manifest"
        rm -f "$w_manifest"
    fi

    local qs_manifest
    qs_manifest=$(mktemp)
    (cd "$DEV_DIR" && ls -1 *.qml qmldir 2>/dev/null) > "$qs_manifest"
    prune_target "$QS_DIR" "$qs_manifest"
    rm -f "$qs_manifest"

    # Chaque entrée du qmldir doit avoir son fichier en face. Sans ce contrôle,
    # « deployment complete » pouvait masquer une barre cassée au redémarrage :
    # un composant annoncé mais absent fait échouer le chargement du shell.
    local manquants=0 file
    while read -r file; do
        [ -f "$QS_DIR/$file" ] || {
            echo "  ❌ qmldir référence $file, absent de $QS_DIR"
            manquants=$((manquants + 1))
        }
    done < <(awk '$NF ~ /\.qml$/ {print $NF}' "$QS_DIR/qmldir")
    if [ "$manquants" -gt 0 ]; then
        echo "  ⚠️  $manquants composant(s) manquant(s) : le shell échouera au démarrage"
        return 1
    fi

    # Chaque script core/ cité par le QML doit exister. Un fichier oublié dans la
    # copie, ou un nom mal orthographié, ne se voit qu'au moment où l'applet
    # l'appelle — donc jamais, tant qu'on n'ouvre pas ce popup.
    local absents_scripts=0 ref
    # Seules les références qui existent dans le dépôt comptent : un nom cité
    # dans un commentaire (core/_service.py dans llm.qml) n'est pas une copie
    # manquée, et le signaler noierait le vrai défaut sous du bruit.
    for ref in $(grep -rhoE 'core/[A-Za-z0-9_]+\.(py|sh)' "$QS_DIR"/*.qml "$QS_DIR"/widgets/*.qml 2>/dev/null | sort -u); do
        [ -f "$DEV_DIR/$ref" ] || continue
        [ -f "$QS_DIR/$ref" ] || {
            echo "  ❌ le QML appelle $ref, présent au dépôt mais absent de $QS_DIR"
            absents_scripts=$((absents_scripts + 1))
        }
    done
    if [ "$absents_scripts" -gt 0 ]; then
        echo "  ⚠️  $absents_scripts script(s) manquant(s) : l'applet échouera à l'usage"
        return 1
    fi

    if [ -d "$DEV_DIR/shaders" ]; then
        mkdir -p "$QS_DIR/shaders"
        cp -f "$DEV_DIR/shaders/"* "$QS_DIR/shaders/" 2>/dev/null || true
    fi

    if [ -d "$DEV_DIR/hyprquickpaper" ]; then
        mkdir -p "$QS_DIR/hyprquickpaper"
        if [ ! -f "$MARKER" ] || [ ! -f "$QS_DIR/hyprquickpaper/config.json" ] || [ "${DEPLOY_OVERWRITE:-0}" = "1" ]; then
            cp "$DEV_DIR/hyprquickpaper/config.json" "$QS_DIR/hyprquickpaper/config.json"
        else
            sync_file "$DEV_DIR/hyprquickpaper/config.json" "$QS_DIR/hyprquickpaper/config.json"
        fi
        cp "$DEV_DIR/hyprquickpaper/colors.json" "$QS_DIR/hyprquickpaper/colors.json"
        cp "$DEV_DIR/hyprquickpaper/shell.qml" "$QS_DIR/hyprquickpaper/shell.qml"
        cp "$DEV_DIR/hyprquickpaper/cache.sh" "$QS_DIR/hyprquickpaper/cache.sh"
        cp "$DEV_DIR/hyprquickpaper/commands.sh" "$QS_DIR/hyprquickpaper/commands.sh"
        chmod +x "$QS_DIR/hyprquickpaper/cache.sh" "$QS_DIR/hyprquickpaper/commands.sh"
    fi

    # Unités systemd utilisateur : quickshell et le canal d'approbation Hermes
    # doivent survivre à un redémarrage de session, et se relancer seuls en cas
    # de plantage. Versionnées ici, installées par le déploiement.
    if [ -d "$DEV_DIR/systemd" ]; then
        local unite
        for unite in "$DEV_DIR/systemd/"*.service; do
            [ -f "$unite" ] || continue
            cp -f "$unite" "$HOME/.config/systemd/user/"
            echo "  ↪ unité installée : $(basename "$unite")"
        done
        systemctl --user daemon-reload 2>/dev/null || true
        # Une unité copiée mais jamais activée ne sert à rien : `enable` la rend
        # persistante, `--now` la démarre sans attendre la prochaine session.
        # L'agent polkit en dépend : sans lui, `pkexec` n'a personne à qui
        # demander l'autorisation, et les écritures dans /sys (limite de charge
        # à 80 %) échouent sans un mot.
        if [ -f "$HOME/.config/systemd/user/polkit-agent.service" ]; then
            systemctl --user enable --now polkit-agent.service 2>/dev/null \
                || echo "  ⚠ agent polkit non démarré (systemctl --user enable --now polkit-agent)"
        fi
    fi

    installer_charge_limit

    installer_crochets_git

    "$CORE_DIR/generate_rofi_theme.sh"

    deploy_ghostty_overrides

    # ── rechargement de la session, sans intervention ───────────────────────
    # Déployer sans relire la config laissait l'utilisateur devant un écran qui
    # affichait l'ancienne version jusqu'à sa prochaine déconnexion. On recharge
    # donc Hyprland puis quickshell ici. L'unité systemd est prioritaire ; le
    # lancement direct ne sert que si elle n'existe pas encore (première install).
    recharger_session() {
        local sig
        sig=$( (ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null || true) | head -1)
        if [ -z "$sig" ]; then
            echo "  ↪ session Hyprland introuvable : rechargement sauté"
            return 0
        fi
        export HYPRLAND_INSTANCE_SIGNATURE="$sig"

        if command -v hyprctl >/dev/null 2>&1; then
            if hyprctl reload >/dev/null 2>&1; then
                echo "  ↪ Hyprland rechargé"
            else
                echo "  ↪ hyprctl reload a échoué (session sans Hyprland actif ?)"
            fi
        fi

        if command -v systemctl >/dev/null 2>&1 \
           && systemctl --user cat quickshell.service >/dev/null 2>&1; then
            # Tuer d'éventuelles instances lancées hors unité systemd seulement si
            # le service n'est pas actif : sinon `pkill -x quickshell` abattrait le
            # service (et tout son CGroup) avant même `systemctl restart`.
            if ! systemctl --user is-active --quiet quickshell.service; then
                pkill -x quickshell 2>/dev/null || true
                sleep 0.4
            fi
            if grep -q "quickshell.service" /proc/$$/cgroup 2>/dev/null \
               && command -v systemd-run >/dev/null 2>&1; then
                if systemd-run --user --quiet -- systemctl --user restart quickshell.service; then
                    echo "  ↪ quickshell relancé (unité systemd, hors CGroup)"
                else
                    echo "  ⚠️  redémarrage de quickshell.service impossible"
                fi
            elif systemctl --user restart quickshell.service; then
                echo "  ↪ quickshell relancé (unité systemd)"
            else
                echo "  ⚠️  redémarrage de quickshell.service impossible"
            fi
        elif command -v quickshell >/dev/null 2>&1; then
            pkill -x quickshell 2>/dev/null || true
            sleep 1
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
                setsid quickshell -n >/dev/null 2>&1 &
            echo "  ↪ quickshell relancé (sans unité)"
        fi

        # Vérification : une barre absente est le seul vrai symptôme d'échec.
        sleep 3
        if command -v hyprctl >/dev/null 2>&1; then
            if [ "$(hyprctl layers 2>/dev/null | grep -c 'namespace: shell-bar')" -ge 1 ]; then
                echo "  ✓ barre présente"
            else
                echo "  ⚠️  aucune couche shell-bar : vérifier le journal de quickshell"
            fi
        fi
    }

    # Le marqueur n'est posé qu'après un déploiement réussi : son absence ici
    # signifie « installation neuve ». On le note avant de le créer.
    local premiere_fois=0
    [ -f "$MARKER" ] || premiere_fois=1
    touch "$MARKER"

    recharger_session

    echo "✅ $DISTRO_TITLE ($FORM_TITLE) deployment complete."
    if [ "${OFFLINE_FALLBACK:-0}" = "1" ] || [ "${MISSING_DEPS_WARN:-0}" = "1" ]; then
        echo ""
        echo "⚠️  Rappel (installation locale / dépendances manquantes) :"
        echo "   Pensez à vérifier et installer les dépendances système une fois connecté via le panneau de configuration :"
        echo "   SUPER + SHIFT + H  ➜  onglet « Apps & Alertes »  ➜  « Installer les paquets manquants »"
    fi

    # Installation neuve : dire où sont les raccourcis. La barre est lancée par
    # l'autostart de Hyprland, pas par ce script — on laisse donc passer quelques
    # secondes avant de notifier, sinon le message part avant que le serveur de
    # notifications n'existe et personne ne le voit. `systemd-run` porte le délai
    # même si le terminal est fermé entre-temps.
    if [ "$premiere_fois" = "1" ]; then
        echo "   SUPER + K   tous les raccourcis"
        echo "   SUPER + H   panneau étendu de l'îlot"
        echo "   SUPER + SHIFT + H   panneau de réglages"
        echo "   SUPER + S   captures d'écran et vidéos"
        echo "   SUPER + SHIFT + S   région copiée au presse-papiers"
        systemd-run --user --collect --quiet --on-active=8 --unit="qs-welcome-$$" \
            notify-send -a "Installation" \
                "AetherShell est prêt" \
                "SUPER + K : tous les raccourcis — SUPER + H : îlot — SUPER + SHIFT + H : réglages — SUPER + SHIFT + S : captures" \
            >/dev/null 2>&1 || true
    fi
}

# Entrée de menu : gestion des snapshots fins
gerer_snapshots_menu() {
    while true; do
        echo ""
        snapshots_lister
        echo "Actions sur les snapshots fins :"
        echo " 1 > Lister les fichiers d'un snapshot"
        echo " 2 > Diff d'un fichier (Snapshot ➜ Vivant)"
        echo " 3 > Restaurer un fichier unique"
        echo " s > Retour au menu principal"
        read -p "Choix : " s_choice
        case "$s_choice" in
            1)
                read -p "Nom du snapshot (ex: 20261109_162000 ou 'latest') [latest] : " s_target
                s_target="${s_target:-latest}"
                local s_path="$SNAPSHOT_DIR/$s_target"
                [ -e "$s_path" ] || { echo "❌ Snapshot introuvable."; continue; }
                echo "Fichiers dans le snapshot $s_target :"
                find -L "$s_path" -type f ! -name "manifest.json" ! -name "checksums.sha256" | sed "s#^$s_path/##" | sort
                ;;
            2)
                read -p "Chemin du fichier (ex: quickshell/Theme.qml) : " f_path
                [ -n "$f_path" ] || continue
                read -p "Depuis le snapshot [latest] : " s_target
                s_target="${s_target:-latest}"
                local s_path="$SNAPSHOT_DIR/$s_target"
                local clean_p="${f_path#$HOME/.config/}"
                clean_p="${clean_p#/}"
                local sf=""
                for cand in "$s_path/$clean_p" "$s_path/quickshell/$clean_p" "$s_path/hypr/$clean_p"; do
                    if [ -f "$cand" ]; then sf="$cand"; break; fi
                done
                if [ -z "$sf" ]; then
                    echo "❌ Fichier introuvable dans le snapshot $s_target."
                    continue
                fi
                local live="$HOME/.config/$clean_p"
                [ -f "$live" ] || { echo "ℹ️ Fichier absent du vivant ($live)."; continue; }
                echo "Diff : Snapshot ➜ Vivant :"
                diff -u "$sf" "$live" || true
                ;;
            3)
                read -p "Fichier à restaurer (ex: quickshell/core/style_vars.json) : " f_path
                [ -n "$f_path" ] || continue
                read -p "Depuis le snapshot [latest] : " s_target
                restore_snapshot_file "$f_path" "${s_target:-latest}"
                ;;
            s|S|q|Q|"")
                return 0
                ;;
            *)
                echo "Choix invalide."
                ;;
        esac
    done
}

if [ "${DIFF_ONLY:-0}" = "1" ]; then
    preflight_diff
    exit 0
fi

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "🔍 Mode Dry-Run (aucune modification ne sera effectuée)."
    check_dependencies
    preflight_diff
    exit 0
fi

if [ "${SNAPSHOTS_ACTION:-}" = "list" ]; then
    snapshots_lister
    exit 0
elif [ "${SNAPSHOTS_ACTION:-}" = "restore_file" ]; then
    restore_snapshot_file "$RESTORE_FILE" "$RESTORE_SNAP"
    exit $?
fi

# Déploiement direct sans sauvegarde préalable
deploy_only() {
    echo "⚡ Déploiement direct sans nouvelle sauvegarde..."
    deploy_new_env
}

if [ "${INSTALL_DEPS_ONLY:-0}" = "1" ]; then
    check_dependencies
    exit $?
fi

if [ "${AUTO_DEPLOY:-0}" = "1" ]; then
    if check_dependencies; then
        preflight_diff
        if [ "${NO_BACKUP:-0}" = "1" ]; then
            echo "⚡ Déploiement sans sauvegarde (--no-backup demandée)..."
        else
            [ "${BACKUP_OK:-0}" = "1" ] || backup_env
        fi
        deploy_new_env
        exit 0
    else
        exit 1
    fi
fi

if [ "${DO_BACKUP:-0}" = "1" ]; then
    backup_env
    exit 0
fi

if [ -n "${HQ_ACTION:-}" ]; then
    case "$HQ_ACTION" in
        list) hq_lister "${HQ_ARG1:-}" ;;
        diff) hq_diff "${HQ_ARG1:-}" ;;
        get)  hq_get "${HQ_ARG1:-}" "${HQ_ARG2:-}" ;;
    esac
    exit $?
fi

# Entrée de menu : voir ce qui a changé depuis une sauvegarde, puis récupérer
# un seul fichier si besoin. Rien n'est écrit dans ~/.config ici.
inspecter_hq() {
    local arch chemin
    arch="$(hq_derniere)"
    [ -f "$arch" ] || { echo "⚠️  Aucune sauvegarde HQ datée dans $BACKUP_DIR."; return 1; }
    echo "Archive : $(basename "$arch")"
    hq_diff "$arch"
    read -p "Fichier à extraire (vide pour revenir au menu) : " chemin
    [ -n "$chemin" ] || return 0
    hq_get "$arch" "$chemin"
}

while true; do
    echo "------------------------------------------"
    echo " $DISTRO_TITLE ($FORM_TITLE) - ENVIRONMENT MANAGER"
    echo "------------------------------------------"
    echo "1 > Déployer avec sauvegarde automatique ($DISTRO)"
    echo "2 > Déployer sans sauvegarde (rapide / vivant déjà sauvegardé)"
    echo "3 > Pré-vol : Diff avant déploiement (Dépôt ➜ Vivant)"
    echo "4 > Sauvegarder l'environnement (Tarball + Snapshot fin)"
    echo "5 > Restaurer l'environnement complet (Archive HQ)"
    echo "6 > Snapshots fins : lister, inspecter ou restaurer un fichier"
    echo "7 > Inspecter une archive tarball (diff + extraire)"
    echo "8 > Vérifier / installer les dépendances ($DISTRO_TITLE - $FORM_TITLE)"
    echo "q > Quit"
    echo "------------------------------------------"
    read -p "Choice: " choice

    case $choice in
        1)
            if check_dependencies; then
                echo ""
                preflight_diff
                echo ""
                read -p "Confirmer le déploiement avec sauvegarde ? (o/n) [o] : " conf_dep
                case "${conf_dep:-o}" in
                    o|O|y|Y|"")
                        [ "${BACKUP_OK:-0}" = "1" ] || backup_env
                        deploy_new_env
                        exit 0
                        ;;
                    *) echo "⏭️ Déploiement annulé." ;;
                esac
            fi
            ;;
        2)
            if check_dependencies; then
                echo ""
                preflight_diff
                echo ""
                read -p "Confirmer le déploiement direct SANS sauvegarde ? (o/n) [o] : " conf_dep
                case "${conf_dep:-o}" in
                    o|O|y|Y|"")
                        deploy_only
                        exit 0
                        ;;
                    *) echo "⏭️ Déploiement annulé." ;;
                esac
            fi
            ;;
        3)
            preflight_diff
            read -p "Appuyer sur Entrée pour revenir au menu..." _
            ;;
        4) backup_env ;;
        5) restore_hq && exit 0 ;;
        6) gerer_snapshots_menu ;;
        7) inspecter_hq ;;
        8)
            INSTALL_DEPS_ONLY=1 check_dependencies || true
            read -p "Appuyer sur Entrée pour revenir au menu..." _
            ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
done
