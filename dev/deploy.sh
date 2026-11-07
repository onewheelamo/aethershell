#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# Unified Quickshell & Hyprland Environment Manager & Deployer
# Deux familles de distribution : Arch Linux et Fedora. La cible se déduit de
# /etc/os-release, jamais du nom de la machine — un dépôt partagé ne doit rien
# dire du parc de son auteur.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_HYPR="$HOME/.config/hypr"
BACKUP_DIR="$HOME/.config/backups_env"
DEV_DIR="$SCRIPT_DIR"
QS_DIR="$HOME/.config/quickshell"
CORE_DIR="$QS_DIR/core"
DEPS_FILE="$DEV_DIR/dependencies.txt"

mkdir -p "$BACKUP_DIR"

# Dépendances applicables à une cible, d'après les portées du fichier :
#   #: commun          → les deux familles
#   #: arch|fedora     → une seule
# Un binaire par ligne ; le reste est commentaire. Sert au contrôle avant
# déploiement et à `--deps`, qui affiche la liste résolue sans rien installer.
deps_pour_cible() {
    local cible="$1" portee="commun" ligne dep
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
        if [ "$portee" = "commun" ] || [ "$portee" = "$cible" ]; then
            printf '%s\n' "$dep"
        fi
    done < "$DEPS_FILE"
}

# 1. Détection de la distribution (argument > /etc/os-release)
#    `arch` couvre Arch et ses dérivés, `fedora` Fedora et ses rebuilds.
DISTRO=""
IDENT=""
if [ -f /etc/os-release ]; then
    IDENT="$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')"
fi
case "$IDENT" in
    arch|archarm|endeavouros|manjaro|garuda|cachyos) DISTRO="arch" ;;
    fedora|nobara|bazzite) DISTRO="fedora" ;;
esac

for arg in "$@"; do
    case "$arg" in
        --arch|arch) DISTRO="arch" ;;
        --fedora|fedora) DISTRO="fedora" ;;
        --target=*)
            case "${arg#*=}" in
                arch|fedora) DISTRO="${arg#*=}" ;;
                *) echo "❌ Cible inconnue : ${arg#*=} (attendu : arch | fedora)" >&2; exit 2 ;;
            esac
            ;;
        --target)
            shift
            case "${1:-}" in
                arch|fedora) DISTRO="${1:-}" ;;
                *) echo "❌ Cible inconnue : ${1:-} (attendu : arch | fedora)" >&2; exit 2 ;;
            esac
            ;;
        --deps) PRINT_DEPS=1 ;;
        --hq-list) HQ_ACTION="list"; shift || true; HQ_ARG1="${1:-}" ;;
        --hq-diff) HQ_ACTION="diff"; shift || true; HQ_ARG1="${1:-}" ;;
        --hq-get)  HQ_ACTION="get";  shift || true; HQ_ARG1="${1:-}"; HQ_ARG2="${2:-}" ;;
    esac
done

if [ -z "$DISTRO" ]; then
    echo "❌ Distribution non reconnue (ID='${IDENT:-absent}')." >&2
    echo "   Forcer la cible : $0 --arch   ou   $0 --fedora" >&2
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
esac
# Sauvegardes : un nom par famille de distribution, sans rien qui nomme la machine.
# HQ seulement : l'environnement Noctalia n'est plus utilise, et une sauvegarde qui
# ne sert jamais ne fait que brouiller le choix au moment de restaurer.
HQ_ALIAS="$BACKUP_DIR/backup_${DISTRO}_hq.tar.gz"
HQ_RETENTION=5

# `--deps` : la liste que ce fichier donne pour la cible, sans rien toucher.
if [ "${PRINT_DEPS:-0}" = "1" ]; then
    deps_pour_cible "$DISTRO" || { echo "❌ $DEPS_FILE introuvable." >&2; exit 1; }
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

