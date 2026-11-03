# Point 11 — Tiroir de réglages à droite

Proposition avant implémentation. Rien n'est codé à ce stade.

---

## 1. Constat mesuré

Le panneau actuel n'est pas un « mur de lignes » informe : il a déjà des onglets.
Le point 11 porte donc sur la **forme** (fenêtre centrée → tiroir) et sur trois
manques, pas sur une réécriture du backend.

| Élément | État actuel |
|---|---|
| Fenêtre | `main.qml` → `PanelWindow` plein écran (`shell-config`, Overlay), un `Loader` `anchors.centerIn` charge `config_panel.qml` |
| Panneau | `Rectangle` 680 × 560, rayon `Theme.globalRadius`, bordure accent 1 px |
| En-tête | titre + bouton de fermeture (croix) 32 × 32 |
| Onglets | `Row` de 4 boutons 34 px : Esthétique, Système & Écrans, Contrôles, Applications |
| Contenu | `Flickable` clippé, 4 `Column` (une par onglet), `contentY = 0` au changement d'onglet |
| Sections | 4 `CollapsibleSection` : « Thème & Fond d'écran », « Aspect technique du bureau », « Programmes par défaut des raccourcis », « Programmes lancés au démarrage » |
| Contrôles numériques | 12 `Stepper` (boutons − / +, molette, appui long) : gaps in/out, bordures, arrondis fenêtres, arrondis îlots, hauteur de barre, pas de redimensionnement, opacité fenêtres, taille du flou, passes du flou, opacité surfaces, seuil de flou |
| Autres contrôles | éditeur hexadécimal de palette, presets Matugen, grille de moniteurs (résolution, taux, échelle), timezone + NTP, aperçu du clavier, table des binds, liste d'autostart, 4 `Process` (état, commandes, sysinfo) |
| État persisté | `panel_sections` dans `style_vars.json` (`esthetique_theme`, `esthetique_aspect`, `apps_programs`, `apps_autostart`) |
| Taille du fichier | `config_panel.qml` 2 482 l., `core/config_manager.py` 1 023 l. (inchangé par ce lot) |
| Absent | aucune recherche, aucun curseur, aucune notion d'ancrage ou de défilement ciblé |

Contraintes de design déjà en place et à respecter : aucun `font.pixelSize`
littéral (tokens de `Theme.qml`), aucun glyphe en dur (passer par `Icon`), libellés
en français, rouge `Theme.error` réservé au signal.

---

## 2. Objectif

Un tiroir ancré à droite, 380 px de large, pleine hauteur sous la barre : on garde
la barre visible et on gagne un objet qui appartient au bord de l'écran au lieu
d'une boîte flottante au centre. Trois ajouts : onglets qui tiennent dans la
largeur, curseurs de 1 px pour les valeurs continues, recherche.

Ce qui ne change pas : le backend (`config_manager.py`, `style_vars.json`),
la file de commandes (`cmdQueue`), `applyStateJson`, l'état `panel_sections`,
les 4 onglets et leur contenu.

---

## 3. Géométrie

- Fenêtre : `PanelWindow` inchangée (plein écran, Overlay, `shell-config`), le
  clic hors du tiroir ferme toujours le panneau.
- Loader : `anchors.centerIn` → ancrage à droite,
  `anchors.rightMargin: Theme.gutter`,
  `anchors.topMargin: Theme.barHeight + Theme.gutter * 2`,
  `anchors.bottomMargin: Theme.gutter`.
- Panneau : `width: 380`, hauteur = hauteur disponible (plus de 560 fixe), rayon
  `Theme.globalRadius` conservé, bordure accent 1 px conservée.
- En-tête : 44 px, titre `textLg`, croix à droite ; nouveau champ de recherche
  dessous (voir §5).
- Bandeau d'onglets : voir §4.
- Zone de contenu : `Flickable` entre le bandeau et le bas, marges `Theme.space4`
  à gauche/droite (16 px utiles de chaque côté → colonne de contenu 348 px).

Sur 1920 × 1080 avec `barHeight` 40 et `gutter` 8 : tiroir de 380 × 1016, à
8 px du bord droit et 56 px du haut. À vérifier à 125 % d'échelle avant de figer
les marges.

---

## 4. Onglets : rail vertical ou bandeau compact

Quatre libellés dans 380 px donnent 95 px par onglet : « Système & Écrans » ne
tient pas. Deux variantes.

