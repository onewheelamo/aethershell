# Point 15 — Écran de connexion : sddm-astronaut re-coloré (livré)

## Décision

Pas de thème maison : `sddm-astronaut-theme` (AUR), re-coloré depuis
`style_vars.json` et posé par `dev/sddm/install.sh`. La maquette maison
(`dev/mockups/greeter_mock.html` et ses rendus) reste dans le dépôt comme
référence de la direction visuelle, mais la mise en page livrée est celle
d'astronaut : horloge géante, formulaire centré sur une colonne floutée, libellés
français, bouton accent.

## État mesuré le 03/11/2026

- `sddm 0.21.0-7`, service actif et `enabled`, greeter en **X11**
  (`sddm-greeter-qt6 --theme …`, journal du 02/11 22:12).
- Deux fichiers locaux se contredisaient dans `/etc/sddm.conf.d/`
  (`99-force-kde-login.conf` → `breeze`, `kde_settings.conf` → `Muse`), aucun des
  deux n'appartenant à un paquet : le second l'emportait dans l'ordre lexical, donc
  le thème effectif était **Muse**, pas breeze.
- Qt 6.12 ; `SddmComponents 2.0` et `Qt5Compat.GraphicalEffects` présents ;
  `qt6-svg`, `qt6-virtualkeyboard`, `qt6-multimedia-ffmpeg`, `qt6-5compat` déjà
  installés → **sddm-astronaut n'ajoute aucune dépendance**.
- Clavier déjà `fr`/`azerty` pour Xorg (`/etc/X11/xorg.conf.d/00-keyboard.conf`),
  `Numlock=on` dans `/etc/sddm.conf`.
- **`/home/utilisateur` est en `710`** : le greeter (uid `sddm`) ne peut lire ni
  `style_vars.json` ni le wallpaper → palette et fond sont générés **dans** le
  thème, pas lus à chaud.

## Installation du thème

```bash
git clone https://aur.archlinux.org/sddm-astronaut-theme.git
cd sddm-astronaut-theme && makepkg -f --noconfirm
pkexec pacman -U "$PWD"/sddm-astronaut-theme-*.pkg.tar.zst
```

Installé en `92.abb3163-1`, dans `/usr/share/sddm/themes/sddm-astronaut-theme`
(19 Mo, fonds vidéo inclus).

## Re-coloration (le dépôt)

```
dev/sddm/
  generate.py    # style_vars.json + `awww query` → out/Themes/palette.conf + out/Backgrounds/wallpaper.png
  install.sh     # génère puis installe (une invite polkit) ; --colors-only pour la palette seule
  out/           # sorties générées, hors dépôt (.gitignore)
```

- `generate.py` prend la palette de `active_theme` (ici `dynamic`) et le wallpaper
  réellement affiché (`awww query`) — jamais une valeur recopiée à la main.
- Fond : recadré 1920×1080 puis `-modulate 55` → luminance moyenne **44,0** contre
  **79,2** à la source, mesurée sur le fichier installé.
- `install.sh` copie `Themes/palette.conf` et `Backgrounds/wallpaper.png` dans le
  thème, patche `metadata.desktop` (`ConfigFile=Themes/palette.conf`), neutralise les
  `Current=` concurrents (sauvegardés dans `~/.config/backups_env/sddm_*`) et écrit
  `/etc/sddm.conf.d/10-sddm-theme.conf` (`Current=sddm-astronaut-theme`). Vérifié :
  **un seul** `Current=` actif dans `/etc/sddm.conf.d/`.

### Correspondance des couleurs

Le thème peint la plupart de ses surfaces à **20 % d'opacité**, et c'est ce qui
décide du choix : une teinte sombre y disparaît. D'où `accent_muted` pour les
champs plutôt que `surface_variant`, qui donnait des champs invisibles sur un
wallpaper de nuit (premier essai, corrigé).

