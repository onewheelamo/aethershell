# Fine tuning — propositions restantes (2026-11-03)

Suite de la feuille de route établie après dépouillement des tops r/unixporn,
r/hyprland et r/QuickShell. Ce fichier ne décrit que ce qui reste à faire : les
points déjà livrés servent de référence de style et de conventions.

Source de vérité : `/home/utilisateur/dev/quickshell_todo/dev/`. Toute modification se
fait ici, le déploiement (`dev/deploy_station.sh`) reste une étape distincte.

---

## 1. État au moment d'écrire

Fait et déployé :

| # | Point | Où |
|---|-------|-----|
| 1 | Jeu d'icônes unique monochrome (Material Design via `Icon.qml`) | `Icon.qml`, îlots, panneau, OSD |
| 2 | Échelle typographique en tokens (`text2xs`…`textXxl`, `iconSm/Md`) | `Theme.qml` §1B |
| 3 | Rythme géométrique (`padH`, `space1..4`, `gutter`, `pillRadius`) | `Theme.qml`, tous les fichiers QML |
| 5a | Capsule continue : une seule surface derrière les trois groupes | `main.qml` + `Theme.barMerged` |
| 8 | Flou derrière les surfaces layer-shell | `hypr_modular/general.lua` |
| 8b | Flou shell réglable à part des fenêtres (actif, seuil `ignore_alpha`, popups) | `config_panel.qml`, `config_manager.py`, bloc `shell-blur` de `general.lua` |
| 8c | Opacité shell séparée de l'opacité des fenêtres | `Theme.qml` (`shellOpacity`), `config_panel.qml`, `config_manager.py` |
| 6 | Liseré dégradé sur le workspace actif, avec repli fond plein sous 3:1 de contraste | `island_left.qml`, `Theme.qml` (`wsActiveOutline`) |
| 4 | Dynamic island : zone média au survol, popup MPRIS, routeur de clics (heure inerte, date → calendrier) | `island_center.qml`, `Theme.qml` (`activePopup` = `media`) |
| 12 | OSD unique : volume et luminosité hors de la barre, barre de progression 2 px | `main.qml`, `island_right.qml` |
| 14 | Notifications en cartes : liseré d'application 2 px, survol, corps à 3 lignes, « Tout effacer » discret | `island_right.qml` (§7.4 et §7.5) |
| 13 | Lock screen cohérent : fond flouté 24 px, Inter, heure tabulaire, ligne média, boutons MDI | `hypr_modular/hyprlock.conf`, `core/generate_rofi_theme.sh` §5 |
| 11 | Panneau de réglages centré 620 px : rail d'onglets, recherche qui saute à l'ancre, curseurs `Slider` | `config_panel.qml`, `main.qml`, `Slider.qml` |

Note 8 : sans `ignore_alpha = 0.4` dans la règle, Hyprland floute toute la
surface layer (fenêtre pleine largeur pour la barre, plein écran pour le panneau)
et pas seulement la capsule visible. Le seuil doit rester sous l'alpha des
surfaces du thème (`globalOpacity` 0.7–0.85).

Note 8b : les layer rules ne se changent pas à chaud en 0.57. Le panneau écrit
donc trois valeurs (`shell_blur_enabled`, `shell_blur_alpha`, `shell_blur_popups`)
dans `style_vars.json`, `config_manager.py` réécrit le bloc entre
`-- BEGIN shell-blur` et `-- END shell-blur` de `general.lua`, puis
`hyprctl reload`. La taille et les passes du flou restent communes aux fenêtres
(`decoration.blur`) : seul l'actif/le seuil/les popups sont propres au shell.

Note 8c : l'opacité est désormais séparée elle aussi. `global_opacity` ne touche
plus que les fenêtres (`decoration.active_opacity` / `inactive_opacity`) ;
`shell_opacity` alimente les surfaces Quickshell (`surfaceBg`, `surfaceVariantBg`,
`panelBg` dans `Theme.qml`). Le seuil de flou doit rester **sous** `shell_opacity`,
sinon Hyprland cesse de flouter : la ligne d'explication du panneau le dit.

Note 12 : la boîte système de la barre ne contient plus qu'une icône de volume, sans
pourcentage : elle ouvre le panneau (volume, luminosité, batterie). Volume et
luminosité ne s'affichent plus que dans l'OSD bas-centre, déclenché par
`core/osd.sh` (binds audio et `XF86MonBrightness*` de `hardware-portable.lua`).
Sur un poste sans batterie, cette icône est le seul contenu de la boîte : la
supprimer rendrait le panneau système inaccessible.

