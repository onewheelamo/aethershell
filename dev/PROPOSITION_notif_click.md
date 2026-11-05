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

Résolution en cascade, **on s'arrête à la première règle qui répond**. Les
programmes ne sont **jamais écrits en dur** : ils viennent du tiroir « Programmes par
défaut des raccourcis » du panneau (`core/app_vars.json`, lu par `Theme.program()`).

1. **Hint explicite** posé par nous : `x-amo-open` (`file:///…`) ou `x-amo-cmd`.
   Déterministe, insensible au texte. C'est la voie pour `screenshot.sh`.
2. **Table par application** (`core/notif_targets.json`) : `appName` ou `desktopEntry`
   → soit une commande à lancer, soit « lancer ceci dans un terminal ». Arch-Update
   y entre.
3. **Action par défaut de la notification** (`actions` avec `identifier == "default"`) :
   `invoke()`. L'application sait mieux que nous quoi faire.
4. **Chemin ou URL repéré dans le texte** : premier `/…`, `~/…` ou `file://…` dont le
   fichier existe, sinon première `http(s)://`. Le fichier est classé par nature
   (vidéo, image, dossier, texte) et cette nature désigne un **alias** du tiroir ;
   une URL part au navigateur.
5. **Application émettrice** : `desktopEntry` → `exec` via `app_index.json`, sinon
   `appName` → entrée du même nom.

Si rien ne répond : pas de cible, **pas d'affordance** (le titre reste du texte).
Si l'alias demandé manque au tiroir, repli sur `xdg-open` et **une ligne dans le
journal** — c'est ainsi qu'on verra qu'il manque un alias, sans échec muet.

## État — L1 livré (05/11, 10:00)

Le socle tourne : `core/notif_target.py` (résolveur, un processus pour la session,
une requête JSON par ligne) est lancé par `island_right.qml`, chaque notification
reçue reçoit sa cible **au moment de la réception** (`entry.target`) et une ligne de
journal. Rien ne s'ouvre encore : le clic est le lot L2.

Journal : `~/.cache/quickshell/notifications.log`, une ligne par notification —
`app= desktop= regle= cible= resume= actions=N [alias_manquant=] [hints=]`.

Mesuré dans le shell vivant (notifications réelles via D-Bus) :

