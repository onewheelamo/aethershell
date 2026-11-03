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
| 12 | OSD unique : volume et luminosité hors de la barre, barre de progression 2 px | `main.qml`, `island_right.qml` |

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

Reste : 4, 7, 9, 10, 11, 13, 14, plus les réserves du §4.

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

### 4. Dynamic island et routeur de popups par contenu — M

Objectif. La pilule centrale devient un objet à états dont la largeur s'anime, et
chaque zone cliquée ouvre le popup correspondant à sa nature, au lieu d'un popup
unique.

Règle demandée par l'utilisateur : le calendrier reste un popup, mais seulement
si l'on clique sur la date. Cliquer la pochette ou le titre ouvre les contrôles
Mpris, le volume ouvre son curseur, une notification ouvre son détail.

Fichiers. `island_center.qml` (1 215 l.), `Theme.qml` (`activePopup`),
`main.qml` (la condition `WlrLayershell.keyboardFocus` teste aujourd'hui
`activePopup === "wifi" || activePopup === "calendar"`).

Approche.
1. Remplacer l'état binaire `calendarOpen` par une propriété `centerState`
   (`idle`, `media`, `volume`, `brightness`, `notification`, `calendar`) portée
   par `island_center`, chaque zone cliquable la positionnant.
2. Contenu dans un `StackLayout`, largeur de la pilule en `implicitWidth` avec un
   `Behavior` sur ressort — les paramètres du ressort existent déjà dans
   `general.lua` (courbe `easy` : mass 1, stiffness 71.2633, damping 15.8273644).
3. Un seul popup par état, positionné sous la pilule, jamais deux à la fois.
4. Étendre la condition `keyboardFocus` de `main.qml` aux états qui demandent le
   clavier (recherche, calendrier).

Risques. Le clic sur la date doit rester distinct du clic sur l'heure : séparer
les deux `MouseArea` proprement, sinon le calendrier s'ouvre depuis n'importe
quel point de la pilule. Les états média dépendent de Mpris (player absent =
état media vide, à masquer).

Vérification. Une capture par état, plus un clic réel sur chaque zone.

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

### 9. Spotlight pill — M, après 5a

Objectif. Pilule bas-centre invoquée au clavier : launcher et commandes, Esc pour
fermer, remplace visuellement fuzzel.

Approche. Nouvelle surface `PanelWindow` (`namespace: "portable-spotlight"`,
`WlrLayer.Overlay`, focus clavier exclusif), champ de recherche, liste filtrée,
navigation clavier. Réutiliser `Theme.pillRadius` et l'échelle typo.

### 10. Which-key par submap — M

Objectif. Overlay deux colonnes listant les binds du submap courant, disparition
après deux secondes.

Prérequis (le vrai coût). Les binds sont déclarés en Lua via `hl.bind` ; il faut
un export : soit un hook au chargement qui écrit un JSON à côté de
`binds.lua`, soit un parseur du fichier. L'affichage lui-même est trivial ensuite.

### 11. Tiroir de réglages à droite — M/L

Objectif. Remplacer le panneau actuel (mur de lignes) par un tiroir de 380 px :
onglets, recherche, curseurs de 1 px.

Fichiers. `config_panel.qml` (2 278 l.) côté QML ; `core/config_manager.py`
(906 l.) ne bouge pas, c'est le backend.

Approche. Reprendre la structure des sections (`CollapsibleSection.qml`) mais en
tiroir plein hauteur, avec un index de recherche sur les libellés. Les tokens et
`Icon` étant en place, l'essentiel est de la mise en page.

### 13. Lock screen — S

Fichier. `~/.config/hypr/hyprlock.conf` (2,8 Ko, préservé au déploiement).

Objectif. Fond flouté 24 px, horloge à la même échelle typographique, une ligne
média, pas de paroles de chanson.

### 14. Notifications en cartes — M

Fichier. `island_right.qml` (1 840 l.).

Objectif. Cartes empilées, liseré accent de 2 px par application, titres sans
emoji, action « tout effacer » discrète.

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

---

## 5. Ordre conseillé

1. 13 (lock screen) — S, indépendant, gain immédiat.
2. 4 (dynamic island + routeur de popups) — le plus gros gain visuel, dépend de la
   règle de popups déjà arbitrée.
3. 14 puis 11 — les deux derniers murs de texte.
4. 9 et 10 — interaction clavier ; 10 commence par l'export des binds.
5. 7 — chantier séparé, en attente des wallpapers en calques.

---

## 6. Journal

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
