# Proposition — widgets de bureau sur les workspaces

État : proposition, rien n'est appliqué. Destinée à relecture externe avant le
premier lot.

## 1. Objet

Poser des widgets **en fond de workspace**, derrière les fenêtres, sur le même
principe que la capsule du lanceur — qui est déjà, techniquement, le premier
d'entre eux. Puis les piloter depuis un nouvel onglet « Widgets » du panneau.

## 2. Ce qui existe déjà, et qui sert de patron

La capsule de repos du lanceur est une `PanelWindow` :

- namespace `shell-spotlight-rest`, couche `Bottom`, 720 × 62, posée par
  `margins.left` + `margins.bottom` (relevé dans `hyprctl layers` :
  `xywh 600 974 720 62` sur 1920 × 1080) ;
- `WlrKeyboardFocus.None`, `ExclusionMode.Ignore`, `color: transparent` ;
- opaque à 0,2 (`spotlightRestBg`), donc sous `ignore_alpha` : pas de flou ;
- visible sur tous les workspaces, cliquable quand rien ne la couvre
  (mesuré : 3 clics sur 3 sur un workspace vide), effacée sous une fenêtre.

Un widget de bureau reprend exactement ces propriétés, avec trois différences :
il est **rattaché à un workspace**, sa **taille suit son contenu**, et sa
position est libre.

## 3. Modèle proposé

### 3.1 Registre d'état

`dev/core/widgets.json`, **fichier d'état préservé** au déploiement (même
politique que `style_vars.json`) :

```json
{
  "widgets": [
    { "id": "clock-1", "type": "horloge", "workspace": 1,
      "x": 120, "y": 180, "scale": 1.0, "enabled": true,
      "options": { "seconds": false, "date": true } },
    { "id": "weather-1", "type": "meteo", "workspace": 3,
      "x": 1480, "y": 220, "scale": 1.0, "enabled": true,
      "options": { "city": "Paris" } }
  ]
}
```

- `workspace` : 1 à 5, ou `0` = tous les workspaces.
- `x`, `y` : coin haut-gauche en pixels de l'écran (marges mesurées, cf. §2).
- `enabled` : le widget reste décrit mais n'est pas rendu.
- `options` : propre au type, sans schéma commun pour l'instant.

Défaut : `{"widgets": []}` — **aucun changement visuel** tant qu'on n'ajoute
rien. La capsule du lanceur reste où elle est (voir §5, lot A).

### 3.2 Rendu

Un `Repeater` dans `main.qml`, un `PanelWindow` par entrée :

```qml
Variants {
    model: Theme.widgets            // lu depuis widgets.json par Theme.qml
    PanelWindow {
        required property var modelData
        screen: topBarWindow.screen
        visible: modelData.enabled
                 && (modelData.workspace === 0
                     || (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.workspace))
        anchors { top: true; left: true }
        margins.top: modelData.y
        margins.left: modelData.x
        implicitWidth: loader.implicitWidth
        implicitHeight: loader.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.namespace: "shell-widget"
        Loader { id: loader; source: "widgets/" + modelData.type + ".qml" }
    }
}
```

Chaque widget est un composant `dev/widgets/<type>.qml` (fond discret à 0,2,
contenu à pleine opacité, aucun `font.pixelSize` littéral, glyphes via `Icon`).

### 3.3 Backend

`core/config_manager.py` : `widgets_list()`, `widget_add(type, workspace, x, y)`,
`widget_set(id, key, value)`, `widget_remove(id)`, et exposition des widgets dans
`get_full_config_state()` (sinon le panneau ne les verra jamais — pitfall 75).
Écriture atomique, pas de régénération de style : `widgets.json` n'alimente aucun
fichier dérivé.

### 3.4 Onglet « Widgets »

Deuxième position du rail. Une section « Sur le bureau » :

- une ligne par widget : glyphe du type + nom, workspace (`Stepper` ou
  pastilles 1…5 / Tous), x/y (`Stepper`), interrupteur d'activation, croix de
  suppression ;
- un bouton « Ajouter un widget » avec choix du type, qui crée l'entrée à une
  position par défaut (centre-bas, comme la capsule) ;
- une ligne pour le **Lanceur**, marquée « intégré » : pas de x/y, mais les six
  positions prédéfinies du §3.5.

Recherche : entrées d'index pour l'onglet et deux libellés (`widgets`,
`bureau`), sinon la recherche ne le trouve pas (pitfall 65).

### 3.5 La capsule du lanceur : positions prédéfinies, pas de position libre

