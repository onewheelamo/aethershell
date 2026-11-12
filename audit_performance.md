# Audit de performance & dette technique

Ce document constitue un audit architectural et d'optimisation du shell (`dev/`), totalisant 52 404 lignes de code (QML, widgets, scripts système et services Python). Il détaille les constats observés, les mécanismes sous-jacents, les propositions concrètes ainsi que les contraintes d'implémentation et de robustesse système.

---

## 1. Synthèse par niveau d'impact

| Priorité | Axe | Constat principal | Gain estimé | Complexité / Risque |
|---|---|---|---|---|
| **1 (Élevé)** | Élimination de l'avalanche de `FileView` | 22 `FileView` surveillent simultanément `bar_applets.json` (dont 18 dans `BarExtra`) et réinvoquent Python | Suppression de ~20 processus concurrents lors des modifications | Faible (centralisation dans `Theme.qml`) |
| **2 (Élevé)** | Réduction du polling subprocess Python | Multiples boucles de 1,5 s à 15 s invoquant `python3` ou `wpctl` (`system_service.py`, `systeme_applet.py`, `reseau_widget.py`) | Baisse nette de charge CPU et consommation batterie | Moyenne (respect du cycle de vie des processus) |
| **3 (Élevé)** | Mutualisation des états système | `system_service.py info` interrogé indépendamment par 4 applets ; cache de `systeme_applet.py` court-circuité | -60 % à -75 % d'invocations système redondantes | Moyenne (contrat de données partagé) |
| **4 (Moyen)** | Lazy-loading ciblé au démarrage | `spotlight.qml` (954 l.) et `first_run.qml` (968 l.) instanciés d'emblée dans `main.qml` | Démarrage accéléré, empreinte RAM allégée | Faible (chargement sur condition `active`) |
| **5 (Moyen)** | Optimisation des commandes Python ciblées | `cheatsheetProc` invoque `config_manager.py state` complet (2 145 l.) pour extraire uniquement `binds` | Ouverture instantanée de `Super+K`, évite la lecture globale | Faible (nouvelle sous-commande dédiée) |

---

## 2. Analyse détaillée & propositions

### 2.1 Surveillance redondante de `bar_applets.json` (Priorité 1)
- **Constat** :
  - `dev/main.qml:1253-1261` instancie 3 objets `BarExtra`.
  - Chaque `BarExtra` (`dev/bar_extra.qml:196-245`) déclare 3 `AppletRow` et 3 `AppletColumn`, soit 18 instances de `FileView` surveillant le même fichier `core/bar_applets.json`.
  - Ajoutées aux 3 îlots (`island_left.qml:36`, `island_center.qml:66`, `island_right.qml:647`) et à `VisualiseurAudio.qml:111`, le shell maintient **22 watchers `FileView` concurrents**.
  - Dans `AppletRow.qml:20-25` et `AppletColumn.qml:17-22`, chaque watcher déclenche `root.resoudre()` à la fois sur `onFileChanged` et `onTextChanged`, ce qui engendre des vagues de sous-processus `python3 core/bar_applets.py resoudre <ile>` même pour les barres inactives.
- **Solution recommandée** :
  - Centraliser l'écoute du fichier `bar_applets.json` dans un unique `FileView` au niveau de `Theme.qml` (selon le patron déjà en place pour `style_vars.json` et `widgets.json`).
  - Résoudre le positionnement des applets soit via un unique appel Python global qui renvoie l'état pour toutes les îles en une passe, soit directement en JavaScript dans QML.

---

### 2.2 Polling sous-processus & Gestion du cycle de vie (Priorité 2)
- **Constats** :
  - `dev/ReseauApplet.qml:96-104` : polling de `system_service.py info` toutes les 10 s.
  - `dev/LuminositeApplet.qml:178-186` : polling de `system_service.py info` toutes les 15 s.
  - `dev/GestionEnergieApplet.qml:68-84` et `dev/island_right.qml:542-555` : polling distinct du même script.
  - `dev/widgets/reseau.qml:52-64` : polling toutes les 2 s de `python3 core/reseau_widget.py`.
  - `dev/VolumeApplet.qml:65-86` : exécution de `wpctl get-volume @DEFAULT_AUDIO_SINK@` toutes les 1,5 s.