PRESERVE_CORE="style_vars.json app_vars.json secrets.json autostart.json widgets.json notif_targets.json llm_providers.json bar_applets.json homelab.json launch_history.json"
# colors.lua est *généré* par generate_rofi_theme.sh depuis style_vars.json :
# il n'est ni préservé ni comparé (sinon .upstream à chaque changement de palette).
# programs.lua est *généré* depuis core/app_vars.json (sync_programs_lua) et
# autostart_cmds.txt depuis core/autostart.json : ils ne sont ni préservés ni
# comparés, et sont réécrits juste après la copie (aucun .upstream possible).
PRESERVE_HYPR="input.lua binds.lua general.lua"

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
        # core/ : un .json présent sur la cible n'est jamais remplacé, sauf s'il
        # fait partie des données livrées. Absent = on installe celui du dépôt.
        case "$dst" in
            */core)
                if [ -e "$dst/$name" ] && [[ "$name" == *.json ]] \
                   && [[ " $JSON_DEPLOYES " != *" $name "* ]]; then
                    continue
                fi
                ;;
        esac
        # Fichiers d'état hors core/ (le cas échéant) : même règle, par liste.
        if [ -e "$dst/$name" ] && [[ " ${NON_ECRASABLES:-} " == *" $name "* ]]; then
            continue
        fi
        if [ -e "$dst/$name" ] && is_preserved "$name" "$list"; then
            sync_file "$f" "$dst/$name"
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
        [ -n "$preserve_list" ] && is_preserved "$name" "$preserve_list" && continue
        case "$name" in
            *.upstream) continue ;;
            hypridle.conf|hyprlock.conf|hyprlock-colors.conf|autostart_cmds.txt|.quickshell_managed) continue ;;
            secrets.json) continue ;;
            # Outils manuels hors périmètre du déploiement : jamais élagués.
            rotate.sh|sync_to_*.sh|sync*.sh) continue ;;
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

pkg_for_bin() {
    local bin="$1"
    if [ "$PKG_MGR" = "dnf" ]; then
        case "$bin" in
            wpctl) echo "wireplumber" ;;
            nmcli) echo "NetworkManager" ;;
            powerprofilesctl) echo "power-profiles-daemon" ;;
            monitor-sensor) echo "iio-sensor-proxy" ;;
            magick) echo "ImageMagick" ;;
            *) echo "$bin" ;;
        esac
    else
        case "$bin" in
            wpctl) echo "wireplumber" ;;
            nmcli) echo "networkmanager" ;;
            magick) echo "imagemagick" ;;
            *) echo "$bin" ;;
        esac
    fi
}

check_dependencies() {
    echo "Checking dependencies for $DISTRO_TITLE..."
    if [ ! -f "$DEPS_FILE" ]; then
        echo "❌ Error: $DEPS_FILE not found."
        return 1
    fi

    local deps=()
    mapfile -t deps < <(deps_pour_cible "$DISTRO")
    local missing=()
    local missing_pkgs=()
    for dep in "${deps[@]}"; do
        if [ -z "$dep" ]; then continue; fi
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
            missing_pkgs+=("$(pkg_for_bin "$dep")")
        fi
    done

    # `grep -q` serait un faux négatif ici : sous `set -o pipefail`, grep sort au
    # premier match, fc-list prend SIGPIPE et le pipeline rend 141 → la police
    # paraît manquante à chaque déploiement et se réinstalle.
    if ! fc-list : family 2>/dev/null | grep -i "0xproto" >/dev/null; then
        echo "⚠️ Police d'icônes manquante : 0xProto Nerd Font"
        if [ -x "$DEV_DIR/core/install_fonts.sh" ]; then
            bash "$DEV_DIR/core/install_fonts.sh" || echo "⚠️ Échec de l'installation automatique de la police."
        fi
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        echo "✅ All dependencies installed."
        return 0
    else
        echo "⚠️ Missing binaries: ${missing[*]} ($PKG_MGR packages: ${missing_pkgs[*]})"
        read -p "Do you want to try installing them now with $PKG_MGR? (y/n): " choice
        if [ "$choice" == "y" ]; then
            if [ "$PKG_MGR" = "dnf" ]; then
                sudo dnf install -y "${missing_pkgs[@]}"
            else
                sudo pacman -S --needed "${missing_pkgs[@]}"
            fi
            return $?
        else
            read -p "Continue deployment anyway? (y/n): " cont
            [ "$cont" == "y" ] && return 0 || return 1
        fi
    fi
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
    grep -qE '^[[:space:]]*background-blur[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$cible" && return 0
    if grep -qE '^[[:space:]]*background-blur' "$cible"; then
        sed -i -E 's/^[[:space:]]*background-blur.*/background-blur = true/' "$cible"
        echo "  ↪ ghostty : background-blur remis à true"
    else
        cat >> "$cible" <<'EOF'

# Flou derrière la fenêtre : sans cette ligne Ghostty ne demande pas l'effet au
# compositeur (ext-background-effect-v1) et seule l'opacité s'applique.
background-blur = true
EOF
        echo "  ↪ ghostty : background-blur ajouté à user.conf"
    fi
}

