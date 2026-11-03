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

Reste : 4, 6, 7, 9, 10, 11, 12, 13, 14, plus deux idées en réserve (§4).

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

### 6. Liseré dégradé sur le workspace actif — S

Objectif. Remplacer le bloc de couleur plein par un contour dégradé, plus discret.

Fichier. `island_left.qml`, délégué de `workspaceRow`.

Approche. QML ne sait pas dégradé une bordure : deux `Rectangle` imbriqués, le
extérieur en `LinearGradient` accent → transparent (horizontal), l'intérieur en
couleur de fond avec 1 px d'inset, rayon identique.

Risque. Sur un fond d'écran clair, le liseré disparaît ; prévoir un repli sur le
fond plein si le contraste calculé est insuffisant.

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

### 12. Un seul OSD capsule — S/M

Objectif. Volume, luminosité et mute dans une seule capsule bas-centre, barre de
progression 2 px, au lieu des indicateurs dispersés.

Fichiers. `main.qml` (surface `portable-osd` déjà en place, `Theme.osdKind` /
`Theme.osdValue`), `island_right.qml` (indicateurs de volume et de luminosité à
retirer).

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

1. 12 (OSD unique) puis 6 (liseré) — finitions visibles, risque faible.
2. 4 (dynamic island + routeur de popups) — le plus gros gain visuel, dépend de
   la règle de popups déjà arbitrée.
3. 11 puis 14 — les deux derniers murs de texte.
4. 7 — chantier séparé, en attente des wallpapers en calques.
5. 9, 10, 13 — interaction et finitions ; 13 est indépendant et rapide.

---

## 6. Journal

- 2026-11-03 : création du fichier. Points 1, 2, 3, 5a, 8 livrés et déployés.
  Commits : `16478d8` (fondations), `0d0dd46` (échappements `\u{…}`), `99d55cf`
  (unification des îlots), `7659ac9` (kanji + arch/power), `b1a7dea` (test 5a),
  puis fusion de la capsule en prod et ajout des `layer_rule`.
