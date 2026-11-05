# Notifications : ouvrir le programme idoine au clic sur le titre

Proposition — état au 05/11, avant toute ligne de code. Décisions en fin de fiche.

## Objectif

Un clic sur le **titre** d'une notification lance ce qu'elle annonce :

| Notification | Clic attendu |
|---|---|
| Arch-Update « mises à jour disponibles » | un terminal s'ouvre et `arch-update` démarre |
| « Enregistrement vidéo arrêté » | le lecteur vidéo lit le `.mp4` produit |
| « Capture d'écran » | le visualiseur ouvre le `.png` |
| « Copie terminée » (Dolphin, script… ) | l'explorateur s'ouvre **sur le dossier d'arrivée** |
| autre application | son action par défaut, sinon l'application elle-même |

## Ce que le shell fait aujourd'hui (mesuré)

- `island_right.qml:221` — `NotificationServer` : chaque notification reçue devient une
  entrée de `notificationsList` (`id, appName, summary, body, time, raw`), plafonnée à
  30, **en mémoire seulement** (perdue au rechargement). `raw` est l'objet
  `QsNotification` (Retainable) : il est déjà conservé, donc les actions natives
  restent atteignables.
- Deux surfaces affichent ces entrées : le **centre** (`7.4`, cartes à ~1750) et le
  **toast** transitoire (`7.5`, ~1997). Aujourd'hui : clic sur une carte = rien ;
  clic sur un toast = ouvre le centre. `MouseArea` du toast : `acceptedButtons` par
  défaut, donc il avale déjà les clics.
- `Notification` expose exactement ce qu'il faut : `appName`, `appIcon`,
  `desktopEntry`, `hints` (objet JS), `actions` (`NotificationAction.text` /
  `.identifier` / `.invoke()`), `summary`, `body`, `urgency`.
- Le rice possède déjà de quoi résoudre une application : `core/app_index.json`
  (168 entrées `{name, exec, icon, comment, category, desktop}`) et la table d'alias
  `app_vars.json` (`Terminal: kitty`, `Files: thunar`, …).
- Le badge Arch-Update de la barre lance déjà `kitty arch-update` (`island_right.qml:553`) :
  la même commande servira de cible.
- `notify-send` 0.8.9 accepte `-h string:<nom>:<valeur>` : nos scripts peuvent donc
  **déclarer** la cible au lieu de la faire deviner.

## Le modèle : une cible figée à la réception

La cible est calculée **quand la notification arrive**, pas au clic, et rangée dans
l'entrée : `entry.target = { kind, label, cmd }`. Trois raisons : l'objet `raw` peut
être détruit ensuite, l'affordance visuelle (curseur, teinte) doit être connue tout
de suite, et l'historique doit rester cliquable après coup.

Résolution en cascade, **on s'arrête à la première règle qui répond** :

1. **Hint explicite** posé par nous : `x-amo-open` (`file:///…`) ou `x-amo-cmd`.
   Déterministe, insensible au texte. C'est la voie pour `screenshot.sh`.
2. **Table par application** (`core/notif_targets.json`) : `appName` ou `desktopEntry`
   → commande. Arch-Update y entre, Dolphin aussi.
3. **Action par défaut de la notification** (`actions` avec `identifier == "default"`) :
   `invoke()`. L'application sait mieux que nous quoi faire.
4. **Chemin ou URL repéré dans le texte** : premier `/…`, `~/…` ou `file://…` dont le
   fichier existe, sinon première `http(s)://`. Ouverture par type (voir table
   ci-dessous) ; une URL part au navigateur.
5. **Application émettrice** : `desktopEntry` → `exec` via `app_index.json`, sinon
   `appName` → entrée du même nom.

Si rien ne répond : pas de cible, **pas d'affordance** (le titre reste du texte).

## La table `core/notif_targets.json`

Fichier d'état (préservé au déploiement, comme `style_vars.json`), surveillé par
`FileView` : éditer le fichier suffit, pas besoin de redémarrer le shell.

```json
{
  "apps": {
    "Arch-Update": "kitty arch-update",
    "arch-update-tray.desktop": "kitty arch-update",
    "Dolphin": { "path": "/usr/bin/thunar %d" }
  },
  "types": {
    "video": "mpv %f",
    "image": "gwenview %f",
    "folder": "thunar %d",
    "text": "kitty -e nvim %f"
  },
  "terminal": "kitty",
  "browser": "firefox"
}
```

- Les clés `apps` matchent `appName` **ou** `desktopEntry` (les deux, sans distinction).
- `%f` = le fichier, `%d` = son dossier, `%u` = l'URL. Toujours substitué en **argument
  d'un argv**, jamais passé à `sh -c` : le texte d'une notification n'est pas une
  commande.