deploy_new_env() {
    echo "🚀 Deploying $DISTRO_TITLE..."

    mkdir -p "$CURRENT_HYPR"
    if [ ! -f "$MARKER" ]; then
        if [ "$BACKUP_OK" = "1" ]; then
            echo "ℹ️ No Quickshell marker in $CURRENT_HYPR: existing files will be replaced (backup done)."
        else
            echo "ℹ️ No Quickshell marker in $CURRENT_HYPR: existing files will be replaced (no backup was created)."
        fi
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
    # Index des applications de la pilule spotlight : données de la machine,
    # pas du dépôt — régénérées à chaque déploiement (et à chaque ouverture).
    if [ -f "$CORE_DIR/app_index.py" ]; then
        python3 "$CORE_DIR/app_index.py" --quiet || true
    fi

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
    fi

    "$CORE_DIR/generate_rofi_theme.sh"

    deploy_ghostty_overrides

    # ── rechargement de la session, sans intervention ───────────────────────
    # Déployer sans relire la config laissait l'utilisateur devant un écran qui
    # affichait l'ancienne version jusqu'à sa prochaine déconnexion. On recharge
    # donc Hyprland puis quickshell ici. L'unité systemd est prioritaire ; le
    # lancement direct ne sert que si elle n'existe pas encore (première install).
    recharger_session() {
        local sig
        sig=$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1)
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
            if systemctl --user restart quickshell.service; then
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

    echo "✅ $DISTRO_TITLE deployment complete."

    # Installation neuve : dire où sont les raccourcis. La barre est lancée par
    # l'autostart de Hyprland, pas par ce script — on laisse donc passer quelques
    # secondes avant de notifier, sinon le message part avant que le serveur de
    # notifications n'existe et personne ne le voit. `systemd-run` porte le délai
    # même si le terminal est fermé entre-temps.
    if [ "$premiere_fois" = "1" ]; then
        echo "   SUPER + K   tous les raccourcis"
        echo "   SUPER + H   panneau de réglages"
        echo "   SUPER + S   captures d'écran et vidéos"
        echo "   SUPER + SHIFT + S   région copiée au presse-papiers"
        systemd-run --user --collect --quiet --on-active=8 --unit="qs-welcome-$$" \
            notify-send -a "Installation" \
                "AetherShell est prêt" \
                "SUPER + K : tous les raccourcis — SUPER + H : réglages — SUPER + SHIFT + S : captures d'écran" \
            >/dev/null 2>&1 || true
    fi
}

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
    echo " $DISTRO_TITLE - ENVIRONMENT MANAGER"
    echo "------------------------------------------"
    echo "1 > Deploy & Switch to Quickshell ($DISTRO)"
    echo "2 > Backup HQ (Hyprland + Quickshell)"
    echo "3 > Restore HQ from an older version"
    echo "4 > Inspecter une sauvegarde (diff + extraire un fichier)"
    echo "q > Quit"
    echo "------------------------------------------"
    read -p "Choice: " choice

    case $choice in
        1)
            if check_dependencies; then
                [ "${BACKUP_OK:-0}" = "1" ] || backup_env
                deploy_new_env
                exit 0
            fi
            ;;
        2) backup_env ;;
        3) restore_hq && exit 0 ;;
        4) inspecter_hq ;;
        q|Q) exit 0 ;;
        *) echo "Invalid choice." ;;
    esac
done
