# Point 4 — Dynamic island et routeur de popups

**Appliqué** (commit `d2458c9`). Décisions retenues : élargissement média au survol
seulement, volume laissé dans le panneau de l'île droite, clic sur toast → centre de
notifications. La description ci-dessous est l'état de la proposition au moment du
go ; pour ce qui a réellement été fait, voir la note 4 et le journal de
`fine_tune.md`. Conservé comme trace du raisonnement.

Proposition avant implémentation. Rien n'est encore modifié dans le QML.

## Ce qui existe aujourd'hui (vérifié dans le code)

`island_center.qml` (1 215 l.) :

- `clockText` (HH:MM), largeur intrinsèque.
- `dateExpandBox` : boîte de 24 px de haut qui s'ouvre au survol
  (`expandProgress`, `Behavior` non animé — c'est la largeur qui est liée à la
  progression) et affiche soit la date longue, soit le titre média
  (`hoverDisplayText`).
- Une seule `MouseArea` couvre toute la pilule sauf l'engrenage : elle ouvre le
  calendrier où qu'on clique.
- `gearBtn` : bascule le panneau de configuration.
- `calendarPopup` : `PopupWindow` de 310 px, calendrier + Nextcloud.

Le média n'existe donc **que** comme texte au survol : `activeMediaInfo` lit
`Mpris.players` (browsers filtrés) et son `Timer` ne tourne que si `hovered`.
Aucun contrôle, aucune progression, aucun popup média.

Ailleurs : le volume et la luminosité sont des `Slider` du popup « system » de
l'île droite (§7.2, `island_right.qml`), et les notifications ont leur centre
(§7.4) plus un toast éphémère (§7.5) qui ne réagit pas au clic.

## Machine à états de la pilule

`centerState` ∈ `idle` | `media`, porté par `island_center` ; `Theme.activePopup`
garde son rôle de coordinateur inter-îlots et accueille `"media"` en plus des
valeurs existantes.

| État | Contenu de la pilule | Sortie |
|------|----------------------|--------|
| `idle` | heure + date (ou date longue) | clic date → `calendar` |
| `media` | heure + titre/artiste + ⏮ ⏯ ⏭ | clic titre → `media` |

Contenu dans un `StackLayout`, largeur = `implicitWidth` de l'état courant avec
`Behavior` sur ressort (`mass 1, stiffness 71.2633, damping 15.8273644`, la courbe
`easy` déjà utilisée par Hyprland). La pilule est centrée : elle s'élargit
symétriquement sans pousser les îlots voisins.

Clic : la `MouseArea` unique disparaît au profit de zones distinctes — heure
(inerte), date (calendrier), zone média (popup média). C'est le point de rupture
avec l'existant : aujourd'hui n'importe quel clic ouvre le calendrier.

## Popup média (nouveau)

Compact, 300 px, ancré sous la pilule comme le calendrier : pochette si
`trackArtUrl` existe, titre, artiste, album, barre de progression
`position/length` (1 px, `Behavior` sur la valeur), trois boutons MDI
(`skip-previous`, `play`/`pause`, `skip-next`), état du lecteur reflété
(`playbackStatus`). Pilotage direct sur `Mpris.players.values[0]`, sans passer par
un process : les méthodes du service sont celles de l'objet du joueur.

Le calendrier perd sa `MouseArea` pleine largeur mais garde tout le reste.

## Fichiers

- `island_center.qml` : `centerState`, `StackLayout`, zones de clic, popup média
  (~+250 l.).
- `Theme.qml` : ajout de `"media"` dans la liste documentée de `activePopup` ;
  aucune nouvelle propriété de style.
- `main.qml` : `keyboardFocus` étendu aux états qui écrivent (aucun des deux ne
  demande le clavier aujourd'hui — calendrier déjà présent, média n'a pas de
  champ ; la condition reste inchangée sauf si le popup média gagne un champ).
- `island_right.qml` : rien, sauf si le clic sur toast est retenu (voir décision 3).

## Risques

- **Largeurs qui sautent** : `implicitWidth` de la pilule est déjà
  `contentRow.implicitWidth + padH*2` ; passer à un `StackLayout` exige de suivre
  la largeur de l'état courant, sinon la barre oscille pendant l'animation. À
  vérifier au ralenti, pas à l'œil.
- **MPRIS absent** : `activeMediaInfo` vaut `null` ; l'état média doit être
  interdit (pas de pilule élargie sur un lecteur fantôme).
- **Le titre peut faire 80 caractères** : largeur maximale à borner et élision,
  sinon la pilule mange la moitié de l'écran.
- Le calendrier est un gros composant : ne pas le déplacer dans le `StackLayout`,
  il reste un popup séparé.

## Vérification

1. `qmllint`, déploiement, redémarrage, `Configuration Loaded`.
2. Une capture par état (`idle`, `media`), zoom sur la pilule.
3. Clic réel par `/dev/uinput` : sur la date → calendrier ; sur le titre → popup
   média ; sur l'heure → rien.
4. `mpris` piloté depuis le popup : `playerctl play-pause` doit suivre, et
   inversement le glyphe doit suivre `playerctl`.
5. Contrôle que `Theme.activePopup` reste exclusif : ouvrir calendrier puis popup
   média ne doit jamais laisser deux fenêtres.

## Décisions à prendre

1. **État média** : élargissement automatique dès qu'une piste joue, ou seulement
   au survol / au clic ?
2. **Volume** : la fiche disait « le volume ouvre son curseur », mais depuis le lot
   A le curseur vit dans le panneau système de l'île droite. Doublonner au centre,
   déplacer, ou laisser en place ?
3. **Clic sur un toast de notification** : l'ouvrir vers le centre de
   notifications (3 lignes dans `island_right.qml`), dans ce lot ou plus tard ?