Note 4 : la pilule centrale a trois zones au clic — l'heure ne fait rien, la date
ouvre le calendrier, le libellé média ouvre le popup MPRIS. La zone média n'existe
qu'au survol **et** si une piste joue : pas d'élargissement permanent de la barre
(choix utilisateur). Le volume n'a pas été doublonné au centre : son curseur reste
dans le panneau système de l'île droite. Le popup s'appuie sur `mediaPlayer` (toute
piste, même en pause) et non sur `activePlayer` (en lecture seule), sinon appuyer
sur pause le refermait ; un `onPlayerChanged` le ferme si le lecteur disparaît.

Note 14 : les cartes du centre de notifications portent un liseré de 2 px à gauche,
franc sur la plus récente et effacé sur les anciennes — c'est la seule hiérarchie
de couleur, le fond ne change qu'au survol. Le nom d'application est en accent et
tronqué, l'heure en chiffres tabulaires, le corps limité à 3 lignes avec ellipse.
« Tout effacer » est neutre au repos et ne passe en `error` qu'au survol : le rouge
est un signal. Le toast (§7.5) n'a **pas** de liseré (retiré à la demande) et perd
sa bordure `warn` — une notification n'est pas une alerte.

Note 14b : le choix du toast se fait sur le toast lui-même. Une cloche barrée en
haut à droite écarte l'application : ses notifications ne s'affichent plus
spontanément et vont directement au centre. La liste vit dans
`core/style_vars.json` (`quiet_notif_apps`) via
`config_manager.py notif_quiet <true|false> <nom d'app…>`, donc elle survit aux
redéploiements et au redémarrage. Le centre rappelle les applications écartées
dans un pied discret (« Notifications silencieuses ») où chaque pastille se retire
d'un clic : le choix reste réversible sans repasser par un toast. La liste étant
relue par le `FileView` de `Theme.qml`, l'effet est immédiat dans les deux sens.

Note 13 : `hyprlock.conf` est désormais **dans le dépôt** (`dev/hypr_modular/`,
copié par `deploy.sh`) et ne contient aucune couleur en dur : il source
`~/.config/hypr/hyprlock-colors.conf`, régénéré depuis `style_vars.json` par
`generate_rofi_theme.sh`. Un changement de palette dans le panneau suit donc
jusqu'à l'écran de verrouillage. Le fond est `path = screenshot` flouté à 24 px :
rien à maintenir côté wallpaper, et le verrou reprend ce que la session affichait.

Reste : 7, 9, 10, 15, plus les réserves du §4.

Note 11 : le panneau est **centré** (620 px, hauteur bornée à 900 px) et non plus
ancré à droite — retournement de la décision initiale après revue. Une recherche
`targetMap` (id → item, QML n'expose pas `findChild`) déplie la section et défile
en trois passes ; `forceActiveFocus()` est nécessaire à l'ouverture, sinon
`WlrKeyboardFocus.OnDemand` ne donne jamais le clavier. Les listes d'applications
et d'autostart ont une hauteur calée sur leur contenu (plafonnée), et le panneau
a été repassé en largeurs fluides pour tenir dans 530 px de contenu.

---

## 2. Conventions à respecter dans tous les points suivants

- Aucun `font.pixelSize` littéral : uniquement les tokens de `Theme.qml`.
- Aucun glyphe écrit en dur dans un `Text` : passer par `Icon` (`glyph: "<nom>"`).
  Les codes Nerd Font s'écrivent `"\u{F0493}"`, jamais `"\uf0493"` (QML ne lit que
  quatre chiffres hexadécimaux).
- Aucune icône SVG tierce dans la barre : elle apporte sa palette et casse le
  monochrome.
- Les espaces de travail gardent leurs kanji 一…五 (choix utilisateur).
- Toute nouvelle propriété de style passe par un booléen ou un token dans
  `Theme.qml`, pour que le retour arrière soit d'une ligne.
- Vérification : `qmllint`, déploiement, `quickshell kill; quickshell -d`, capture
  `grim` puis recadrage zoomé ; pour Hyprland, `hyprctl configerrors` vide.

---

## 3. Fiches

### 7. Depth wallpaper — L, bloqué sur les assets

Objectif. Fond en 2–3 calques avec parallaxe de 6–10 px au changement de
workspace, les îles posées entre les calques.

Fichiers. `hyprquickpaper/shell.qml` (321 l.), `hyprquickpaper/config.json`.

Approche. Mode `depth` dans le carrousel existant : un manifeste par image
décrivant les calques (fichier, profondeur), un `Item` par calque, translation
proportionnelle au workspace actif.

Blocage. Il faut des wallpapers découpés en calques avec alpha. Sans eux l'effet
est impossible ; la segmentation automatique (détourage de sujet) est un autre
projet. Ne pas commencer le QML avant d'avoir choisi le format et deux images de
test.

