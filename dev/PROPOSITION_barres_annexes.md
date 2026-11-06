# Barres annexes — popups et rendu vertical

État au 2026-11-06. Ce document décrit ce qui existe, ce qui casse quand un applet
quitte la barre du haut, le modèle proposé, et les décisions qui appartiennent à
Amo. Rien n'est codé tant que les décisions ne sont pas tranchées.

---

## 1. Inventaire mesuré

**Surfaces.** `bar_extra.qml` produit une surface par barre, `cote` valant
`bas`, `cote-gauche` ou `cote-droite`. Chaque barre a trois zones
(`debut`, `milieu`, `fin`). En bas, les applets sont posés par `AppletRow` (des
`Row`) ; sur les côtés, par `AppletColumn` (des `Column`).

**Géométrie.** Une barre latérale fait `Theme.barHeight` de large, soit 36 px, sur
toute la hauteur de l'écran. C'est la largeur d'une barre, pas celle d'un applet.

**Le problème de fond.** `Applet.qml` dimensionne un applet sur
`contenu.implicitWidth`, où `contenu` est une `Row` horizontale (icône + valeur).
Rien ne contraint cette largeur : dans une bande de 36 px, un applet en occupe
60 à 250 et déborde sur le bureau. `AppletColumn` empile donc des objets plus
larges que lui.

**Ancrage des popups.** Treize déclarations `anchor.rect` dans huit fichiers :

| Fichier | y | x |
| --- | --- | --- |
| `Applet.qml` (carte de survol, popup) | `Theme.barHeight + 6` | 0 |
| `NotifsApplet`, `ReseauApplet`, `VolumeApplet` | `Theme.barHeight + 6` | centré sur l'applet |
| `PowerApplet` | `Theme.barHeight + 6` | aligné à droite |
| `CalendrierPanneau` | `versLeBas ? +hauteur : -hauteur` | centré sur l'îlot |
| `MediaPanneau` | `ancre.popupY(ancre)` | centré, puis `clampPopupX` |
| `island_right` (menu systray) | `popupY` | aligné à droite, puis `clampPopupX` |

Trois fichiers savent donc déjà ouvrir d'un autre côté (`versLeBas`, `popupY`,
`clampPopupX`), mais aucun ne connaît l'orientation de la barre : tous supposent
« la barre est en haut, le popup s'ouvre dessous ».

**Deux panneaux sont soudés à l'îlot central.** `CalendrierPanneau` et
`MediaPanneau` sont instanciés dans `island_center.qml` et s'ancrent sur l'îlot
(`ancre: islandCenter`), pas sur l'applet. Les applets `calendrier` et `musique`
sont marqués `_popup_externe` : `Applet.qml` ne dessine rien pour eux. Si l'un
d'eux est déplacé sur une barre latérale, son panneau continuera de s'ouvrir sous
l'îlot central de la barre du haut — à l'autre bout de l'écran.

**Applet en mode jauge.** `systeme` dessine quatre pistes de 26 px précédées d'une
icône : environ 150 px de large. Verticalement, cela ne tient pas dans 36 px.

---

## 2. Modèle proposé

### 2.1 Ancrage directionnel, une seule règle

Un helper unique dans `Theme` rend le rectangle du popup pour un applet donné :

```qml
// ile : "<barre>:<place>" ; applet : l'Item ; popupW/popupH : taille du popup
Theme.ancrePopup(ile, applet, popupW, popupH)  // -> { x, y }
```