**A — rail vertical d'icônes (recommandé).** Une colonne de 44 px à gauche du
tiroir, 4 boutons carrés de 36 px (palette, moniteur, clavier, fusée), l'actif en
accent plein. Le libellé apparaît en `textXs` sous l'icône au survol, dans une
info-bulle interne (pas de tooltip système). Le contenu dispose alors de
380 − 44 − 32 = 304 px utiles. Avantage : la hauteur sert au contenu, l'onglet
actif est lisible d'un coup d'œil, et la recherche peut occuper le haut du tiroir
sans concurrence. Inconvénient : 44 px de largeur perdus.

**B — bandeau horizontal compact.** Icône seule + libellé court (« Esthétique »,
« Système », « Clavier », « Apps ») en `textXs`, 4 boutons de 84 px. Avantage :
aucune largeur perdue, structure actuelle conservée (donc diff plus petit).
Inconvénient : les libellés raccourcis s'éloignent des intitulés des sections et
la barre de recherche doit tenir sur une ligne de plus.

Le choix A change la structure (une colonne + une zone de contenu) mais supprime
le problème de largeur une fois pour toutes. Le choix B est un diff de 30 lignes.
**Recommandation : A.**

---

## 5. Recherche

Trois approches, du moins cher au plus complet.

**Option 1 — filtre de sections (S).** Le champ ne cherche que dans les 4 titres
de section + les libellés d'onglets : il bascule sur l'onglet et déplie la section
correspondante. Coût faible, mais 4 entrées rendent la recherche décorative.

**Option 2 — index d'ancres (M, recommandé).** Une table statique dans
`config_panel.qml`, une entrée par réglage (≈ 34 entrées) :

```qml
readonly property var searchIndex: [
    { label: "Opacité des surfaces du shell", words: "opacite transparence verre shell",
      tab: 0, section: "esthetique_aspect", target: "shellOpacityRow" },
    …
]
```

Chaque entrée porte un `target` : l'`id` de la ligne QML concernée. Une fois
l'onglet actif et la section dépliée, `mapToItem(mainFlickable.contentItem, 0, 0).y`
donne la position et le `Flickable` y amène avec une animation de 180 ms ; la ligne
clignote une fois en accent (opacité 0.18 → 0, 600 ms) pour montrer où l'on arrive.
Coût : ajouter un `id` aux ~34 lignes ciblées, écrire la table, tenir la table à
jour quand un réglage change de place. C'est la seule option qui rende la recherche
utile sans annoter les 2 482 lignes.

**Option 3 — annotation par ligne (L).** Chaque ligne déclare ses mots-clés, la
recherche filtre réellement l'affichage. Coût : toucher toutes les lignes du
panneau, et le filtrage casse les hauteurs implicites des `CollapsibleSection`.
**Recommandation : 2, en second temps (volet V4), une fois le tiroir stable.**

Comportement retenu pour l'option 2 : `/` ou `Ctrl+F` met le focus dans le champ,
`Échap` le vide puis ferme le tiroir, `↑`/`↓` parcourent les résultats, `Entrée`
saute au réglage. Le champ affiche les résultats dans une liste de 5 lignes
maximum, sous le champ, par-dessus le contenu (fond `surfaceBg`, ombre portée par
bordure accent 1 px).

---

## 6. Curseurs de 1 px

Nouveau composant `Slider.qml`, dans l'esprit de `Stepper.qml` (même API de
propriétés, même émission `valueModified`), pour que le remplacement soit
mécanique :

```qml
Slider {
    value: root.gapsIn; minimumValue: 0; maximumValue: 10; stepSize: 1
    onValueModified: function(v) { root.runConfigCmd(["gaps", v, root.gapsOut]) }
}
```

Spec visuelle (tokens existants, aucune constante nouvelle hors hauteurs) :

| Élément | Valeur |
|---|---|
| Hauteur du composant | 26 px (comme `Stepper`) |
| Piste | 1 px, `Theme.surfaceVariant` ; partie remplie en `Theme.accent` |
| Poignée | 3 × 11 px, rayon 1,5, `Theme.accent` ; 5 × 13 au survol et pendant le glissement |
| Valeur | texte `textXs`, chiffres tabulaires, aligné à droite, 44 px réservés, suffixe conservé (« px », « % ») |
| Interaction | glissement continu, clic sur la piste, molette (± `stepSize`), accrochage à `stepSize` |
| Accessibilité | le clavier n'est pas branché dans ce lot (le tiroir n'a pas de focus par ligne) ; la molette et le clic restent |