### 9. Spotlight pill — LIVRÉ (v1 apps + v2 alias, commandes, historique)

Objectif. Pilule bas-centre invoquée au clavier : launcher d'applications, Échap
pour fermer, remplace fuzzel.

Livré. `dev/spotlight.qml` (pilule) + surface `PanelWindow`
`namespace: "portable-spotlight"` dans `main.qml` (`WlrLayer.Overlay`, focus
clavier exclusif, `ExclusionMode.Ignore`, fond transparent plein écran pour
capter le clic extérieur). `Theme.spotlightVisible` + IPC `toggleSpotlight`,
`showSpotlight`, `hideSpotlight`, `spotlightState`. Bind `SUPER + R`.
Index des applications : `core/app_index.py` → `core/app_index.json`
(noms `Name[fr]`, `Exec` nettoyé des `%f/%u/%U…`, icône, catégorie), régénéré au
déploiement et à chaque ouverture ; données de la machine, hors dépôt
(`.gitignore`). Icônes via `image://icon/<nom>`, repli sur l'initiale.

Pièges mesurés.
- `Loader` **impose sa taille à son item** : `height: item.height` sur le Loader
  crée une boucle et la pilule déborde par le bas. Le Loader remplit la fenêtre
  (`anchors.fill`) et c'est la pilule qui s'ancre (`bottom`, marge 44).
- Une zone inerte de la pilule (pied, marges) laisse passer le clic jusqu'au fond
  cliquable → fermeture inattendue. `MouseArea { anchors.fill: parent }` déclaré
  **avant** le contenu absorbe ces clics.
- `image://qsicon/` n'existe pas : le fournisseur est `image://icon/`.
- Le texte enrichi QML ne comprend pas `<span style=…>` pour la surlignure :
  `<font color=…><u>…</u></font>`.
- Ouverture sans requête = pilule repliée (comme la maquette) : la liste ne
  s'affiche qu'à la première frappe.
- Les tout premiers caractères tapés < ~1 s après l'ouverture peuvent se perdre
  (le grab clavier exclusive arrive après le map) : sans incidence à la main,
  visible avec un outil qui tape instantanément.
- Flou : ajouter `portable-spotlight` à `SHELL_BLUR_NAMESPACES`
  (`core/config_manager.py`) **et** au bloc `shell-blur` de `general.lua`.

v2 (livrée). Trois sources dans la même liste :
- **alias** — `core/app_vars.json`, les mêmes variables que les raccourcis
  Hyprland ; ajout/suppression déjà possible dans le panneau (onglet
  Applications), elles apparaissent donc dans la pilule sans doublon de config ;
- **commandes** — préfixe `>` : tout ce qui suit part dans `sh -c`, une seule
  ligne « COMMANDE », `Entrée` exécute ;
- **historique** — désactivé par défaut, activé par `launch_history` dans
  `style_vars.json` (ligne ✓/✕ + bouton « Vider » dans l'onglet Applications,
  trouvable par la recherche du panneau). Écrit par `core/launch_history.py`
  (`core/launch_history.json`, 25 entrées max, dédoublonnées par commande) ;
  champ vide = les 6 derniers lancements, étiquetés « RÉCENT ».

Le contournement fuzzel (bind `mouse:272` + `launcher_click_close.sh`) est
**retiré** : la surface se ferme elle-même.

Pièges v2.
- `get_full_config_state()` doit exposer chaque nouveau réglage, sinon le panneau
  ne voit jamais la valeur (elle reste à son défaut dans l'UI).
- Un bouton conditionnel placé à droite du libellé décale le toggle quand il
  apparaît : garder l'élément permanent contre le bord (ici « Vider » à gauche du
  ✓, le ✓ collé au bord).
- Les styles de boutons du panneau : `color: Theme.surfaceVariant` +
  `border.color: success/error` + `radius: Theme.globalRadius` ; un fond teinté à
  15 % paraît délavé à côté des autres lignes.

### 9bis. Barre au repos / réveillée — LIVRÉ

Objectif. La barre reste affichée mais effacée au repos ; elle prend l'allure d'un
popup quand on l'utilise.

Livré. `Theme.barRestOpacity = 0.2`, `Theme.barBg = Qt.alpha(surface, barOpacity)`
avec `barOpacity = barAwake ? shellOpacity : barRestOpacity`. `barAwake` est vrai
si la barre vient d'être cliquée (`barAroused`, 2,6 s), si un popup est ouvert
(`activePopup`) ou si la pilule est visible. La transition passe par le
`Behavior on color` existant (180 ms).