Décision retenue : la capsule est un **cas à part**. Elle ne se place pas au
pixel, elle choisit dans une grille de six positions :

| clé          | zone               | marges (1920 × 1080, capsule 720 × 62) |
|--------------|--------------------|----------------------------------------|
| `haut-centre`  | bord haut, centre  | left 600, bottom —,  top 12            |
| `bas-centre`   | bord bas, centre   | left 600, bottom 44 (position actuelle)|
| `haut-gauche`  | tiers gauche, haut | left 12,  top 12                       |
| `haut-droit`   | tiers droit, haut  | left 1884 − w, top 12                  |
| `bas-gauche`   | tiers gauche, bas  | left 12,  bottom 44                    |
| `bas-droit`    | tiers droit, bas   | left 1884 − w, bottom 44               |

Les valeurs sont **calculées** (`Math.round`), pas écrites en dur : une seule
constante de largeur (`w`) et les marges du thème (`Theme.gutter`), pour que le
passage à un autre écran ou à une autre hauteur de barre ne demande rien.

État : `launcher_position` dans `style_vars.json` (déjà préservé au déploiement,
déjà lu par `Theme.qml`) — pas besoin d'un second fichier pour un seul réglage,
et ça évite d'introduire `widgets.json` pour la capsule alors qu'elle ne suit pas
le modèle des widgets.

Dans l'onglet : ligne « Lanceur », marquée **intégré**, avec les six positions en
pastilles (même forme que les groupes de choix du panneau : centrées sous leur
libellé, sur une ligne) et pas de champs x/y.

Un point de géométrie à trancher : une capsule de 720 px ne tient pas dans un
tiers (640 px). Deux comportements possibles, à choisir :

- **A. elle rétrécit** dans les positions en tiers (`w = min(720, W/3 − 2·gutter)`
  = 616 ici), la même largeur servant aux quatre positions de tiers ;
- **B. elle garde 720 px** et déborde du tiers vers le centre.

A est cohérent avec l'idée de « tiers » ; B garde une capsule identique partout.

### 3.6 Les quatre premiers types

| type      | contenu                                   | options                     |
|-----------|-------------------------------------------|-----------------------------|
| `horloge` | heure `HH:MM`                             | `secondes` (bool, défaut non)|
| `date`    | jour de la semaine + date longue           | —                           |
| `meteo`   | glyphe + température + ville               | `ville` (sinon celle du réglage global) |
| `combo`   | les trois côte à côte, une seule entrée    | `secondes` (héritée)        |

Ils ne sont pas quatre composants autonomes : trois **feuilles** partagées
(`widgets/Horloge.qml`, `widgets/Date.qml`, `widgets/Meteo.qml`) plus
`widgets/Combo.qml` qui les dispose en une ligne — heure et date empilées,
filet à 9 % du texte, puis météo. Ainsi l'option « secondes » n'existe qu'une
fois, et un futur widget « agenda » pourra réutiliser les mêmes blocs.

Maquette arrêtée (couleurs de la palette active, wallpaper réel, 1920 × 1080) :
`dev/mockups/widgets.html`, captures `widgets_nu.png` / `widgets_carte.png`.
Variante retenue à confirmer : **texte seul**, une ombre très douce pour la
lisibilité (la variante « carte » alourdit un fond déjà chargé).

**Dépendance nouvelle : la météo.** Contrairement à l'horloge et à la date
(`SystemClock`), il n'existe aucune source de météo dans le dépôt — l'îlot
central n'en a pas, `secrets.json` ne contient que Nextcloud. Il faut donc
`core/weather_service.py` : appel unique à open-meteo (aucune clé), cache dans
`~/.cache` rafraîchi toutes les 15 min, sortie JSON lue par un `Process` à
commande **fixe** (pitfall 89). Réglage `weather_place` / `weather_lat` /
`weather_lon` dans `style_vars.json`. Glyphes à ajouter à `Icon.qml` pour la
pluie, la neige, le brouillard et l'orage (vérifiés dans `glyphnames.json`).


## 4. Contraintes et risques connus

1. **Zone morte des clics.** Une surface layer consomme les clics sur toute son
   étendue, même transparente (pitfall 81). La fenêtre de chaque widget doit donc
   être exactement de la taille de son contenu — jamais une fenêtre plein écran
   avec un widget dessiné dedans, sinon le bureau devient incliquable.