Les 12 `Stepper` deviennent des `Slider`, sauf ceux dont la plage est trop
petite pour un curseur utile : « Gaps internes » (0–10), « Bordures » (0–6) et
« Passes du flou » (1–6) restent des `Stepper`. Les 9 autres passent en curseur :
gaps externes, arrondis fenêtres, arrondis îlots, hauteur de barre, pas de
redimensionnement, opacité fenêtres, opacité surfaces, seuil de flou, taille du
flou.

`Stepper.qml` reste dans le dépôt : il garde ces trois réglages et la mise à la
valeur exacte à la molette.

---

## 7. Découpage en volets

Chaque volet se déploie et se vérifie seul ; un volet raté ne laisse pas le
panneau à moitié converti.

**V1 — géométrie et en-tête.** Loader ancré à droite, panneau 380 × hauteur
disponible, en-tête 44 px, marges internes. Aucun contenu déplacé. Vérification :
capture du tiroir ouvert, barre toujours visible, clic hors tiroir qui ferme.

**V2 — onglets en rail.** Selon la variante retenue. Vérification : les 4 onglets
basculent, l'onglet actif se distingue, le contenu ne déborde pas de 304 px.

**V3 — curseurs.** `Slider.qml` + remplacement des 9 réglages. Vérification :
chaque curseur écrit la même valeur que le `Stepper` qu'il remplace (comparer
`style_vars.json` avant/après pour trois d'entre eux), la poignée se déplace,
la valeur affichée est celle du fichier après rechargement.

**V4 — recherche.** Table d'ancres, champ, navigation. Vérification : trois
recherches représentatives (« opacité », « flou », « autostart ») mènent au bon
onglet, à la bonne section, et la ligne ciblée est visible à l'écran.

Ordre conseillé : V1, V2, V3 (visible et mesurable), puis V4 après revue du
résultat. Les quatre volets tiennent dans un lot.

---

## 8. Risques et parades

| Risque | Parade |
|---|---|
| Largeur 380 insuffisante pour la grille des moniteurs | La grille passe en une colonne (elle est déjà en grille de cartes) ; vérifier à 1920 px puis à 125 % d'échelle |
| Le panneau devient trop haut et le `Flickable` perd le haut du contenu | `contentY = 0` conservé au changement d'onglet et à l'ouverture |
| Curseur qui écrit à chaque pixel de glissement | `onValueModified` n'est émis qu'à la fin du glissement et sur la molette (comme `Stepper`), pas à chaque `positionChanged` |
| Recherche qui pointe une ligne dans une section repliée | Le saut déplie la section avant de calculer `y` (via `setPanelSection`), puis attend une frame (`Qt.callLater`) |
| Régression d'état | `panel_sections` et `style_vars.json` inchangés ; le panneau relit l'état complet à l'ouverture (`refreshConfigState`) |
| `⏻` en icône de section (`apps_autostart`) | Corrigé au passage : `glyph: "power"` (déjà présent dans `Icon.qml`) — c'est le défaut signalé au §4 du backlog |

---

## 9. Vérification commune

```
qmllint dev/config_panel.qml dev/Slider.qml
cd /home/utilisateur/dev/quickshell_todo && printf '1\ns\n' | bash dev/deploy.sh --station
for p in $(pgrep -x quickshell); do kill $p; done; quickshell -d
hyprctl layers | grep -c shell-config      # 1 quand le panneau est ouvert
grim, puis recadrage zoomé du tiroir
diff -q dev/config_panel.qml ~/.config/quickshell/config_panel.qml
```

Contrôle de non-régression fonctionnelle, au clic réel (`/dev/uinput`) : ouvrir le
tiroir, changer d'onglet, déplier une section, déplacer un curseur, fermer par
clic extérieur et par `Échap`.

---

## 10. Décisions demandées

1. **Onglets** : rail vertical d'icônes (A, recommandé) ou bandeau horizontal
   compact (B, diff minimal) ?
2. **Recherche** : la garder dans ce lot (V4, option 2) ou livrer d'abord le
   tiroir et les curseurs, et décider la recherche sur pièce ?
3. **Largeur** : 380 px (fiche) ou 420 px, qui laisse respirer la grille des
   moniteurs et les libellés longs (« Opacité des surfaces du shell ») ?