- `types` sert aux chemins détectés à la règle 4. Il est **nécessaire** ici :
  `xdg-open` est mal réglé sur cette machine (mesuré : `image/png` → **Chrome**,
  `inode/directory` → **Filelight**), il reste en dernier recours seulement.

## Affordance et interaction

- Le titre (`summary`) devient cliquable : `cursorShape: PointingHandCursor`,
  titre légèrement teinté d'accent au survol (120 ms), et au clic
  `Quickshell.execDetached(target.cmd)`.
- Le reste de la carte ne déclenche rien : on lit une notification, on ne veut pas
  lancer une vidéo en la survolant.
- Après clic : la carte est retirée de la liste et le centre se ferme ; le toast
  disparaît. (Aujourd'hui le clic sur un toast ouvre le centre — ce comportement
  reste sur le corps du toast, le titre prend la cible.)
- Le ✕ de la carte et « Tout effacer » ne changent pas.
- Rien à ajouter au thème : `Theme.accent`, `Theme.fontUi`, 120 ms, mêmes rayons.

## Découpage en lots

| Lot | Contenu | Preuve |
|---|---|---|
| **L1** socle | `notif_targets.json` + résolveur + `entry.target` à la réception + journal `~/.cache/quickshell/notifications.log` (une ligne par notification : app, résumé, cible choisie, règle gagnante) | sans clic : `notify-send` de test, on lit la cible dans le journal |
| **L2** interaction | titre cliquable dans le centre **et** le toast (curseur, teinte), exécution + retrait + fermeture | capture de la barre avec le toast, puis une notification de test cliquée par toi |
| **L3** hints | `screenshot.sh` envoie `-h string:x-amo-open:file://…` sur capture/vidéo ; vérifier que `hints` remonte bien la clé | notification de capture, clic → fichier ouvert |
| **L4** actions natives (option) | afficher les `actions` de la notification en petits boutons dans la carte | une notification d'essai avec `--action` |
| **L5** panneau (option) | onglet Notifications : éditer la table, voir les applications écartées | déployer, rouvrir le panneau |

## Risques et points à vérifier avant d'écrire

- **Nom des hints** : `Notification.hints` est un objet JS ; il faut confirmer la clé
  exacte rendue par Quickshell pour `-h string:x-amo-open:…` (test : une notification
  d'essai + `console.log(JSON.stringify(notification.hints))`).
- **Actions après coup** : `invoke()` sur une notification déjà retirée par
  l'application peut échouer ; la cascade prévoit la suite (table, chemin, app).
- **Historique en mémoire** : la liste et les cibles disparaissent au rechargement du
  shell. Suffisant pour l'usage visé ; persister un historique est un autre chantier.
- **Sécurité** : aucune commande issue du texte d'une notification. Seuls le hint,
  la table et `app_index.json` produisent un argv.
- **Notifications de nos scripts** : elles arrivent avec `appName = "notify-send"`
  (le binaire), donc la règle 2 ne les distinguera pas — d'où le hint du lot L3.

## Décisions (tranchées le 05 novembre)

| # | Question | Décision |
|---|---|---|
| 1 | Élément cliquable | **Le titre seul** — curseur main + teinte accent au survol ; le reste de la carte ne déclenche rien, le ✕ reste le ✕ |
| 2 | Résolution | **Cascade complète** : hint → table par application → action native → chemin/URL dans le texte → application émettrice |
| 3 | Terminal | **`ghostty`** (partout où une cible demande un terminal) |
| 4 | Après le clic | La notification **disparaît** de la liste et le centre **se ferme** |
| 5 | Notifications de copie | Elles viennent de **Thunar** → entrée dédiée dans la table (dossier d'arrivée → `thunar %d`) |

Ouverture des fichiers, décidé sans question parce que la mesure l'impose : **table
`types` explicite** (vidéo → `mpv`, image → `gwenview`, dossier → `thunar`,
texte → `kitty -e nvim`), `xdg-open` en dernier recours seulement.

Reste à mesurer au moment de coder, sans effet sur le plan :

- le `appName` et le `desktopEntry` exacts des notifications de Thunar (et de
  Arch-Update) — une copie de fichier et une notification de test suffisent ;
- la clé exacte rendue par `Notification.hints` pour `-h string:x-amo-open:…` ;
- la syntaxe de lancement de ghostty (`ghostty -e arch-update` a priori).

## Commandes de départ de la table

```json
"apps": {
  "Arch-Update": "ghostty -e arch-update",
  "Thunar": "thunar %d",
  "thunar.desktop": "thunar %d"
}
```

Le nom exact de Thunar (`Thunar`, `File Operations`, `thunar.desktop`) sera fixé
après la mesure ; les trois formes voisines peuvent cohabiter dans la table, une
clé qui ne matche jamais ne coûte rien.

