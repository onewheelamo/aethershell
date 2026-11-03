# Proposition de nettoyage des répertoires cibles — rice Quickshell/Hyprland

Date : 2026-11-03 14:54 CET
Auteur de la proposition : Hermes (à soumettre à relecture externe)
Périmètre analysé : `~/.config/quickshell`, `~/.config/hypr`, `~/.config/rofi`,
`~/.config/fuzzel`, `~/.config/backups_env`, et leur source `/home/utilisateur/dev/quickshell_todo/dev`.

Statut : **proposition, rien n'a été appliqué.** Toutes les suppressions décrites
ci-dessous sont soit en dry-run, soit conditionnées à une validation.

---

## 0. Contexte et méthode

Le rice déployé est une copie de `dev/` via `deploy_station.sh` (Arch) et
`deploy_portable.sh` (Fedora). Un déploiement a été exécuté à 14:54, donc les
cibles sont à jour côté code : le problème analysé n'est pas un retard de
synchronisation, mais **l'accumulation de fichiers qui ne sont jamais supprimés**
et **la confusion entre code, état utilisateur et fichiers générés**.

Méthode : inventaire par `find`/`ls`, comparaison `diff -rq` dev ↔ cible,
recherche de références (`grep -rn`) pour chaque candidat à la suppression,
lecture des scripts de déploiement et de `core/generate_rofi_theme.sh`.
Les commandes de preuve sont en annexe A.

Environnement : Hyprland 0.57.0 (config Lua), Quickshell 0.3.2, Arch,
un moniteur HDMI-A-1 1920x1080@60.

---

## 1. Inventaire des fichiers en trop (état constaté)

### 1.1 `~/.config/quickshell`