| Notification d'essai | Règle | Cible retenue |
|---|---|---|
| `-a Arch-Update` « Mises à jour disponibles » | table | `ghostty -e arch-update` |
| hint `x-amo-open:file://…/Capture….png` | hint | `gwenview <png>` |
| hint `x-amo-open:file://…/t.mp4` | hint | `mpv <mp4>` |
| `-a Thunar` « 2 fichiers copiés vers /home/utilisateur/Images/Screenshots » | chemin → `folder` | `thunar <dossier>` |
| `-a com.example` « voir https://… » | url | `firefox <url>` |
| actions explicites (`gdbus`) | action native | `Ouvrir` (identifiant `default`) |
| `-a Firefox` sans action | app émettrice | `/usr/lib/firefox/firefox` |
| `-a Inconnu` sans rien | aucune | — (pas d'affordance) |

Deux constats de mesure :

- **Le serveur n'annonçait pas la capacité `actions`.** `NotificationServer` a
  `actionsSupported` à `false` par défaut ; notify-send répondait donc « Actions
  are not supported by this notifications server » et n'envoyait **aucune**
  action (`actions=0`) — la règle 3 était morte-née côté clients, alors que le
  serveur savait les recevoir (vérifié en D-Bus pur, `gdbus`, `actions=2`).
  Corrigé : `actionsSupported: true` et `persistenceSupported: true` sur le
  serveur. `GetCapabilities` répond maintenant `['persistence','body','actions']`
  et la même notification notify-send arrive avec `actions=1` →
  `regle=action cible=Ouvrir`. Les boutons d'action ne sont pas encore dessinés
  (lot L4) : seule l'action `default` sert, via le clic sur le titre.
- La clé du hint arrive bien telle quelle : `x-amo-open` (la cascade teste un nom
  qui finit par `x-amo-open`, insensible à la casse, pour tolérer un préfixe).

Le tiroir a été aligné au passage : `Terminal` = `ghostty` (déjà changé côté
vivant), plus `Video` = `mpv` et `Images` = `gwenview`, dans `app_vars.json` **et**
`programs.lua`. `notif_targets.json` est entré dans `PRESERVE_CORE` (état, pas
code) : une modification du panneau ou du fichier survit au déploiement.

## La table `core/notif_targets.json`

Fichier d'état (préservé au déploiement, comme `style_vars.json`), surveillé par
`FileView` : éditer le fichier suffit, pas besoin de redémarrer le shell. Elle ne
nomme **aucun binaire** : elle nomme des alias du tiroir.

```json
{
  "apps": {
    "Arch-Update":          { "run": "arch-update", "terminal": true },
    "arch-update-tray.desktop": { "run": "arch-update", "terminal": true }
  },
  "types": {
    "video":  "Video",
    "image":  "Images",
    "folder": "Files",
    "text":   "Editor"
  },
  "url": "Browser"
}
```

- Les clés `apps` matchent `appName` **ou** `desktopEntry` (les deux, sans distinction).
- `{"run": …, "terminal": true}` : la commande est lancée **dans le terminal du
  tiroir** (alias `Terminal`). Le résolveur connaît deux formes de terminal — `kitty
  <cmd>` (le binaire prend la commande directement) et `<term> -e <cmd>` pour les
  autres (ghostty, foot, alacritty, wezterm) — une seule ligne de connaissance, dans
  le résolveur, pas dans la table.
- `types` associe une **nature** à un **alias**, jamais à un binaire. Aujourd'hui le
  tiroir n'a ni `Video` ni `Images` : ils s'ajoutent (voir plus bas).
- Le chemin détecté est passé en **argument** : `sh -c '<commande de l’alias> "$1"' _
  <chemin>`. L'alias est la config de l'utilisateur, le chemin vient d'une
  notification — il n'est jamais concaténé dans la chaîne de commande.
- Repli final : `xdg-open`, qui est mal réglé ici (mesuré : `image/png` → **Chrome**,
  `inode/directory` → **Filelight**). D'où la résolution par alias plutôt que par
  type MIME.

## Le tiroir « Programmes par défaut » est la source de vérité

Trois changements dans `core/app_vars.json` (donc visibles et modifiables dans le
panneau, et repris par `programs.lua` pour les binds Hyprland) :

| Alias | Aujourd'hui | Après | Effet de bord assumé |
|---|---|---|---|
| `Terminal` | `kitty` | **`ghostty`** | `SUPER + Retour` ouvre ghostty |
| `Video` | — | **`mpv`** | nouvel alias, utilisé par les notifications de capture vidéo |
| `Images` | — | **`gwenview`** | nouvel alias, utilisé par les notifications de capture d'écran |

Les alias restent **sans accent** (`Video`, `Images`) : `config_manager.py` en dérive
un identifiant Lua pour `programs.lua`. `Files` (`thunar`), `Editor` et `Browser`
sont déjà là et servent tels quels.

Conséquence de méthode : si tu changes un jour un de ces programmes dans le panneau,
les notifications suivent sans redéploiement. Et un alias absent ne casse rien — il
retombe sur `xdg-open` en le disant dans le journal.


## Affordance et interaction

Précisé le 05/11 : **le centre et le toast n'ont pas le même fond**, mais la même
règle pour le titre.

| Zone | Centre (centre = popup) | Toast (spontané) |
|---|---|---|
| **Titre** (`summary`) | ouvre la cible, retire la notification, ferme le popup | ouvre la cible **et** retire la notification du centre ; le toast disparaît |
| Reste de la carte | rien (on lit) | ouvre le centre de notifications |
| ✕ / cloche barrée | retire la carte | écarte l'application des toasts (inchangé) |

- Titre cliquable : `cursorShape: PointingHandCursor`, teinte accent au survol
  (120 ms), puis `Quickshell.execDetached(target.cmd)`.
- Pas de cible résolue → le titre redevient du texte simple, sans curseur ni teinte :
  un clic qui ne ferait rien est pire qu'un clic absent.
- **Retirer ≠ retirer de la liste.** Une entrée retirée doit aussi être
  `dismiss()`-ée côté serveur (`raw.tracked = false`), sinon `keepOnReload` la
  ressuscite au prochain rechargement du shell. Défaut existant à corriger dans le
  même lot : le ✕ de la carte et « Tout effacer » ne font aujourd'hui que vider la
  liste, la notification reste suivie par le serveur.
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
| 3 | Programmes | **Le tiroir « Programmes par défaut » du panneau** (`app_vars.json`), jamais un binaire en dur dans la table |
| 4 | Terminal | L'alias `Terminal` passe de `kitty` à **`ghostty`** — donc `SUPER + Retour` aussi |
| 5 | Vidéo / images | Deux alias ajoutés au tiroir : **`Video` → `mpv`**, **`Images` → `gwenview`** |
| 6 | Après le clic | La notification **disparaît** de la liste et le centre **se ferme** |
| 7 | Notifications de copie | Elles viennent de **Thunar** ; le dossier d'arrivée repéré dans le texte part à l'alias `Files` (aucune entrée d'application nécessaire si le chemin est dans le texte) |

Reste à mesurer au moment de coder, sans effet sur le plan :

- le `appName` / `desktopEntry` exacts des notifications de Thunar et d'Arch-Update
  (une copie de fichier et une notification de test suffisent) ;
- la clé exacte rendue par `Notification.hints` pour `-h string:x-amo-open:…` ;
- la syntaxe de lancement de ghostty avec une commande (`ghostty -e arch-update`
  a priori) et le fait qu'elle rende bien la main (pas d'attente du shell).


## Ce que ça donne concrètement

| Notification | Règle | Commande lancée |
|---|---|---|
| Arch-Update | table (`terminal: true`) | `ghostty -e arch-update` |
| « Enregistrement vidéo arrêté » (hint) | hint | `mpv <fichier>` (alias `Video`) |
| « Capture d'écran » (hint) | hint | `gwenview <fichier>` (alias `Images`) |
| « Copie terminée » de Thunar | chemin dans le texte → `folder` | `thunar <dossier>` (alias `Files`) |
| Firefox « téléchargement terminé » | action native (`default`) | l'action de Firefox |
| n'importe quelle autre | application émettrice | son `Exec` de `app_index.json` |

Une commande d'alias rendue par `Theme.program()` est lancée telle quelle ; le chemin,
lui, arrive en `$1` (`sh -c '<alias> "$1"' _ <chemin>`). Rien du texte d'une
notification n'entre dans une chaîne de commande.