- **Règles impératives sur les processus résidents / démons** :
  - *Gestion du cycle de vie* : Comme documenté dans `dev/core/lancer_quickshell.sh:34-41`, les processus résidents orphelins (`pactl`, `inotifywait`, Python) peuvent bloquer le redémarrage du shell s'ils ne meurent pas avec leur parent.
  - Tout démon de flux doit impérativement être déclaré via un `Process` QML rattaché à l'arbre Quickshell (qui envoie `SIGTERM`/`SIGHUP` à la destruction du composant) plutôt qu'exécuté en tâche de fond détachée (`execDetached`).
  - Le script Python doit intercepter les signaux d'arrêt (`signal.SIGTERM`, `signal.SIGHUP`) pour fermer proprement ses descripteurs et sockets.
- **Solution recommandée** :
  - Pour le réseau et l'état système : mutualiser la lecture de `system_service.py info` dans une boucle cadencée globale plutôt que par applet individuel.
  - Pour le volume : voir section 2.4 sur l'évaluation de PipeWire.

---

### 2.3 Cache et duplication applet / widget (Priorité 3)
- **Constat** :
  - `dev/core/systeme_applet.py:166-174` intègre un mécanisme de cache disque (`CACHE_TTL`).
  - Cependant, `dev/widgets/systeme.qml:113`, `dev/SystemePopup.qml:190` et `dev/Applet.qml:167` passent le drapeau `--force` sur leurs timers réguliers (toutes les 3 s pour le widget).
  - Résultat : le cache est réécrit en permanence sur disque sans jamais être réutilisé pour servir les autres appelants.
- **Solution recommandée** :
  - Réserver l'argument `--force` aux déclenchements manuels explicites (clic utilisateur pour rafraîchir).
  - Définir une durée de validité du cache cohérente (~2 à 3 s) pour que l'applet de barre, le popup système et le widget de bureau exploitent la même mesure sans recalculs I/O concurrents.

---

### 2.4 Évaluation des bindings audio et PipeWire (Priorité 3)
- **Constat** :
  - `VolumeApplet.qml` invoque `wpctl get-volume` toutes les 1,5 s via un sous-processus.
- **Précautions relatives à Quickshell 0.3.2** :
  - Le binaire Quickshell 0.3.2 intègre les symboles `Quickshell.Services.Pipewire` (`libpipewire-0.3.so.0`).
  - *Néanmoins*, l'intégration directe de `Services.Pipewire` doit être qualifiée en amont : sur certaines révisions, la destruction/reconnexion de nœuds PipeWire ou le rechargement à chaud (`quickshell ipc`) peut entraîner des fuites de file descriptors ou des plantages du contexte PipeWire si les objets ne sont pas proprement désenregistrés.
- **Solution recommandée** :
  - Étape intermédiaire prudente : utiliser un sous-processus unique et surveillé qui écoute `pactl subscribe` ou `pw-mon` pour ne déclencher la lecture que sur événement de modification audio, évitant ainsi le polling aveugle à 1,5 s.
  - Étape cible : tester les bindings natifs `Quickshell.Services.Pipewire` sur un composant isolé avant déploiement général.

---

### 2.5 Horloge & synchronisation temporelle (Priorité 4)
- **Constat** :
  - `dev/HorlogeApplet.qml:19-25` utilise un `Timer` classique avec `interval: 1000` pour afficher l'heure au format `hh:mm`.
- **Analyse des risques** :
  - Remplacer directement ce timer par `interval: 60000` introduit un déphasage visible par rapport à la seconde 00 réelle, et amplifie le risque de désynchronisation après une mise en veille du système.
- **Solution recommandée** :
  - Remplacer le `Timer` par le composant natif `SystemClock` de Quickshell avec `precision: SystemClock.Minutes` (comme déjà implémenté avec succès dans `dev/widgets/horloge.qml:45-48` et `dev/widgets/date.qml:60-63`). Ce composant gère nativement le calage à la seconde près et la reprise après veille sans logique manuelle.