| Fichier | Taille | Constat |
|---|---|---|
| `ThemeColors.qml` | 290 o | **Aucune référence** (grep sur *.qml/*.py/*.json), absent de `dev/` et absent de `qmldir` → mort |
| `core/app_vars.json.new` | 157 o | Diff vide avec `app_vars.json` → bruit pur |
| `core/secrets.json.new` | 167 o | **Copie d'un secret** produite par la logique de préservation |
| `core/style_vars.json.new` | 1617 o | Version amont non appliquée (rounding 2 / opacity 0.85 vs live 18 / 0.7) |
| `hyprquickpaper/config.json.new` | 190 o | Version amont sans `x_factor` ni `keep_open` |
| `core/fuzzel.ini` | 476 o | Artefact de build : généré dans `$SCRIPT_DIR` puis copié vers `~/.config/fuzzel/` |
| `core/rofi_config.rasi` | 2762 o | Idem, doublon de `~/.config/rofi/config.rasi` |
| `core/__pycache__/` | 20 K | Cache Python, recréé à l'exécution |
| `.git/` | 84 K | Dépôt **vide** : 0 commit, aucun remote |

### 1.2 `~/.config/hypr` (≈112 K de candidats)

| Fichier | Constat |
|---|---|
| `binds.lua.new`, `colors.lua.new`, `general.lua.new` | Diffs amont réels (fichiers préservés) |
| `hardware-portable.lua.new`, `hardware-station.lua.new`, `input.lua.new`, `programs.lua.new` | **Identiques au live** (`cmp -s`) → bruit |
| `hyprland.conf.old`, `hyprland.lua.old`, `hyprland.lua.mod-backup-20261021_190255`, `hyprland.lua.quickshell-backup-6dea48d5…` | Sauvegardes manuelles/anciennes migrations |
| `.hyprland.conf.kate-swp` | Fichier d'échange éditeur |
| `portable.lua`, `station.lua` | Ancienne config par hôte, remplacée par `hardware-*.lua` ; **non require** par `hyprland.lua` |
| `hardwareconfig.lua` | 0 octet, non require |
| `keybindings.lua` + `keybindings.lua.bak` | **Non require** (seul `binds` l'est) ; pointe vers `noctalia msg`, environnement abandonné |
| `scripts/wallpaper_switcher.sh` | Référencé **uniquement** par `hyprland.conf.old` et `hyprland.lua.old` ; remplacé par `hyprquickpaper` |
| `shaders/` | Dossier vide |
| `rotate.sh` | Aucune référence ; la rotation passe désormais par `config_manager.py` (action `rotate`) |
| `sync_to_portable.sh`, `sync_to_station.sh` | Legacy Hyprland+Noctalia (rsync vers `~/.config/noctalia`, qui existe encore) — **pas morts, mais hors périmètre du rice actuel** |

À conserver explicitement : `hyprlock.conf`, `hypridle.conf` (lus par les binaires
au chemin par défaut), `autostart_cmds.txt` (généré, lu par `exec.lua`),
`.quickshell_managed` (marqueur de déploiement).

### 1.3 Ailleurs

- `~/.config/rofi/config.rasi.old` (oct. 2025)
- `~/.config/backups_env/backup_station_hn.tar.gz` : 7,4 M, aucune rotation

---

## 2. Causes racines (au-delà des fichiers)

1. **Copie sans élagage.** `copy_dir_files()` itère sur les fichiers de `dev/`
   et copie ; aucun mécanisme ne supprime dans la cible ce qui a disparu ou été
   renommé en amont. Tout fichier retiré du dev reste à vie.

2. **`.new` systématique.** Pour chaque fichier préservé, le script fait
   `cp "$f" "$dst/$name.new"` **même quand le contenu est identique**, et
   **même pour `secrets.json`**. Résultat : 11 `.new` dont 5 sans information.

3. **Rustines sur fichiers préservés.** `deploy_station.sh` :
   - l.172-176 : ajoute le bind screenshot par `grep`/`echo` s'il est absent.
     `dev/binds.lua` le contient déjà → dans la cible il est **ajouté en fin de
     fichier** alors qu'il est ligne 24 côté dev (ordre différent, drift).
   - l.178-181 : `sed 's/dampening =/damping =/'` sur `general.lua`.
     `dev/general.lua` est déjà corrigé → la rustine ne fait plus que masquer
     la différence entre source et déployé.
   `deploy_portable.sh` ne contient aucune de ces deux rustines : les deux scripts
   divergent déjà.

4. **Pas de classification code / état / généré.** Le déploiement traite de la
   même façon du code QML (à écraser), de l'état édité par le panneau (à
   préserver) et des fichiers régénérés à l'exécution (à ne pas copier).
   C'est cette confusion qui produit à la fois les `.new` inutiles et les
   artefacts de build dans `core/`.

### Preuve du point 4 : `colors.lua` est généré, pas édité

`core/generate_rofi_theme.sh` (l.254-277) écrit `~/.config/hypr/colors.lua`
depuis `style_vars.json` (`ACCENT`, `SURFACE_VAR`, `RADIUS`, `OPACITY`).
`colors.lua` figure pourtant dans `PRESERVE_HYPR`. De même :
`programs.lua` ↔ `app_vars.json` (en-tête Section 7 de `config_manager.py`),
`autostart_cmds.txt` ↔ `autostart.json` (Section 8),
`rofi/config.rasi` + `fuzzel/fuzzel.ini` + `hyprquickpaper/colors.json`
(générateur). **`style_vars.json` est la source de vérité** de la palette,
des arrondis et de l'opacité ; `colors.lua` n'en est que la projection.

Conséquence : le live (rounding 18, opacity 0.7, palette `d8c3ab`) n'est pas
une « édition manuelle à préserver » mais l'état courant de `style_vars.json`,
alors que `dev/style_vars.json` est resté aux valeurs par défaut (2 / 0.85 /
`80d5d4`).

---

## 3. Patch proposé

Trois volets indépendants, applicables séparément.

### Volet A — nettoyage one-shot (`dev/clean_targets.sh`)

Dry-run par défaut, archive avant suppression, trois niveaux de risque.

```bash
#!/usr/bin/env bash
set -euo pipefail
DRY=1; [ "${1:-}" = "--apply" ] && DRY=0
STAMP=$(date +%Y%m%d_%H%M%S)
ARC="$HOME/.config/backups_env/clean_$STAMP"
QS="$HOME/.config/quickshell"; HY="$HOME/.config/hypr"

SAFE=(
  "$QS/ThemeColors.qml"
  "$HY/portable.lua" "$HY/station.lua" "$HY/hardwareconfig.lua"
  "$HY/keybindings.lua" "$HY/keybindings.lua.bak"
  "$HY/hyprland.conf.old" "$HY/hyprland.lua.old"
  "$HY"/hyprland.lua.mod-backup-* "$HY"/hyprland.lua.quickshell-backup-*
  "$HY/.hyprland.conf.kate-swp"
  "$HY/scripts" "$HY/shaders"
  "$HOME/.config/rofi/config.rasi.old"
)
BUILD=(
  "$QS/core/fuzzel.ini" "$QS/core/rofi_config.rasi" "$QS/core/__pycache__"
)
MAYBE=(
  "$HY/rotate.sh" "$HY/sync_to_portable.sh" "$HY/sync_to_station.sh"
)

do_rm() {
  for p in "$@"; do
    [ -e "$p" ] || continue
    echo "  rm $p"
    if [ "$DRY" = 0 ]; then
      mkdir -p "$ARC"; cp -a "$p" "$ARC"/ 2>/dev/null || true
      rm -rf "$p"
    fi
  done
}

echo "== niveau 1 (sûr)";       do_rm "${SAFE[@]}"
echo "== niveau 3 (artefacts)"; do_rm "${BUILD[@]}"
[ "${2:-}" = "--maybe" ] && { echo "== niveau 2"; do_rm "${MAYBE[@]}"; }

if [ "$DRY" = 0 ]; then
  mkdir -p "$ARC/new_files"
  mv "$HY"/*.new "$QS"/core/*.new "$QS"/hyprquickpaper/*.new "$ARC/new_files"/ 2>/dev/null || true
  rm -rf "$QS/.git"
fi

echo "dry-run : relancer avec --apply [--maybe]"
```

Choix : les `.new` sont **archivés, pas supprimés** (ils portent le diff amont).
`sync_to_*` et `rotate.sh` sont en niveau 2 car ce sont des outils manuels
potentiellement encore utilisés.

### Volet B — refonte du déploiement

#### B1. Manifeste de politique (nouveau `dev/deploy_manifest.tsv`)

```tsv
# chemin relatif        politique   destination
island_left.qml         code        qs
island_center.qml       code        qs
island_right.qml        code        qs
main.qml                code        qs
shell.qml               code        qs
Theme.qml               code        qs
config_panel.qml        code        qs
CollapsibleSection.qml  code        qs
Stepper.qml             code        qs
qmldir                  code        qs
core/*.py               code        qs/core
core/*.sh               code        qs/core
hypr_modular/*.lua      code        hypr
style_vars.json         state       qs/core
app_vars.json           state       qs/core
secrets.json            state       qs/core   (jamais copié, jamais .new)
autostart.json          state       qs/core
general.lua             state       hypr
binds.lua               state       hypr
input.lua               state       hypr
colors.lua              generated   hypr
programs.lua            generated   hypr
autostart_cmds.txt      generated   hypr
rofi_config.rasi        generated   rofi
fuzzel.ini              generated   fuzzel
colors.json             generated   qs/hyprquickpaper
```

`generated` = jamais copié ni préservé : régénéré par le panneau ou le script
de thème. `state` = préservé, avec migration de schéma si le dev ajoute une clé.

#### B2. Remplacement de `copy_dir_files` (les deux scripts)

```bash
sync_file() {                      # code/state, sans .new inutile
  local src="$1" dst="$2" name; name="$(basename "$dst")"
  [ -e "$dst" ] || { cp "$src" "$dst"; return; }
  cmp -s "$src" "$dst" && { rm -f "$dst.upstream"; return; }
  cp "$src" "$dst.upstream"        # un seul diff amont, écrasé au passage suivant
}

prune_target() {                   # supprime ce qui n'est plus dans le manifeste
  local dst="$1" manifest="$2" f name
  for f in "$dst"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    grep -qE "^$name[[:space:]]" "$manifest" && continue
    case "$name" in *.upstream|hyprlock.conf|hypridle.conf) continue ;; esac
    echo "  prune $dst/$name"; rm -f "$f"
  done
}
```

Appel type :

```bash
while read -r rel policy dest; do
  case "$policy" in
    code)      sync_file "$DEV_DIR/$rel" "$(target_for "$dest")/$rel" ;;
    state)     is_preserved ... && sync_file ... ;;
    generated) : ;;   # laissé au générateur
  esac
done < "$DEV_DIR/deploy_manifest.tsv"
prune_target "$CURRENT_HYPR" "$MANIFEST_HYPR"
```

#### B3. Suppressions dans les scripts (diff proposé)

```diff
--- a/dev/deploy_station.sh
+++ b/dev/deploy_station.sh
@@
-    # Add SUPER + SHIFT + S screenshot binding if missing from preserved binds.lua
-    if [ -f "$CURRENT_HYPR/binds.lua" ] && ! grep -q "screenshot.sh" "$CURRENT_HYPR/binds.lua"; then
-        echo "  ↪ adding screenshot shortcut (SUPER + SHIFT + S) to $CURRENT_HYPR/binds.lua"
-        echo -e '\n-- Capture d’écran interactive (SUPER + SHIFT + S) : zone/fenêtre, presse-papier & fichier\nhl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("$HOME/.config/quickshell/core/screenshot.sh"))' >> "$CURRENT_HYPR/binds.lua"
-    fi
-
-    # Fix damping keyword in general.lua if present in preserved config
-    if [ -f "$CURRENT_HYPR/general.lua" ]; then
-        sed -i 's/dampening =/damping =/g' "$CURRENT_HYPR/general.lua"
-    fi
-
     touch "$MARKER"
```

`dev/binds.lua` contient déjà le bind (l.24) et `dev/general.lua` utilise déjà
`damping` (l.50) : ces rustines ne produisent plus que du drift et un ordre
de bind différent entre source et cible.

#### B4. Générateur de thème

`core/generate_rofi_theme.sh` écrit `rofi_config.rasi` et `fuzzel.ini` dans
`$SCRIPT_DIR` avant de les copier vers XDG. Proposition : écrire directement
dans `$XDG_CONFIG_HOME/{rofi,fuzzel}`, ou dans `dev/.build/` ignoré par git,
et retirer toute copie de ces deux fichiers dans `core/` de la cible.

### Volet C — hygiène

1. **Git au bon endroit** : `git init` dans `dev/quickshell_todo`, premier
   commit de l'état courant, suppression de `~/.config/quickshell/.git`
   (dépôt vide, 84 K). `.gitignore` : `*.new`, `*.upstream`, `__pycache__/`,
   `*.log`, `dev/core/secrets.json`, `.build/`.
2. **Rétention backups** : `ls -1t ~/.config/backups_env/*.tar.gz | tail -n +4 | xargs -r rm -f`
   (garder 3).
3. **Vérification post-application** :
   - `diff -rq dev ~/.config/quickshell --exclude=core --exclude=.git`
     ne doit plus montrer que les `state` et `generated` ;
   - `hyprctl reload && hyprctl configerrors` → vide ;
   - `quickshell log` (ou journal) sans erreur QML, capture d'écran de la barre ;
   - `qs ipc call portable toggleConfig` fonctionne toujours.

---

## 4. Ordre d'application et rollback

1. Volet C.1 (git dans dev) → filet de sécurité avant tout.
2. Volet A en dry-run, relecture de la liste, puis `--apply` (sans `--maybe`).
3. Volet B1+B2 sur une copie de `deploy_station.sh`, test à blanc, puis
   remplacement ; idem `deploy_portable.sh`.
4. Volet B3, B4, puis redéploiement complet et vérifications C.3.

Rollback : `backups_env/clean_<date>/` contient tous les fichiers retirés ;
les tarballs HN/HQ existants couvrent le reste. Aucune suppression n'est faite
hors archive.

---

## 5. Points à faire critiquer (hypothèses assumées)

1. **Source de vérité.** Je pars du principe que le live est l'état voulu
   (rounding 18, opacity 0.7, palette `d8c3ab`) et que `dev/style_vars.json`
   doit être réaligné dessus. L'inverse (le dev est la référence, le live a
   dérivé) changerait le patch : il faudrait alors écraser le live.
2. **`colors.lua` en `generated`.** Conséquence de la lecture de
   `generate_rofi_theme.sh` ; à confirmer en vérifiant qu'aucune édition
   manuelle de `colors.lua` n'est attendue.
3. **Niveau 2.** `rotate.sh` et `sync_to_*` sont peut-être encore utilisés à la
   main ; je ne les supprime pas par défaut.
4. **`.new` → `.upstream`.** Le renommage casse les habitudes, mais rend
   explicite « ceci est la version amont, non appliquée » et évite la
   prolifération (un seul fichier par cible, écrasé).
5. **Non couvert volontairement** : la refonte UI du panneau
   (`TODO_panel_sections.md`), les bugs blur/OSD signalés comme bloquants, et
   le contenu de `dev/` lui-même (logs `tablet_events.log`, `capture_events.sh`,
   `mockup_portable.svg`, `PROJECT_TODO.md`, `__pycache__`) qui relève de
   l'hygiène du dépôt source, pas des cibles.

---

## Annexe A — commandes de preuve

```bash
hyprctl version; quickshell --version
diff -rq /home/utilisateur/dev/quickshell_todo/dev /home/utilisateur/.config/quickshell \
     --exclude=.git --exclude=__pycache__ --exclude='*.log' --exclude='*.svg'
diff -rq /home/utilisateur/dev/quickshell_todo/dev/hypr_modular /home/utilisateur/.config/hypr
grep -rn "ThemeColors" --include=*.qml --include=*.py /home/utilisateur/.config/quickshell
grep -rn 'require\|dofile' /home/utilisateur/.config/hypr/hyprland.lua
cd /home/utilisateur/.config/hypr && for f in *.new; do cmp -s "$f" "${f%.new}" && echo "identique $f"; done
cd /home/utilisateur/.config/quickshell && git status --short; git log --oneline
grep -n 'colors.lua\|GENERATED_ROFI\|GENERATED_FUZZEL' dev/core/generate_rofi_theme.sh
```

## Annexe B — fichiers vérifiés comme utilisés (ne pas supprimer)

`core/osd.sh` (appelé par `binds.lua` l.69 et `hardware-portable.lua` l.8),
`core/monitor_utils.py` (`import` dans `config_manager.py` l.29 et
`tablet_mode_daemon.py`), `core/runtime_paths.py` (`from runtime_paths import`
dans `nextcloud_service.py` et `system_service.py`), `core/tablet_mode_daemon.py`,
`core/workspace_service.py`, `core/system_service.py`, `core/theme_manager.py`,
`core/generate_colors.sh`, `core/generate_rofi_theme.sh`,
`core/secrets.example.json` (modèle), `hyprland.lua`, `exec.lua`, `windows.lua`.