Pas de flou au repos, sans rien ajouter : la règle `layer_rule` porte
`ignore_alpha = 0.30`, donc Hyprland ne floute pas une surface à 0,2 ; à 0,7 le
flou de la règle s'applique à nouveau. Mesuré à la luminance moyenne de la
capsule : 77,1 au repos, 58,6 réveillée, retour à 77,1 après 3,4 s.

Piège. La barre est en mode fusionné (`barMerged = true`) : les trois îlots sont
transparents et la seule surface visible est `capsuleBg` dans `main.qml`. C'est
**elle** qu'il faut brancher sur `Theme.barBg` — changer les fonds d'îlots ne
produit rien de visible.

### 9quater. Lanceur toujours posé en veille — LIVRÉ

La pilule n'est plus une surface qui apparaît : c'est une capsule permanente en
bas au centre, à 0,2 (`Theme.spotlightRestOpacity` / `spotlightRestBg`), donc
sans flou par la même règle `ignore_alpha`. Un clic dessus ou `SUPER + R`
l'ouvre : elle prend l'opacité des surfaces Quickshell (`Theme.surfaceBg`,
`shell_opacity`) et le flou de la règle `layer_rule`.

Deux fenêtres, pas une :
- `portable-spotlight-rest` — 720 × 62, ancrée en bas, centrée par
  `margins.left = (largeur écran − 720) / 2` et `margins.bottom = 44`, focus
  clavier `None`, visible dès que la pilule est fermée. Étroite **exprès** :
  une surface layer consomme les clics sur toute sa zone, un plein écran au
  repos mangerait tous les clics de l'écran.
- `portable-spotlight` — plein écran, focus clavier exclusif, uniquement pendant
  la frappe (fond cliquable pour fermer au clic extérieur).

Les `margins` d'une `PanelWindow` fonctionnent bien ici (position mesurée :
`xywh 600 974 720 62` pour un écran de 1920 et une marge basse de 44) — le
commentaire de l'OSD qui les disait inopérants ne concerne que son cas.

La capsule passe **derrière** les fenêtres : une surface de la couche `bottom`
ne reçoit pas les clics (Hyprland ne route l'entrée que vers les couches
`top`/`overlay`) et reste sous les fenêtres. Elle est donc invisible dès qu'une
fenêtre couvre le bas de l'écran. Pour qu'elle reste cliquable quand elle est
réellement visible, sa couche est liée à l'occupation du workspace :
`WlrLayershell.layer: desktopClear ? WlrLayer.Top : WlrLayer.Bottom`, où
`desktopClear` compte les toplevels du workspace focalisé. Bureau nu : dessus,
donc cliquable (rien à masquer) ; fenêtre présente : dessous, effacée.

### 9ter. Îlot gauche sans lanceur — LIVRÉ

L'icône Arch et son séparateur sont retirés : l'îlot ne contient plus que les
workspaces (la largeur suit le contenu, `implicitWidth`). Le bind fuzzel était
déjà remplacé par `SUPER + R` → pilule ; `~/.config/fuzzel` est supprimé et
`core/generate_rofi_theme.sh` ne régénère plus de `fuzzel.ini` (section retirée,
sections renumérotées). Le paquet lui-même reste à désinstaller avec un mot de
passe root : `sudo pacman -Rns fuzzel`.

### 10. Which-key par submap — M

Objectif. Overlay deux colonnes listant les binds du submap courant, disparition
après deux secondes.

Prérequis (le vrai coût). Les binds sont déclarés en Lua via `hl.bind` ; il faut
un export : soit un hook au chargement qui écrit un JSON à côté de `binds.lua`,
soit un parseur du fichier. Aucun `submap` n'existe aujourd'hui dans `binds.lua` :
il faut donc d'abord décider quelles touches passent en sous-carte (gestion de
fenêtre ? redimensionnement ?) et les y déclarer, sinon l'overlay n'a rien à
montrer. L'affichage lui-même est trivial ensuite.

### 11. Panneau de réglages centré, 620 px — LIVRÉ

Objectif initial. Remplacer le panneau « mur de lignes » par un tiroir à droite
de 380 px : onglets, recherche, curseurs de 1 px.

