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
  generate.py    # style_vars.json + `awww query` → out/Themes/portable.conf + out/Backgrounds/portable.png
  install.sh     # génère puis installe (une invite polkit) ; --colors-only pour la palette seule
  out/           # sorties générées, hors dépôt (.gitignore)
```

- `generate.py` prend la palette de `active_theme` (ici `dynamic`) et le wallpaper
  réellement affiché (`awww query`) — jamais une valeur recopiée à la main.
- Fond : recadré 1920×1080 puis `-modulate 55` → luminance moyenne **44,0** contre
  **79,2** à la source, mesurée sur le fichier installé.
- `install.sh` copie `Themes/portable.conf` et `Backgrounds/portable.png` dans le
  thème, patche `metadata.desktop` (`ConfigFile=Themes/portable.conf`), neutralise les
  `Current=` concurrents (sauvegardés dans `~/.config/backups_env/sddm_*`) et écrit
  `/etc/sddm.conf.d/10-portable.conf` (`Current=sddm-astronaut-theme`). Vérifié :
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