---

### 2.6 Cycle de vie des composants UI & intégrité de l'historique (Priorité 4)
- **Constats** :
  - `dev/main.qml:704-708` (`spotlightLoader`) charge `spotlight.qml` sans condition `active`. Cela charge 954 lignes de QML et exécute immédiatement `tablePrefixes` (`launcher_service.py --aide`, `dev/spotlight.qml:138-142`) au boot.
  - `dev/main.qml:889-891` (`assistantPremierLancement`) instancie `first_run.qml` (968 l.) de façon permanente, même quand le premier lancement est déjà achevé (`first_run_completed: true`).
  - `dev/main.qml:878-881` instancie `NotifHistory`.
- **Analyse du risque sur `NotifHistory`** :
  - `notif_history.qml` lit l'historique depuis `~/.cache/quickshell/notifications-history.jsonl` (alimenté de façon autonome par `core/notif_target.py` lors des notifications entrantes).
  - Bien que le tiroir ne reçoive pas directement les signaux D-Bus d'interception, **il ne doit pas être déchargé de manière agressive** afin de garantir l'accessibilité immédiate de l'historique au raccourci clavier (`Super + Shift + N` / IPC `showNotifHistory`) sans latence perceptible.
- **Solutions recommandées** :
  - Passer `spotlightLoader` en lazy-loading strict (`active: charge` armé lors de la première ouverture, sur le modèle de `configLoader`).
  - Remplacer l'instanciation directe de `FirstRun` par un `Loader` conditionné par `active: !Theme.firstRunCompleted`.
  - Maintenir l'instanciation de `NotifHistory` telle quelle pour garantir la réactivité de l'affichage et la consistance de la session.

---

### 2.7 Optimisation des points chauds Python (Priorité 5)
- **Constat** :
  - À l'ouverture de l'écran des raccourcis (`Super + K`), `dev/main.qml:802-824` appelle `python3 core/config_manager.py state`.
  - Cette commande exécute `get_full_config_state()` (`dev/core/config_manager.py:1923-2004`) qui interroge les profils d'écrans, les secrets chiffrés, les fournisseurs LLM, les autostarts et les widgets, alors que seule la liste des raccourcis (`d.binds`) est consommée.
- **Solution recommandée** :
  - Ajouter une sous-commande dédiée `config_manager.py binds` qui renvoie exclusivement `get_binds_list()`, divisant drastiquement le temps d'exécution et évitant des I/O inutiles.

---

## 3. Plan d'intervention ordonnancé

### Lot 1 — Gains rapides & sans risque de régression
1. **Raccourcis clavier** : implémenter `config_manager.py binds` pour l'appel de `cheatsheetProc` dans `main.qml`.
2. **Horloge de barre** : migrer `dev/HorlogeApplet.qml` vers `SystemClock { precision: SystemClock.Minutes }`.
3. **Cache système** : supprimer le commutateur `--force` sur les timers de `dev/widgets/systeme.qml` et `dev/Applet.qml`.
4. **Timers médias** : fusionner les deux minuteurs de 1 000 ms dans `dev/MediaPanneau.qml`.
5. **Démarrage conditionnel** : passer `spotlightLoader` et `assistantPremierLancement` sous chargement différé via `Loader.active`.

### Lot 2 — Refactorisation structurelle & processus
1. **Centralisation de `bar_applets.json`** : basculer la surveillance dans `Theme.qml` pour éliminer les 22 `FileView` et la cascade d'exécutions de `bar_applets.py`.
2. **Mutualisation système** : regrouper les appels d'état système au sein d'une cadence unique, en s'assurant que tout sous-processus reste sous contrôle du cycle de vie Quickshell.
3. **Surveillance audio** : évaluer et qualifier le comportement de `Quickshell.Services.Pipewire` sous Quickshell 0.3.2 en banc d'essai avant remplacement éventuel du polling `wpctl`.
