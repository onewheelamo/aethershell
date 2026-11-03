# Point 15 — Écran de connexion (greeter) : maquette + architecture

## État mesuré le 03/11/2026

- `sddm 0.21.0-7`, service `sddm.service` actif et `enabled`.
- Le greeter tourne en **X11** : `sddm-greeter-qt6 --theme /usr/share/sddm/themes/Muse`
  (journal du 02/11 22:12).
- Deux fichiers se contredisent dans `/etc/sddm.conf.d/` :
  `99-force-kde-login.conf` (`Current=breeze`) et `kde_settings.conf`
  (`Current=Muse`). Le second l'emporte dans l'ordre lexical — le thème effectif
  est **Muse**, pas breeze comme l'annonçait la fiche du backlog.
- Qt 6.12 ; `SddmComponents 2.0` et `Qt5Compat.GraphicalEffects` sont présents
  (`/usr/lib/qt6/qml/`) ; `qt6-svg` et `qt6-virtualkeyboard` installés.
- Clavier déjà en `fr`/`azerty` pour Xorg (`/etc/X11/xorg.conf.d/00-keyboard.conf`),
  `Numlock=on` dans `/etc/sddm.conf`.
- **`/home/utilisateur` est en `710`** : le greeter s'exécute sous l'uid `sddm` (969) et ne
  peut lire ni `~/.config/quickshell/core/style_vars.json`, ni le wallpaper. Toute
  palette ou image doit donc être **cuite dans le thème** à l'installation.

## Maquette

`dev/mockups/greeter_mock.html` (source, trois états par `?s=idle|typing|error`)
et les rendus `greeter_idle.png`, `greeter_typing.png`, `greeter_error.png`,
`greeter_detail.png` (×2), au wallpaper et à la palette de la session.

| Élément | Valeur | Motif |
|---------|--------|-------|
| Carte | 364 px, rayon 26, padding 28 | gabarit de la pilule spotlight, pas celui du panneau |
| Fond carte | `surface` à 78 % + flou 26 | doit rester lisible sur un wallpaper clair |
| Bordure | accent à 18 % | rappel de la capsule de la barre |
| Avatar | 68 px, lettre accent sur accent 14 % | pas de photo : aucune dépendance à `user.avatar` |
| Champ | 46 px, rayon 23, loupe/cadenas 15 px | hauteur de la capsule |
| Bouton | 42 px, accent plein, texte `bg` | seule surface saturée : le point de mire |
| Horloge | 76 px poids 200, chiffres tabulaires | l'heure se lit de loin, le reste se lit de près |
| Pied de carte | filet 1 px + « Hyprland ⌄ » | la session reste atteignable sans encombrer |
| Coins | hôte en bas à gauche, veille/redémarrage/extinction en bas à droite | rien d'autre n'est cliquable |