Ce qui a été fait (commit `de8bdb7`). Le panneau reste **centré** (largeur 620,
hauteur bornée à 900 px au lieu de coller à la barre et au bas de l'écran), avec
un rail vertical d'icônes 44 px, un champ de recherche en haut et les sections
dépliées par défaut dessous. `Slider.qml` remplace les 9 `Stepper` (même API,
écriture backend au relâchement seulement). Toutes les rangées sont passées en
largeurs fluides : pastilles thème/schéma/contraste sur des lignes dédiées,
palette en `Flow`, carte de moniteur pleine largeur, raccourcis et variables
d'applications éllipsés, barre d'ajout de bind sur deux lignes.

Pièges rencontrés et solutions.
- La recherche saute à l'ancre : QML n'expose pas `QObject::findChild`, d'où la
  table `id -> item` (`targetMap`) ; le scroll se refait sur trois passes parce
  que le dépliage d'une section n'est pas mesurable à la frame suivante.
- Un `TextInput` consomme la touche Entrée : le saut doit être dans `onAccepted`,
  pas dans `Keys.onReturnPressed`.
- `WlrKeyboardFocus.OnDemand` ne donne jamais le clavier sans un
  `forceActiveFocus()` explicite à l'ouverture du panneau.
- Une carte de résultats en `anchors.fill` du parent circulaire se réduit à 8 px :
  ancre `top/left/right` seulement, hauteur = hauteur du contenu.
- Un `Flow` qui passe à la ligne n'agrandit pas toujours son `implicitHeight` :
  préférer des `Row` dédiées, ou une hauteur explicite.


### 15. Écran de connexion SDDM cohérent — M, décision d'installation à prendre

Objectif. L'écran de connexion ne doit pas casser l'unité visuelle : même fond
que le bureau, même accent, même typographie. Aujourd'hui SDDM est resté en
configuration par défaut (`/etc/sddm.conf.d/*.conf` → `Current=breeze`), donc en
rupture complète avec le reste.

Fichiers. Aucun pour l'instant : ni `dev/sddm/`, ni thème. Le greeter vit hors
session, il faut donc un nouveau répertoire dans le dépôt et une étape
d'installation distincte du déploiement ordinaire.

Approche.
1. Choisir le fond : le wallpaper courant, ou une variante assombrie d'environ
   40 % — un fond clair et chargé passe mal sous un formulaire translucide.
2. Choisir un thème Qt Quick pilotable par fichier (sddm-astronaut, Sugar Candy,
   Corners) : ils exposent `Background`, `Font`, `AccentColor`,
   `FormBackgroundColor`, donc réglables sans toucher au QML du thème.
3. Ne pas écrire les couleurs à la main : les dériver de `dev/core/style_vars.json`
   (palette `dynamic`) au moment du déploiement, comme `config_manager.py` le fait
   pour les layer rules. Un changement de palette doit se propager au bureau,
   à hyprlock et à SDDM en une seule opération.

Contraintes.
- SDDM tourne avant la session : ni Quickshell, ni variables d'environnement du
  shell. Tout doit être écrit sur disque à chaque changement de palette.
- `/etc/sddm.conf.d/` demande sudo : soit `deploy.sh` gagne un mode explicite,
  soit les fichiers vivent dans `dev/sddm/` avec une commande d'installation
  séparée. Même arbitrage que pour `hyprlock.conf` au point 13 — à trancher avant
  de commencer.
- Ne pas tester en redémarrant le service : `systemctl restart sddm` tue la
  session en cours. Passer par un TTY (Ctrl+Alt+F2) ou par
  `sddm-greeter-qt6 --test-mode --theme <chemin>`.

Vérification. Capture du greeter en `--test-mode`, comparaison des couleurs
dominantes avec la palette du bureau (accent et fond), puis changement de palette
dans le panneau et contrôle que le greeter suit sans édition manuelle.
---

## 4. Idées en réserve

Capsule à trois segments (proposition de l'utilisateur). Garder la capsule mais
rendre transparentes les deux zones de séparation, pour simuler trois îlots sans
revenir aux trois pilules indépendantes. Implémentation : dessiner le fond en
trois `Rectangle` qui partagent rayons et paddings, avec un booléen
`Theme.capsuleGaps` et une largeur de coupe. Aucun impact sur les îlots.

Variante `acrylic` du flou. `decoration.blur.variant = "acrylic"` avec
`clarity 0.82`, `refraction 24`. Attention : le variant est global, il change
aussi le flou des fenêtres flottantes. À essayer seul, avec mesure GPU.

Dette signalée dans `CLEANUP_PROPOSAL_2026-11-03.md` : `programs.lua` et
`autostart_cmds.txt` sont encore traités comme préservés alors qu'ils sont
générés ; ils produiront un `.upstream` dès que le panneau les modifiera. À
basculer en fichiers générés.

Deux symboles échappent encore au jeu d'icônes, trouvés par l'avertissement ajouté
à `Icon.qml` : `icon: "⏻"` sur un en-tête de section de `config_panel.qml` (donc
une icône vide) et un `Text` brut « ⏻ Session & Alimentation » dans
`island_right.qml`. Le premier se corrige en une ligne (`glyph: "power"`) ; le
second demande de passer la ligne par `Icon` + `Text`, deux lignes.

---

## 5. Ordre conseillé

Un lot, un chantier clavier, une décision.

- ~~**Lot C — 11 (panneau de réglages)**~~ — livré (commit `de8bdb7` puis retouches).
- **Lot D — 9 et 10 — M chacun.** Interaction clavier. 10 coûte plus que sa fiche :
  aucun `submap` n'existe aujourd'hui dans `binds.lua`, il faut d'abord créer les
  sous-cartes puis exporter les binds, avant d'afficher quoi que ce soit.
- **Décision — 15 (SDDM) — M.** Bloqué sur un arbitrage, pas sur du code :
  `deploy.sh` gagne-t-il un mode sudo, ou l'installation reste-t-elle une commande
  séparée depuis `dev/sddm/` ?
- **Chantier séparé — 7 (depth wallpaper) — L.** En attente des wallpapers en
  calques ; ne pas commencer le QML avant d'avoir choisi le format et deux images
  de test.

---

## 6. Journal

- 2026-11-03 : 13 livré — écran de verrouillage cohérent. `hyprlock.conf` entre
  dans le dépôt (`dev/hypr_modular/`, copié par `deploy.sh`) et source une palette
  générée (`hyprlock-colors.conf`, section 5 de `generate_rofi_theme.sh`) : plus
  aucune couleur en dur, et `~/.config/Brain_Shell/matugen/colors.conf` — disparu
  depuis la refonte, donc labels sans couleur — n'est plus référencé. Fond
  `path = screenshot` flouté 24 px, Inter 100 px avec chiffres tabulaires, date en
  toutes lettres, champ capsule 320×50, une ligne média, trois glyphes MDI
  cliquables. Pièges rencontrés : (a) hyprlang rejette `{{…}}` dans `text`
  (« Invalid expression type ») et le label retombe alors sur « Sample Text » —
  d'où `core/lock_media.sh` pour le format playerctl ; (b) dans `position`, un y
  positif place le widget **au-dessus** du centre ; (c) `pkill -USR1 hyprlock`
  déverrouille mais inscrit un échec dans `pam_faillock` (3 → 10 minutes de
  blocage du compte, à purger avec `faillock --user amo --reset`).

- 2026-11-03 : création du fichier. Points 1, 2, 3, 5a, 8 livrés et déployés.
  Commits : `16478d8` (fondations), `0d0dd46` (échappements `\u{…}`), `99d55cf`
  (unification des îlots), `7659ac9` (kanji + arch/power), `b1a7dea` (test 5a),
  puis fusion de la capsule en prod et ajout des `layer_rule`.
- 2026-11-03 : 8b livré — flou shell séparé du flou des fenêtres dans le panneau
  « Aspect technique du bureau » (deux groupes : fenêtres / surfaces Quickshell).
  Mesure A/B panneau ouvert : énergie de contours 32,4 → 23,5 (−27 %) flou actif,
  −0 % en zone témoin hors panneau ; seuil 0,90 (au-dessus de l'opacité 0,70)
  redonne exactement la valeur « désactivé », ce qui valide `ignore_alpha`.
- 2026-11-03 : 8c livré — opacité séparée. Les deux groupes portent maintenant
  l'opacité et le flou de leur cible. Indépendance mesurée : opacité fenêtres
  0,70 → 0,50 laisse la barre identique (écart 0,07, luminance 38,8 inchangée) et
  `decoration:active_opacity` suit à 0,50 ; opacité surfaces 0,70 → 0,35 laisse la
  fenêtre identique au pixel (écart 0,00) et ne touche pas `active_opacity`
  (toujours 0,70).
- 2026-11-03 : lot A livré (6 + 12). Liseré : le contour est tracé au `Canvas`
  d'`island_left.qml` (trait 1,5 px, accent 0,95 → 0,10) plutôt qu'avec deux
  Rectangles imbriqués, qui auraient doublé l'opacité de l'intérieur ; repli
  automatique sur le fond plein sous 3:1 (`Theme.wsActiveOutline`), 6,6:1 avec la
  palette courante. OSD : les pourcentages volume/luminosité ont quitté la barre,
  la boîte système ne garde qu'une icône de volume qui ouvre le panneau (vérifié
  au clic réel : « Contrôles système · Station » s'ouvre), barre de progression
  ramenée à 2 px. `hyprctl layers` ne liste pas les `PopupWindow` : l'absence de
  surface n'y prouve pas que le popup est fermé.
- 2026-11-03 : correctifs après retour sur le lot A.
  · Liseré : le rayon était borné par la seule hauteur (`min(radius, h/2)`) alors que
    le tracé est inset de 0,75 px. Les segments droits devenaient négatifs et QML
    dessinait deux ergots verticaux de chaque côté du kanji. Rayon borné par
    `(w-2i)/2` et `(h-2i)/2` ; fin du dégradé remontée de 0,10 à 0,30 pour que le
    contour se referme visuellement.
  · Molette de volume : elle avait disparu avec les indicateurs. Rétablie sur l'icône
    (clic gauche = panneau système, clic droit = mute), OSD immédiat via
    `Theme.showOsd`. Les touches média ne passaient que par l'OSD : l'icône attendait
    le sondage de 5 s, et une `Connections` sur `osdValue` ne peut pas tester
    `osdVisible` puisque `showOsd()` écrit la valeur avant de rendre la surface visible.
  · `Icon.qml` : `volume-high` manquait de la table. Un nom absent rend un texte vide
    sans message, donc le haut-parleur disparaissait au-dessus de 70 % dans la barre
    **et** dans l'OSD. Glyphe ajouté, plus un `console.warn` pour tout nom inconnu.
    Restent deux usages hors périmètre révélés par cet avertissement : `icon: "⏻"`
    dans `config_panel.qml` (en-tête de section sans icône) et un `Text` brut
    « ⏻ Session & Alimentation » dans `island_right.qml`.

- 2026-11-03 : 4 livré — dynamic island et routeur de clics. La pilule distingue
  désormais trois zones : l'heure ne fait rien, la date ouvre le calendrier, le
  libellé média ouvre un nouveau popup MPRIS (pochette ou icône, titre,
  artiste/album, progression 2 px, temps, previous / lecture-pause / next pilotés
  par `Services.Mpris`). Décisions prises : élargissement au survol seulement
  (pas d'état média permanent), volume non doublonné au centre, clic sur un toast
  → centre de notifications. Deux pièges : (a) une `Row` dans la `Column` du popup
  sans largeur explicite bouclait (`Column.width` ← `Row.width` ← `Column.width`)
  et tout le bloc titre restait invisible alors que la barre et les boutons
  s'affichaient ; (b) conditionner la visibilité du popup à « le joueur joue »
  refermait celui-ci à l'instant où l'on appuyait sur pause — d'où la séparation
  `mediaPlayer` (toute piste) / `activePlayer` (en lecture). Vérifié par clics
  réels : heure 795 px → rien, date 1090 px → calendrier, média 920 px → popup ;
  bouton central : `playerctl status` passe Playing → Paused → Playing sans que
  le popup se ferme ; barre de progression à 21 s sur une piste de 60 s (0:20 /
  -0:39, remplissage au tiers) ; toast réel (`notify-send`) → « Notifications (2) ».
- 2026-11-03 : popup média agrandi sur demande. 300 → 360 px, pochette 40 → 80 px
  (rayon 5), titre `textLg`, artiste `textSm`, progression 3 px, temps `textXs`,
  boutons `iconLg` (nouveau token `Theme.iconLg`, 22) dans une boîte 40×34. Deux
  défauts trouvés en testant avec de vrais lecteurs : la pochette peut arriver en
  `data:` base64 (mpv-mpris) et le préfixe `file://` la cassait — les schémas
  connus (`file://`, `http`, `data:`, `image://`) passent désormais tels quels ;
  et la zone média dépendait de « en lecture », or `isPlaying` tombe entre deux
  pistes : la zone clignotait et la pilule se rétractait. Elle suit maintenant
  `mediaPlayer` (toute piste), le survol étant déjà la condition d'affichage.
- 2026-11-03 : 14 livré — notifications en cartes. Liseré d'application de 2 px à
  gauche (franc sur la plus récente, effacé sur les anciennes), fond
  `surfaceVariant` sans bordure qui s'éclaircit au survol, nom d'app en accent,
  heure tabulaire, corps limité à 3 lignes avec ellipse, croix en `error` au
  survol seulement. En-tête : compteur en accent au lieu de « Notifications (3) » ;
  « Tout effacer » neutre au repos, rouge au survol. Le toast perd sa bordure
  `warn` et prend le même liseré : une notification n'est pas une alerte. État vide
  centré avec cloche barrée. Mesures : survol de carte +4/+6/+7 par canal au pixel ;
  « Tout effacer » ne rougit qu'au survol (255,180,171, la couleur `error` de la
  palette) ; nom d'app long tronqué sans toucher la croix ; corps coupé à 3 lignes.
  Piège de méthode : détruire le périphérique `/dev/uinput` entre deux positions
  casse le `HyprlandFocusGrab` et referme le popup — les survols se vérifient par
  petits déplacements internes, ou au pixel entre deux captures.
- 2026-11-03 : toast sans liseré + choix par application. Le toast ne porte plus
  de liseré (il reste dans le centre) et gagne une cloche barrée à droite de
  l'en-tête : elle ajoute l'application à `quiet_notif_apps`
  (`style_vars.json`), dont les notifications vont désormais directement au
  centre. Le centre affiche un pied « Sans apparition spontanée » avec une
  pastille par application écartée, retirable d'un clic. Cycle vérifié au clic
  réel : toast → cloche barrée → `["Thunar"]`, notification suivante sans toast
  (moyenne de zone 64,4 = sans toast contre 58,5 avec), carte toujours présente
  dans le centre, pastille « Thunar » puis `[]` après clic sur sa croix, toast de
  retour. Nom d'application avec espaces testé (« Strawberry Music Player »).
  Deux pièges : un enfant ajouté dans un `Flickable` est reparenté à son
  `contentItem` (hauteur 0) et se superpose au contenu — le pied devait être un
  frère du `Flickable` dans la `Column` ; et `Icon.qml` mappait `bell-off` sur
  `F009C`, qui est `bell-outline` (cloche simple, sans barre) — le glyphe
  « barré » ne l'était pas, corrigé en `F009B` (l'état vide de la barre et du
  centre affichait donc une cloche normale).
- 2026-11-03 : fenêtre blanche par instance de quickshell — corrigé. Chaque
  instance ouvrait une fenêtre toplevel vide (`class: org.quickshell`,
  `title: quickshell`) tuilée par le compositeur : trois instances donnaient trois
  barres empilées **et** deux fenêtres blanches (la première instance en avait une
  aussi, elle passait inaperçue). Cause : `shell.qml` était un `Loader` **à la
  racine** (`Loader { source: "main.qml" }`). Les fenêtres chargées n'ont alors pas
  de racine de shell, et Quickshell les héberge dans un `ProxyFloatingWindow`, qui
  se matérialise en toplevel vide (les avertissements « QML ProxyFloatingWindow:
  Setting width is deprecated » dans le log en étaient la seule trace). Réduit à
  un cas minimal en trois essais : `Loader` racine → 1 fenêtre blanche ;
  `ShellRoot { Loader }` avec un `Item` chargé → 0 ; `ShellRoot` direct → 0.
  Correctif : `shell.qml` devient `ShellRoot { Loader { source: "main.qml" } }` et
  la racine de `main.qml` passe de `ShellRoot` à `Item` (`ShellRoot` est
  optionnel). Vérifié : 1 instance → 0 fenêtre blanche, 0 avertissement proxy ;
  3 instances → 3 barres (normal, une par instance), **0** fenêtre blanche ; le
  toast, le centre de notifications et le pied « Notifications silencieuses »
  fonctionnent toujours. Piste complémentaire non appliquée : lancer
  `quickshell -n` (--no-duplicate) dans l'autostart pour empiler zéro barre au
  lieu de trois.

- 2026-11-03 : fuzzel restait affiché malgré un clic à l'extérieur — corrigé.
  Le launcher quitte pourtant sur perte de focus clavier
  (`exit-on-keyboard-focus-loss=yes` dans `fuzzel.ini`), mais Hyprland 0.57 ne
  retire pas le focus clavier d'une surface layer quand le clic tombe sur le
  bureau (aucune surface à focaliser) ou sur la fenêtre **déjà** active (pas de
  changement de focus, donc pas de `wl_keyboard.leave`). Un clic sur la barre ou
  sur une autre fenêtre fermait bien fuzzel : le bug était limité à ces deux cas.
  Corrigé par un bind souris **non-consommant** (`binds.lua`,
  `{ mouse = true, non_consuming = true }` sur `mouse:272`) qui lance
  `core/launcher_click_close.sh` : le script sort immédiatement si fuzzel ne
  tourne pas, sinon compare `hyprctl cursorpos` à la géométrie de la couche
  `launcher` et `pkill -x fuzzel` seulement si le clic est dehors. Le clic
  continue vers la fenêtre en dessous. Mesuré : ~20 ms par clic quand fuzzel est
  fermé (le `pgrep` précède tout appel `hyprctl`), et le bind `SUPER + mouse:272`
  de déplacement de fenêtre reste prioritaire (modmask 64 vs 0).
  **Périmé depuis le point 9** : la pilule spotlight remplace fuzzel, le bind
  `mouse:272` et `core/launcher_click_close.sh` sont supprimés (la surface gère
  son propre clic extérieur). Le journal reste comme trace de la limite
  d'Hyprland 0.57 sur le focus des surfaces layer.