2. **Couche `Bottom` et fenêtres.** Un widget en `Bottom` reçoit les clics quand
   il est découvert et pas quand une fenêtre le couvre. C'est le comportement
   voulu, mais il interdit un widget « toujours au premier plan » : il faudra un
   choix explicite par widget si ce besoin apparaît.
3. **Flou.** À 0,2 d'opacité, `ignore_alpha 0.30` ne floute pas (comme la
   capsule). Un widget plus opaque que 0,30 exigerait son namespace dans
   `SHELL_BLUR_NAMESPACES` **et** dans le bloc `-- BEGIN shell-blur`.
4. **Changement de workspace.** La visibilité passe par
   `Hyprland.focusedWorkspace.id` ; vérifier qu'un widget n'apparaît pas une
   frame sur le workspace voisin au passage (sinon masquer/mapper avec un
   `Timer` court).
5. **Trois enregistrements par composant** (pitfall connu) : le fichier sous
   `dev/`, l'entrée dans `qmldir` s'il est instancié par nom, et la ligne `cp`
   dans `deploy.sh`. Sans la troisième, le panneau s'ouvre vide sans erreur QML.
6. **`widgets.json` doit entrer dans `PRESERVE_HYPR`** ? Non : il vit dans
   `~/.config/quickshell/core/`, donc la politique « état » des fichiers du shell
   s'applique — à déclarer explicitement dans `deploy.sh` pour ne pas être écrasé
   au premier déploiement.

## 5. Découpage proposé

- **Lot A — modèle et rendu (S/M).** `widgets.json`, lecture par `Theme.qml`,
  `Repeater` de `PanelWindow`, un seul type : `horloge` (heure + date, options
  secondes). Vérification : `hyprctl layers` montre une couche `shell-widget` par
  widget, à la géométrie demandée, sur le bon workspace, et le bureau reste
  cliquable partout ailleurs.
- **Lot A′ — positions de la capsule (S).** `launcher_position` dans
  `style_vars.json`, six clés, marges calculées depuis `Theme.gutter` et la
  largeur ; la capsule actuelle devient `bas-centre` par défaut, donc aucun
  changement visible au déploiement. Vérification : pour chaque clé, l'`xywh`
  relevé dans `hyprctl layers` doit correspondre à la table du §3.5, et le clic
  sur la capsule doit toujours ouvrir la pilule.
- **Lot B — onglet Widgets (M).** Section, liste, ajout, activation, x/y,
  suppression, entrée d'index, icône `widgets` ajoutée à `Icon.qml` ; plus la
  ligne « Lanceur » avec ses six positions en pastilles.
- **Lot C — deuxième type (S/M).** `meteo`, qui réutilise les services déjà
  appelés par l'îlot central (aucun nouveau démon).
- **Lot D — mise en place à la souris (M/L).** Glisser-déposer depuis le panneau ;
  demande un mode « placement » et une surface de capture, donc à part.

## 6. Décisions qui appartiennent à l'utilisateur

1. ~~Quels types au départ ?~~ **Tranché : météo, horloge (option secondes), date,
   et un combo des trois (§3.6).**
2. Un widget se rattache à un workspace précis, ou se pose-t-il par défaut sur
   « tous » ? (Les deux sont dans le modèle ; c'est la valeur par défaut qui
   change.)
3. ~~La capsule devient-elle un widget du registre ?~~ **Tranché : cas à part,
   positions prédéfinies (§3.5).** Reste à choisir : dans les positions en tiers,
   la capsule **rétrécit** (A) ou **garde 720 px** (B) ?
4. Position réglée aux flèches dans le panneau, ou directement à la souris
   (lot D tout de suite) ?
5. Rendu : **texte seul** (proposé, cf. maquette) ou carte translucide ?
6. Météo : ville fixe dans le panneau (donc coordonnées réglées une fois), ou
   détection par IP au premier lancement puis mémorisée ?

## 7. Vérification prévue à chaque lot

- `hyprctl layers` : une couche `shell-widget` par widget actif, `xywh` attendu,
  niveau 1 (bottom) ; aucune couche sur les widgets désactivés.
- Changement de workspace : le widget du workspace 1 disparaît en allant sur 2.
- Clic sur le bureau hors du widget : rien ne se ferme, rien ne s'ouvre.
- Clic sur le widget : réaction attendue (aucune pour une horloge).
- `hyprctl configerrors` vide, log Quickshell sans `WARN scene`.
- Le panneau (onglet Widgets) relu après ajout : la valeur écrite dans
  `widgets.json` est celle affichée au refresh suivant.