États : au repos (invite + caret), frappe (points + caret), erreur (bordure et
message `error`, la carte grandit d'une ligne).

## Architecture proposée

Thème maison **« portable »**, Qt Quick pur — aucune dépendance Plasma/Kirigami,
aucun paquet AUR :

```
dev/sddm/
  generate.py            # style_vars.json → theme/palette.json + theme/background.png
  install.sh             # pkexec : copie le thème, écrit 10-portable.conf
  theme/
    Main.qml             # horloge, carte, coins
    metadata.desktop     # [SddmGreeterTheme] Type=sddm-theme, QtVersion=6, ConfigFile=theme.conf
    theme.conf
    palette.json         # généré (bg, fg, accent, surface, error)
    background.png       # généré : wallpaper assombri 40 %, 1920×1080
```

- **Palette** : `generate.py` lit `core/style_vars.json` (le même fichier que
  `config_manager.py` utilise pour les layer rules) et écrit `palette.json`. Comme
  `colors.lua`, c'est un fichier **généré**, jamais édité à la main.
- **Flou de la carte** : `ShaderEffectSource` sur `background.png` +
  `GaussianBlur` (`Qt5Compat.GraphicalEffects`) — le `backdrop-filter` de la
  maquette se traduit exactement comme ça, sans shader écrit à la main.
- **Installation séparée** : `dev/sddm/install.sh` (une invite polkit) copie vers
  `/usr/share/sddm/themes/portable/` et écrit
  `/etc/sddm.conf.d/10-portable.conf` (`Current=portable`), en supprimant le
  `Current=` contradictoire des deux fichiers existants. `deploy.sh` reste sans
  sudo : il n'a aucun moyen de demander un mot de passe, et un déploiement ne
  doit pas dépendre d'une authentification.
- **Après un changement de palette** : `dev/sddm/install.sh --colors-only`
  (une invite, deux fichiers réécrits). Le changement de wallpaper est rare, donc
  la contrainte est acceptable ; à défaut le greeter garde la palette précédente.

## API à utiliser (vérifiée présente, à confirmer au test-mode)

- `sddm.login(user, password, sessionIndex)`, signaux `loginFailed`,
  `loginSucceeded` ; `sddm.canSuspend/canReboot/canPowerOff` et
  `suspend()/reboot()/powerOff()`.
- `userModel` (`lastIndex`, `get(index).name/realName`) et `sessionModel`
  (`index`, `get(index).name`) pour le pied de carte.
- Verr. Maj : l'exposition de `keyboard.capsLock` varie selon les versions ; à
  vérifier d'abord avec un `console.log` en test-mode. Si absent, l'indicateur se
  déduit du `TextInput` (`inputMethodHints`) et reste optionnel.

## Vérification

0. **Mode test validé** (03/11) : `QT_QPA_PLATFORM=wayland sddm-greeter-qt6
   --test-mode --theme <dir>` ouvre une fenêtre Wayland 1920×1080
   (`class: sddm-greeter-qt6`), capturable au `grim` sans toucher au service. Le
   thème `ryoku` s'y est affiché avec le bon utilisateur (`amo`) et la session
   `hyprland (uwsm-managed)` — donc `userModel` et `sessionModel` renseignent
   correctement, et le libellé de session se déduira du nom renvoyé.
1. `sddm-greeter-qt6 --test-mode --theme dev/sddm/theme` puis `grim` — jamais
   `systemctl restart sddm` : cela tue la session en cours.
2. Comparer l'accent et le fond de la capture à `palette.dynamic`.
3. Après installation : `grep Current /etc/sddm.conf.d/10-portable.conf`,
   `ls /usr/share/sddm/themes/portable`, et un seul `Current=` dans
   `/etc/sddm.conf.d/`.
4. Changer la palette dans le panneau, relancer `install.sh --colors-only`,
   recontrôler la capture : le greeter doit suivre sans édition manuelle.

## Risques

- Un thème Qt6 dont le `Main.qml` lève une erreur ne casse pas la session : SDDM
  retombe sur un thème par défaut, mais l'écran de connexion devient inutilisable
  en cas d'erreur bloquante — d'où le test-mode avant toute bascule.
- `metadata.desktop` doit porter `Type=sddm-theme`, `MainScript=Main.qml`,
  `QtVersion=6` et `ConfigFile=theme.conf`, sinon le thème n'apparaît pas dans la
  liste (vérifié sur `ryoku`).
- Le greeter X11 démarre avant NetworkManager : l'avatar réseau et la météo sont
  hors sujet ici, ne rien afficher qui dépende d'un service de session.

## Trois décisions ouvertes

1. **Thème maison** (recommandé : zéro dépendance, palette Matugen, cohérence
   garantie) **ou** `sddm-astronaut` depuis l'AUR (plus vite posé, look tiers à
   re-colorer).
2. **Installation** : script séparé `dev/sddm/install.sh` + `pkexec` (recommandé)
   **ou** mode `--system` dans `deploy.sh`.
3. **Fond** : wallpaper courant assombri 40 % (recommandé) **ou** image dédiée
   figée dans `dev/sddm/theme/`.