| Clé du thème | Source | Rôle |
|---|---|---|
| `TimeTextColor` / `DateTextColor` | `fg` / `fg` à 70 % | horloge et date |
| `FormBackgroundColor` | `surface` | colonne du formulaire (30 %) |
| `DimBackgroundColor` + `DimBackground=0.20` | `bg` | voile sur le wallpaper |
| `Login/PasswordFieldBackgroundColor` | `accent_muted` | champs (20 %) |
| `PlaceholderTextColor` | `fg` à 55 % | invites |
| `LoginButtonBackgroundColor` / `…TextColor` | `accent` / `bg` | bouton : pâle au repos, accent plein dès qu'un mot de passe est saisi |
| `WarningColor` | `error` | échec de connexion |
| `System/Session/VirtualKeyboard…` | `fg` à 60–70 % | boutons secondaires |
| `Hover*` | `accent` | survols |
| `Dropdown*` / `Highlight*` | `bg` / `accent` | listes utilisateurs et sessions |

Autres réglages : `Font=Inter`, `FontSize=13`, `RoundCorners=24`,
`Locale=fr_FR.UTF-8` (`DateFormat="dddd d"` → « mardi 3 »), `HourFormat=HH:mm`,
`PartialBlur=true`, `BlurMax=32`, `Blur=1.6`, `FormPosition=center`,
`HideSystemButtons=false`, `UseRealName=false`, et libellés français dans les
`Translate*` (`Se connecter`, `Mot de passe`, `Verr. Maj activée`, `Éteindre`…).

## Vérification

```bash
QT_QPA_PLATFORM=wayland sddm-greeter-qt6 --test-mode \
  --theme /usr/share/sddm/themes/sddm-astronaut-theme
grim /tmp/greeter.png
```

Le mode test ouvre une fenêtre Wayland 1920×1080 (`class: sddm-greeter-qt6`) sans
toucher au service. Trois passes : thème d'origine, thème re-coloré au repos, puis
mot de passe saisi au clavier virtuel (`/dev/uinput`) — le bouton passe bien en
accent plein et devient lisible. **Ne jamais** lancer `systemctl restart sddm` :
cela tue la session en cours.

## Points connus

- L'étiquette de session affiche « Session (Hyprland (uwsm-managed)) » : les
  parenthèses viennent du nom de session renvoyé par SDDM, pas du thème.
  Corrigeable en patchant `Components/SessionButton.qml` si le rendu gêne.
- Une mise à jour du paquet AUR réécrit `metadata.desktop` (donc `ConfigFile`) :
  relancer `bash dev/sddm/install.sh` après chaque `yay -Syu`.
- Après un changement de palette ou de wallpaper :
  `bash dev/sddm/install.sh --colors-only` (une invite polkit). `deploy.sh` ne peut
  pas le faire — il n'a aucun moyen de s'authentifier.
- `magick` affiche un `ParseError missing >` en lisant le JPEG source : sans effet,
  le PNG généré est valide (dimensions et luminance contrôlées).

## Thèmes complets qylock (SDDM seulement)

Amont : https://github.com/Darkkal44/qylock (GPL-3.0) — 39 thèmes sous `themes/`,
~595 Mo, essentiellement des fonds vidéo. **Seul `themes/` est utilisé** : la
version écran de veille du dépôt (`quickshell-lockscreen/`, `lock.sh` + QML
hyprlock) n'est pas reprise, la session a déjà son verrou.

Chaque thème est autonome (`Main.qml`, `theme.conf`, `bg.png`, `font/`) et ne
demande que des modules déjà présents : `SddmComponents 2.0`,
`Qt5Compat.GraphicalEffects` (`qt6-5compat`), `Qt.labs.folderlistmodel`.

```
dev/sddm/
  qylock.py       # catalogue + récupération à la demande (jamais versionnée)
  install.sh --qylock <nom…>   # pose dans /usr/share + helper polkit
  thumbnails.sh   # miniatures des deux familles (astronaut et qylock)
```