| Barre | y | x |
| --- | --- | --- |
| `haut` | `barHeight + 6` | inchangé (0, centré ou droite selon l'applet) |
| `bas` | `-(popupH + 6)` | inchangé |
| `cote-gauche` | centré verticalement sur l'applet | `barHeight + 6` |
| `cote-droite` | centré verticalement sur l'applet | `-(popupW + 6)` |

`PopupAdjustment.All` reste le filet de sécurité : si un popup ne tient pas à
l'écran, Quickshell le retourne ou le fait glisser.

Les huit fichiers concernés appellent ce helper au lieu d'écrire `barHeight + 6`.
Sur la barre du haut, le résultat est **identique** à aujourd'hui : c'est ce qui
rend le lot vérifiable sans risque.

### 2.2 Rendu vertical d'un applet

`Applet.qml` reçoit une propriété `verticale` (posée par `AppletColumn`). Quand
elle est vraie :

- `contenu` devient une `Column` au lieu d'une `Row` : icône au-dessus, valeur en
  dessous, la largeur de l'applet est bornée à `Theme.barHeight` ;
- le popup et la carte de survol s'ouvrent **de côté** (§2.1) ;
- la valeur n'est plus défilante mais tronquée à la largeur de la bande
  (défiler sur 36 px ne se lit pas).

`AppletColumn` n'a alors plus rien à corriger : ses enfants sont à sa largeur.

### 2.3 Ce que le modèle ne règle pas

- **Les deux panneaux externes** (calendrier, média) restent ancrés sur l'îlot
  central. Décision à prendre : les interdire ailleurs que dans la barre du haut,
  les y autoriser en assumant un panneau mal placé, ou les migrer dans
  `Applet.qml` (gros lot, six cents lignes de QML à déplacer).
- **L'applet jauge** garde son rendu horizontal ou passe en icône+valeur sur un
  côté. Décision aussi.

---

## 3. Découpage en lots

**Lot A — ancrage directionnel.** Helper `Theme.ancrePopup`, puis les huit
appels. Aucun changement visible sur la barre du haut. Vérifiable en comparant
deux captures avant/après, puis en allumant une barre du bas.

**Lot B — rendu vertical.** `Applet.qml` (`verticale`), `AppletColumn.qml`
(pose la propriété), `bar_extra.qml` (largeur de bande, marges). Se vérifie avec
une barre latérale allumée.

**Lot C — passe de vérification et documentation.** Captures, `hyprctl layers -j`
(largeur de la surface = 36 px), clic → popup à côté, clic extérieur → fermeture,
Échap, et mise à jour de `references/bar-applets.md` dans le skill.

---

## 4. Risques

- Un popup qui s'ouvre du mauvais côté est **invisible** en test : il faut
  allumer réellement une barre du bas et une barre latérale pour le voir.
- `PopupAdjustment.All` masque les erreurs d'ancrage : un popup mal placé reste
  souvent affiché, juste au mauvais endroit. Comparer les coordonnées dans
  `hyprctl layers -j` plutôt que se fier à « il s'affiche ».
- Allumer une barre latérale change la zone exclusive d'Hyprland : les fenêtres
  se réordonnent. À faire quand Amo ne travaille pas dans une fenêtre plein écran.
- `AppletColumn` en mode vertical passe par la même `MouseArea` : le clic reste
  celui de l'applet, mais la carte de survol doit aussi changer d'axe, sinon elle
  recouvre la colonne.

---

## 5. Commandes de vérification

    # largeur réelle de la surface et position des popups
    hyprctl layers -j | jq '.[] | .levels[] | .[] | select(.namespace|startswith("shell-bar")) | {namespace, x, y, w, h}'

    # capture d'une bande latérale (barre à gauche, écran 1920x1080)
    grim -g "0,0 80x1080" /tmp/barre-gauche.png

    # état des applets placés
    python3 ~/.config/quickshell/core/bar_applets.py resoudre cote-gauche:milieu

---

## 6. Décisions qui appartiennent à Amo

1. Rendu d'un applet sur une barre de côté : icône au-dessus de la valeur,
   icône seule (valeur au survol), ou valeur seule.
2. Popup d'une barre de côté : à côté de l'applet centré verticalement, ou aligné
   sur le haut de l'applet.
3. Applets à panneau externe (calendrier, musique) sur une barre latérale :
   interdits ailleurs que dans la barre du haut, autorisés avec un panneau
   ouvert sous l'îlot central, ou migration des panneaux dans `Applet.qml`.
4. Applet jauge (`systeme`) sur un côté : rendu normal icône + valeur, ou quatre
   mini-pistes empilées.
5. Quelle barre allumer pour la vérification : bas, côté gauche, ou les deux.