- `qylock.py list` / `fetch <nom…>` / `fetch --static` (refuse un fond vidéo) /
  `fetch --all`. Cache : `~/.local/share/qylock-themes/<nom>/`, arbre GitHub
  dans `~/.cache/quickshell/qylock-tree.json` (`QYLOCK_REFRESH=1` pour rafraîchir).
- `clockwork` contient trois thèmes (orbital, neo-orbital, tape) : SDDM ne sait
  nommer qu'un dossier de premier niveau dans `Current=`, ils sont donc installés
  aplatis en `clockwork-<variante>`.
- `install.sh --qylock` réinstalle aussi `greeter-palette` et sa règle polkit :
  l'ancienne version du helper ne connaissait que les confs astronaut et
  refusait un thème complet.
- Miniatures : `greeter_manager.py sources` donne la liste `id → dossier`, que
  `thumbnails.sh` capture une par une en mode test. Un thème seulement récupéré
  (pas encore installé) est listé avec le suffixe « (à installer) ».
- **Le panneau ne lit pas le dépôt.** `dev/core/greeter_manager.py` doit être
  recopié dans `~/.config/quickshell/core/` (ce que fait `deploy.sh`) : sans ça
  le panneau continue d'afficher l'ancienne liste, sans les thèmes qylock, même
  quand `python3 dev/core/… list` les voit. Vérification rapide :
  `diff -q dev/core/greeter_manager.py ~/.config/quickshell/core/greeter_manager.py`.
  L'onglet « Connexion » étant chargé à la demande (`Loader { active: visible }`),
  rouvrir le panneau suffit ensuite — pas besoin de relancer Quickshell.

### État mesuré le 04/11/2026

Installés : `clockwork-orbital`, `clockwork-neo-orbital`, `clockwork-tape`,
`field`, `material-you`, `material-you-dark`, `nothing` — plus `ryoku`, déjà
présent dans `/usr/share/sddm/themes` et reconnu comme qylock via
`Author=Darkkal44` dans sa metadata. Les sept variantes ont été rendues en mode
test (Qt 6.12) avant installation, puis une capture depuis
`/usr/share/sddm/themes/nothing` a confirmé que la copie root:root se rend.

Sélection vérifiée de bout en bout : `greeter_manager.py apply nothing` →
`Current=nothing`, `list` renvoie `active=nothing` ; retour à `pixel_sakura`
(astronaut) ensuite, donc le drop-in `/etc/sddm.conf.d/10-sddm-theme.conf`
alterne bien entre les deux familles.

## Autre machine que le desktop (Fedora)

Rien de ce pipeline n'est joué par `deploy.sh` : il vit dans `dev/sddm/` et
s'installe à la main, une fois par machine, avec `install.sh` (une invite
polkit).

- **Taille d'écran.** `generate.py` lit `hyprctl monitors -j` (moniteur focalisé)
  et repasse en pixels physiques (`width × scale`) : le greeter s'affiche hors
  compositeur, donc aucune échelle ne lui est appliquée. Repli 1920×1080 quand
  il n'y a pas de session (ssh, tty) ; `GREETER_SCREEN=WxH` force la valeur.
  `greeter-palette set-palette` vérifie ensuite le PNG contre `ScreenWidth` /
  `ScreenHeight` de la conf, et non plus contre une taille codée en dur.
- **Fedora.** Pas d'AUR : cloner `https://github.com/Keyitdev/sddm-astronaut-theme`
  dans `/usr/share/sddm/themes/sddm-astronaut-theme`. Police Inter :
  `rsms-inter-fonts` (`inter-font` sur Arch), `install.sh` prévient si elle
  manque. Le `Current=` de base y vit dans `/etc/sddm.conf` et non dans
  `conf.d/` : `install.sh` le neutralise aussi, sinon deux `Current=`
  cohabitent.
- **Prérequis** : `~/.config/quickshell/core/style_vars.json` doit exister sur la
  machine (premier déploiement fait), sinon `generate.py` s'arrête.
