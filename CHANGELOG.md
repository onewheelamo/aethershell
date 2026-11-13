# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), versionnage
sémantique. Tant que le format des fichiers de configuration (`style_vars.json`,
`bar_applets.json`, `widgets.json`) n'est pas figé, les versions restent en `0.x` : une
montée de mineure peut demander une adaptation des réglages.

## [0.3.6] — 2026-11-13

### Corrigé

- **Panneau étendu de l'Îlot dynamique** ([`dev/IslandPanel.qml`](dev/IslandPanel.qml), [`dev/IslandTabAlertes.qml`](dev/IslandTabAlertes.qml)) : ajout de l'accolade fermante manquante sur `ColumnLayout` dans `IslandPanel.qml` (qui empêchait le chargement du panneau étendu et laissait une surface vide) et remplacement de `Theme.iconXs` par `12` sur les icônes de `IslandTabAlertes.qml`.

## [0.3.5] — 2026-11-13

### Ajouté

- **Panneaux latéraux de l'Îlot dynamique** ([`dev/IslandSidePanel.qml`](dev/IslandSidePanel.qml), [`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/IslandPanel.qml`](dev/IslandPanel.qml), [`dev/IslandTabAlertes.qml`](dev/IslandTabAlertes.qml), [`dev/core/todo_applet.py`](dev/core/todo_applet.py)) :
  - Bouton `+` sur la ligne **« TÂCHES (…) & AGENDA »** ouvrant un panneau latéral droit (`340 px`) pour créer une nouvelle tâche (`todo_applet.py ajouter <titre> [detail] [fichier]`, choix du fichier cible et rafraîchissement instantané).
  - Bouton **« Agenda → »** ouvrant le calendrier mensuel et les événements Nextcloud dans ce même panneau latéral au lieu d'un popup séparé.
  - Animation synchronisée sur `Theme.panelAnimDuration` (`Easing.OutCubic`) maintenant l'ensemble centré horizontalement.
- **Taquet de surveillance Hermès** ([`dev/IslandTabAlertes.qml`](dev/IslandTabAlertes.qml)) : bascule directe de la surveillance des tâches par Hermès (`todo_applet.py surveillance <on|off>`) depuis l'en-tête *Tâches & Agenda*.

## [0.3.4] — 2026-11-13

### Ajouté

- **Batterie dans l'Îlot dynamique** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml)) : affichage de l'applet batterie/luminosité dans l'îlot étendu au survol (avec centrage de l'horloge et alignement du groupe droit) et carte dédiée de gestion de la charge batterie (`Santé 80 %` / `Charge 100 %` via `core/system_service.py`) sur laptop dans l'onglet *Système & Réseau* entre les jauges matérielles et le réseau.

### Corrigé

- **Icônes des alias dans Spotlight** ([`dev/spotlight.qml`](dev/spotlight.qml)) : résolution complète des icônes de programmes depuis `app_index.json` (gestion des chemins complets, `env`, `flatpak run`, variantes de binaire comme `code` → `code-oss` / `zen-browser` → `zen-bin`, lanceur principal sans arguments) et réapplication dynamique sur les entrées d'alias dans l'historique des lancements récents après ajout ou modification dans le panneau de configuration.
- **Démon de métriques sans écritures disque & caches** ([`dev/core/metriques_daemon.py`](dev/core/metriques_daemon.py), [`dev/core/systeme_applet.py`](dev/core/systeme_applet.py), [`dev/core/reseau_widget.py`](dev/core/reseau_widget.py), [`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml)) : conservation des deltas CPU/réseau en mémoire dans le démon (`persister=False`), déplacement du cache CPU vers `~/.cache/quickshell/systeme_cpu_cache.json` et réutilisation de `Theme.systemeData` dans l'onglet *Système & Réseau* lorsque le démon est actif.
- **Ergonomie & conventions QML** ([`dev/IslandTabApparence.qml`](dev/IslandTabApparence.qml), [`dev/IslandTabAlertes.qml`](dev/IslandTabAlertes.qml), [`dev/IslandTabMedia.qml`](dev/IslandTabMedia.qml), [`dev/Icon.qml`](dev/Icon.qml), [`dev/Theme.qml`](dev/Theme.qml)) : hauteur explicite du `Flow` des thèmes, scan `themes_scan.py --sync` différé à l'ouverture de l'onglet Apparence, sonde `awww query` conditionnée à `depthWallpaper`, et remplacement des derniers emojis par des glyphes monochromes `Icon.qml`.

### Supprimé

- **Nettoyage du code mort** ([`dev/SurfaceFloutee.qml`](dev/SurfaceFloutee.qml), [`dev/Theme.qml`](dev/Theme.qml), [`dev/main.qml`](dev/main.qml), [`dev/CalqueProfondeur.qml`](dev/CalqueProfondeur.qml), [`dev/core/config_manager.py`](dev/core/config_manager.py), [`dev/core/parallaxe_layers.py`](dev/core/parallaxe_layers.py), [`dev/widgets/systeme.qml`](dev/widgets/systeme.qml), [`dev/widgets/reseau.qml`](dev/widgets/reseau.qml)) : suppression de `FlouFond.qml`, des résidus `shell_flou_*` (y compris la génération de `fond-ecran.png`), du mode expérimental abandonné `widgets_multieffect` et du `MouseArea` inactif sur le widget Système.

## [0.3.3] — 2026-11-13

### Ajouté

- **Raccourci Îlot dynamique & alias Spotlight** ([`dev/hypr_modular/binds.lua`](dev/hypr_modular/binds.lua), [`dev/spotlight.qml`](dev/spotlight.qml)) : ajout du raccourci `SUPER + H` pour déployer/fermer le panneau étendu de l'Îlot dynamique (`toggleIslandPanel`) et ajout de l'alias intégré *Config — Panneau de réglages* (avec icône `cog` via `Icon.qml`) dans Spotlight sur les mots-clés `config`, `réglages`, `paramètres` ou `aethershell`.

### Modifié

- **Raccourci du panneau de configuration** ([`dev/hypr_modular/binds.lua`](dev/hypr_modular/binds.lua), [`dev/IslandTabApparence.qml`](dev/IslandTabApparence.qml), [`dev/OngletBarres.qml`](dev/OngletBarres.qml), [`dev/first_run.qml`](dev/first_run.qml), [`dev/deploy.sh`](dev/deploy.sh), [`README.md`](README.md), [`docs/README.md`](docs/README.md)) : passage du raccourci d'ouverture du panneau de configuration de `SUPER + H` à `SUPER + SHIFT + H`.

## [0.3.2] — 2026-11-13

### Ajouté

- **Bluetooth & thèmes dynamiques dans l'Îlot dynamique** ([`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml), [`dev/IslandTabApparence.qml`](dev/IslandTabApparence.qml)) : activation/désactivation Bluetooth et grille des périphériques appairés dans *Système & Réseau* (`core/bluetooth_service.py`) ; synchronisation des schémas de couleurs (`~/.local/share/color-schemes` et `/usr/share/color-schemes` via `themes_scan.py --sync`) avec liste dynamique à 6 thèmes + tiroir dépliable et mode `Matugen` (`dynamic`) dans *Apparence*.
- **Surface unifiée & démon de métriques** ([`dev/SurfaceFloutee.qml`](dev/SurfaceFloutee.qml), [`dev/core/metriques_daemon.py`](dev/core/metriques_daemon.py)) : composant unique de rendu de surface pour l'ensemble du shell (panneau de config, îlot, popups, barre, tiroir de notifications, barre de capture, sélecteurs) et démon persistant `metriques_daemon.py` (`SplitParser` dans `Theme.qml`) supprimant les lancements Python en boucle toutes les 2–3 s sur les widgets système/réseau.

### Modifié

- **Rendu verre & passage en flux d'événements** ([`dev/SurfaceFloutee.qml`](dev/SurfaceFloutee.qml), [`dev/OngletApparence.qml`](dev/OngletApparence.qml), [`dev/VolumeApplet.qml`](dev/VolumeApplet.qml), [`dev/widgets/presse_papiers.qml`](dev/widgets/presse_papiers.qml), [`dev/widgets/usb.qml`](dev/widgets/usb.qml), [`dev/MinimiseApplet.qml`](dev/MinimiseApplet.qml), [`dev/core/launcher_service.py`](dev/core/launcher_service.py)) : suppression du flou interne (`FlouFond`) pour laisser uniquement le flou compositeur Hyprland (`shell-blur`, montrant les fenêtres derrière les surfaces), remplacement des minuteurs de sondage par `pactl subscribe`, `FileView` sur `cliphist/db`, `udevadm monitor` et `Hyprland.rawEvent`, déduplication des sondes météo dans `Theme.qml`, et cache disque 300 s (`fichiers_index.txt`) dans `launcher_service.py`.

### Corrigé

- **Fiabilité & ergonomie** ([`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml), [`dev/IslandTabApparence.qml`](dev/IslandTabApparence.qml), [`dev/core/bar_applets.py`](dev/core/bar_applets.py), [`dev/deploy.sh`](dev/deploy.sh), [`dev/NotifsApplet.qml`](dev/NotifsApplet.qml)) : lecture du contrat `compact.barres` / `detail` dans *Système & Réseau* (CPU/RAM/GPU/disques) avec sélection par défaut de `/home`, persistance des options d'applets même désactivés (`options_inactives`, débloquant le choix des montages disques), correction de l'appel `theme_manager.py` et surbrillance exclusive du thème actif, `watchChanges: root.ouvert` sur `NotifsApplet.qml`, garde de chemin `$SNAPSHOT_DIR/` sur `rotate_snapshots()` dans `deploy.sh`, et retrait des propriétés mortes / replis en dur (`Theme.qml`, `FlouFond.qml`).

## [0.3.1] — 2026-11-13

### Ajouté

- **Îlot dynamique façon tiroir Android & personnalisation** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/AppletRow.qml`](dev/AppletRow.qml), [`dev/OngletBarres.qml`](dev/OngletBarres.qml), [`dev/Theme.qml`](dev/Theme.qml)) : ouverture du panneau au clic sur l'îlot (heure/date incluse), filtrage de la barre étendue sur `systray`, `workspaces` et `minimise` (retrait du lecteur et des applets redondants), et curseur de vitesse d'animation du panneau (`panel_anim_duration`) dans l'onglet *Barres & Applets*.
- **Aperçu du prochain événement & raccourci Configuration** ([`dev/IslandTabAlertes.qml`](dev/IslandTabAlertes.qml), [`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml)) : affichage du prochain événement à venir dans *Alertes & Tâches* lorsqu'aucun événement n'est prévu sur la journée, et ajout d'un bouton *Configuration* dans l'en-tête de *Système & Réseau*.
- **Wi-Fi complet dans *Système & Réseau*** ([`dev/IslandTabSysteme.qml`](dev/IslandTabSysteme.qml), [`dev/core/system_service.py`](dev/core/system_service.py)) : force du signal (icône dynamique + pourcentage), surbrillance du réseau connecté (`in_use`), détection des réseaux connus (`nmcli connection show`) et champ de saisie inline de clé pour les réseaux protégés inconnus.

### Modifié

- **Ergonomie & rendu visuel du panneau et de la barre** ([`dev/IslandPanel.qml`](dev/IslandPanel.qml), [`dev/IslandTabControles.qml`](dev/IslandTabControles.qml), [`dev/main.qml`](dev/main.qml), [`dev/SystrayApplet.qml`](dev/SystrayApplet.qml)) : suppression du bouton « rectangles » dans la barre étendue et du liseré vertical des onglets ; dans *Contrôles*, le bouton d'alimentation éteint désormais la machine (`systemctl poweroff`) avec une icône lune (`weather-night`) dédiée à la mise en veille ; extension du visualiseur audio jusqu'aux bords en mode `island` et retour des icônes du systray en couleur native.

### Corrigé

- **Fluidité, flou, notifications et visualiseur** ([`dev/main.qml`](dev/main.qml), [`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/IslandTabMedia.qml`](dev/IslandTabMedia.qml), [`dev/NotifService.qml`](dev/NotifService.qml)) : suppression des saccades à l'ouverture (hauteur Wayland pré-dimensionnée, préchargement asynchrone de `IslandPanel.qml`, sous-processus différés), application de la même règle de flou que le panneau de configuration (`Theme.surfaceBg` sans double multiplication d'opacité), fermeture du panneau au clic sur une notification (`openNotifTarget`), icône `cog` sur *Système & Réseau*, et bascule fonctionnelle du visualiseur via `core/bar_applets.py`.

## [0.3.0] — 2026-11-13

### Ajouté

- **Panneau morphé à 3 états et 5 onglets pour l'Îlot dynamique** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/IslandPanel.qml`](dev/IslandPanel.qml), `dev/IslandTab*.qml`) : extension animée (`compact` → `etendu_barre` → `panneau` `680 × 420 px`) avec rail vertical gauche à 5 onglets (*Contrôles rapides*, *Média & Son*, *Alertes & Tâches*, *Système & Réseau*, *Apparence*), `HyprlandFocusGrab` (+150 ms) et commandes IPC `toggleIslandPanel` / `openIslandPanel`.
- **Décoration et morphing unifiés pour les panneaux de barre** ([`dev/PanneauSurface.qml`](dev/PanneauSurface.qml), [`dev/Popup.qml`](dev/Popup.qml), [`dev/CalendrierPanneau.qml`](dev/CalendrierPanneau.qml), [`dev/MediaPanneau.qml`](dev/MediaPanneau.qml)) : animation d'ouverture depuis le bord de la barre porteuse avec verre dépoli (`FlouFond`), `Theme.barBg`, `Theme.shellOpacity`, `Theme.pillRadius` et bordure `Theme.accent` / `Theme.barBorder`.
- **Transitions de fond d'écran par shader (`WallpaperFx`)** ([`dev/WallpaperFx.qml`](dev/WallpaperFx.qml), [`dev/shaders/wallfx.frag`](dev/shaders/wallfx.frag), [`dev/core/wallfx_maps.py`](dev/core/wallfx_maps.py), [`dev/hyprquickpaper/commands.sh`](dev/hyprquickpaper/commands.sh)) : propagation organique en cellules 4 px (`contagio`) et passage de relais sans accroc avec `awww`, inspiré de `diegoMalagrida/pocket-dots` (cité dans [`README.md`](README.md) et [`docs/README.md`](docs/README.md)).
- **Service de notifications persistant** ([`dev/NotifService.qml`](dev/NotifService.qml), [`dev/main.qml`](dev/main.qml)) : extraction de `NotificationServer` et de l'historique hors de `island_right.qml` pour garantir la réception des notifications au boot en mode `classic` comme en mode `island`.

### Modifié

- **Optimisations de performance & centralisation** ([`dev/Theme.qml`](dev/Theme.qml), [`dev/FlouFond.qml`](dev/FlouFond.qml), [`dev/FondProfondeur.qml`](dev/FondProfondeur.qml), [`dev/VisualiseurAudio.qml`](dev/VisualiseurAudio.qml), [`dev/spotlight.qml`](dev/spotlight.qml), [`dev/SystemePopup.qml`](dev/SystemePopup.qml)) : sonde unique `Theme.wallpaperCourant` (`awww query`), `SystemClock` dans `DynamicIsland`, suppression du dernier `FileView` redondant sur `bar_applets.json`, retrait de `--force` à l'ouverture de `SystemePopup`, cache LRU borné (20 entrées / TTL 8 s) dans `spotlight.qml` et lecture partagée de `Theme.systemInfo.hostname`.

### Corrigé

- **Stabilisation de l'Îlot dynamique & applets** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/main.qml`](dev/main.qml), [`dev/SystrayApplet.qml`](dev/SystrayApplet.qml), [`dev/LuminositeApplet.qml`](dev/LuminositeApplet.qml), [`dev/GestionEnergieApplet.qml`](dev/GestionEnergieApplet.qml), [`dev/island_right.qml`](dev/island_right.qml)) : maintien d'expansion lorsqu'un popup est ouvert, masque d'entrée Wayland (`Region`) pour éviter l'interception de clics hors pilule, suppression des séparateurs fantômes, dédoublonnage `musique`, exposition du bouton Réglages, correction `trayMa.containsMouse`, bornage du visualiseur (`160 px` max) et initialisation synchrone de `Theme.systemInfo`.

## [0.2.2] — 2026-11-13

### Ajouté

- **Mode Îlot dynamique (`DynamicIsland`)** : documentation complète de la disposition commutable dans les README en français et en anglais ([`README.md`](README.md), [`docs/README.md`](docs/README.md)).

### Modifié

- **Largeur compacte de l'îlot dynamique** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml)) : réduction de la taille de repos de 220 px à 90 px max pour un rendu minimaliste et épuré au centre de la barre.

### Corrigé

- **OSD du volume et de la luminosité dans l'îlot dynamique** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml)) : extension animée automatique de la pilule à 160 px minimum dès l'apparition de l'OSD pour éviter tout débordement de la jauge et du pourcentage, avec retour fluide au repos à expiration.
- **État Wi-Fi à la bascule de style de barre** ([`dev/ReseauApplet.qml`](dev/ReseauApplet.qml)) : synchronisation immédiate et binding direct sur `Theme.systemInfo` à l'instanciation du composant, supprimant le clignotement transitoire « Déconnecté » avant le rafraîchissement périodique.
- **Ancrage et maintien du calendrier dans l'îlot dynamique** ([`dev/DynamicIsland.qml`](dev/DynamicIsland.qml), [`dev/main.qml`](dev/main.qml)) : positionnement direct sous la pilule et maintien forcé de l'état étendu tant que la popup du calendrier est ouverte.
- **Rendu visuel des ombres et du flou** ([`dev/FlouFond.qml`](dev/FlouFond.qml)) : masque d'arrondi propre sur `MultiEffect` et alignement sans redondance.

## [0.2.1] — 2026-11-12

### Ajouté

- **Les quotas Antigravity se lisent par fenêtre, sur le CLI lui-même** ([`dev/core/antigravity_service.py`](dev/core/antigravity_service.py), [`dev/core/comptes_applet.py`](dev/core/comptes_applet.py)) : `agy -p /usage --output-format json` répond depuis la session déjà ouverte, sans tour de modèle et sans consommer de quota, et rend un bucket par couple (groupe de modèles, fenêtre) — fraction restante et heure de remise à zéro : Gemini 7 j et 5 h, Claude/GPT 7 j et 5 h, Gemini 4 Argon 7 j, soit cinq fenêtres sur un abonnement Pro. C'est plus précis que l'API Code Assist, qui donne un reste par modèle sans dire à quelle fenêtre il appartient, et que les logs, qui ne savent dire que « bloqué jusqu'à ». Le service garde ses replis dans l'ordre — API, puis logs, puis dernier relevé complet daté — et retient un échec du CLI dix minutes : `agy` sans session ouverte lance son flux OAuth et se bloque, ce qui ne doit pas coûter l'attente à chaque rafraîchissement. Le widget passe en tableau sans changement de QML (`widgets/llm.qml` rendait déjà des `lignes` : une ligne par fenêtre, nom, tranche, pourcentage, échéance) ; l'applet reprend la fenêtre dans son libellé (« Claude/GPT 7 j »), sinon deux lignes de la même famille portent le même nom avec deux chiffres différents. Mesuré : 2,9 s à froid, 0,05 s depuis le cache, cinq lignes.

- **La limite de charge se bascule sans mot de passe** ([`dev/charge-limit/`](dev/charge-limit), [`dev/core/system_service.py`](dev/core/system_service.py), [`dev/deploy.sh`](dev/deploy.sh)) : l'action polkit `org.aethershell.charge.limit` est liée au helper `/usr/local/bin/aether-charge-limit` par `org.freedesktop.policykit.exec.path`, donc `pkexec` présente cette action et non l'exécution générique de n'importe quel programme en root. Le helper (`80|100|status`) écrit le seuil générique et le `conservation_mode` d'`ideapad_acpi` quand ils existent, puis relit ce qu'il a écrit ; une règle JS dispense les membres de `wheel` en session locale active, le défaut restant `auth_admin` pour tous les autres — une session distante garde le mot de passe. L'installation est idempotente par empreinte sha256 des trois fichiers, retenue hors de `~/.config/quickshell` que l'élagage nettoie : une machine à jour ne voit aucune invite à chaque déploiement. L'applet notifie l'échec — le JSON de `system_service.py` porte `error` — au lieu de laisser un interrupteur revenir tout seul.

### Modifié

- **Le plafond de charge affiché est celui que la machine applique** ([`dev/core/system_service.py`](dev/core/system_service.py), [`dev/GestionEnergieApplet.qml`](dev/GestionEnergieApplet.qml), [`dev/LuminositeApplet.qml`](dev/LuminositeApplet.qml)) : le `conservation_mode` d'IdeaPad vise 60 %, pas 80 % — l'applet annonçait donc « 80 % » puis affichait le `Not charging` du contrôleur comme une panne, à un niveau inférieur au plafond promis. Le service publie `limit_pct` et `limit_kind` (seuil ou conservation), le libellé suit la valeur réelle, et à plafond atteint l'applet écrit « limite atteinte ».

### Corrigé

- **L'agent polkit de la session est réellement lancé** ([`dev/core/agent_polkit.sh`](dev/core/agent_polkit.sh), [`dev/systemd/polkit-agent.service`](dev/systemd/polkit-agent.service), [`dev/core/config_manager.py`](dev/core/config_manager.py), [`dev/deploy.sh`](dev/deploy.sh)) : le garde `pgrep -f "(polkit-…)"` de l'entrée d'autostart se reconnaissait dans sa propre ligne de commande, répondait « déjà lancé » et sortait — l'agent n'était jamais démarré, donc `pkexec` échouait sans un mot et les actions qui écrivent dans `/sys` ne faisaient rien. Le garde vit désormais dans un script, où le motif n'est plus dans la ligne de commande, et il compare les **sessions** (`/proc/<pid>/sessionid`) : sur une machine où le compositeur et le shell sont dans deux sessions logind, un agent lancé par l'autostart ne sert à rien pour les applets. Une unité `polkit-agent.service`, activée par le déploiement, le lance depuis la session du shell ; `hyprpolkitagent`, qui part en SIGSEGV sous `systemd --user` sans compositeur visible, passe en dernier recours, et l'unité est bornée à trois essais par minute. Vérifié par `pkcheck` : `org.aethershell.charge.limit` répond « yes » sans interaction, `org.freedesktop.policykit.exec` reste en `auth_admin`.

## [0.2.0] — 2026-11-11

### Ajouté

- **Installation et mise à jour en une seule ligne** ([`install.sh`](install.sh), [`dev/core/maj_shell.py`](dev/core/maj_shell.py), [`dev/OngletEcrans.qml`](dev/OngletEcrans.qml), [`dev/deploy.sh`](dev/deploy.sh), [`dev/config_panel.qml`](dev/config_panel.qml), [`dev/dependencies.txt`](dev/dependencies.txt)) : `curl -fsSL https://raw.githubusercontent.com/onewheelamo/aethershell/master/install.sh | sh` lit la distribution dans `/etc/os-release`, clone le dépôt ou le met à jour en avance rapide (`--ff-only` : un clone divergent s'arrête au lieu de fabriquer une fusion), puis lance `deploy.sh` — sauvegarde comprise. Le panneau gagne un tiroir « Mise à jour du shell » dans l'onglet « Écrans & Système » : version posée, version publiée sur GitHub, pastille « à jour / X disponible / état inconnu », et trois gestes — vérifier tout de suite, mettre à jour (la commande s'ouvre dans le terminal par défaut via `core/maj_terminal.sh`, le déploiement redémarre le shell), copier la ligne pour une autre machine. La comparaison s'appuie sur `core/version.json`, écrit par `deploy.sh` à chaque déploiement (le dossier déployé n'est pas un dépôt git, il ne pouvait pas dire quelle version il portait). `maj_shell.py` n'interroge GitHub qu'une fois toutes les **280 minutes** et répond depuis `~/.cache/quickshell/maj_shell.json` entre deux : ouvrir le panneau ne sort pas sur le réseau ; après un échec, un nouvel essai attend 10 minutes, et une panne n'efface pas la dernière version connue. Le minuteur du panneau ne tourne que tant que l'onglet est affiché. `git` et `curl` rejoignent `dependencies.txt`. Mesuré : la ligne complète sur un dossier vide (clone compris) rend la main en 2,0 s, 0,8 s au passage suivant ; `maj_shell.py` répond en 57 ms quand le cache est frais contre 426 ms pour un aller-retour GitHub en `--force` ; cache vieilli puis ouverture du panneau sur la section (`quickshell ipc -n call shell openConfigSection systeme_maj`) : le fichier de cache est réécrit à l'instant et le journal ne porte aucune erreur QML (le premier essai en portait une : une accolade de trop peu dans `OngletEcrans.qml`, corrigée).
- **Les gaps extérieurs de la barre se règlent, latéral et vertical séparément** ([`dev/Theme.qml`](dev/Theme.qml), [`dev/main.qml`](dev/main.qml), [`dev/bar_extra.qml`](dev/bar_extra.qml), [`dev/OngletBarres.qml`](dev/OngletBarres.qml), [`dev/config_panel.qml`](dev/config_panel.qml), [`dev/core/config_manager.py`](dev/core/config_manager.py), [`dev/core/style_vars.json`](dev/core/style_vars.json)) : `Theme.gutter` était une constante de 8 px — ce sont désormais deux réglages, `bar_gaps_out_h` (gauche/droite) et `bar_gaps_out_v` (haut/bas), de 0 à 32 px chacun, sous « Barres du shell » et dans la recherche du panneau. L'ancienne clé unique `bar_gaps_out` reste lue en repli : une machine déjà réglée garde exactement son aspect. La surface de la barre du haut et la bande qu'elle réserve aux fenêtres étaient écrites en dur pour une marge de 8 px (`+ 14` et `+ 10`) : elles suivent la marge verticale (`+ gutterV + 6`, `+ gutterV + 2`), et la pilule prend la marge latérale sur ses deux côtés. Mesuré (hauteur de barre 30 px) par `hyprctl monitors` (bande réservée) et `hyprctl layers` (géométrie des surfaces) : à h=20/v=3 la barre du haut reste à 35/39 comme à v=3 seul, la barre du bas mesure 1880 px de large à x=20 et sa réserve 36 ; à h=3/v=20 la barre du haut passe à 52/56, la barre du bas à x=3 et 1914 de large, sa réserve à 70 ; la barre de gauche se pose à x=3 sur 988 px de haut et réserve 36. Chaque axe ne déplace que ce qu'il doit.

- **Mettre une fenêtre de côté et la rappeler d'un clic** ([`dev/Theme.qml`](dev/Theme.qml), [`dev/MinimiseApplet.qml`](dev/MinimiseApplet.qml), [`dev/core/app_classes.py`](dev/core/app_classes.py), [`dev/core/applets_catalogue.json`](dev/core/applets_catalogue.json), `~/.config/hypr/binds.lua`) : Hyprland 0.57 n'a pas de « minimiser », donc **SUPER + D** envoie la fenêtre au focus sur le workspace spécial `special:minimized`, et **SUPER + Maj + D** rappelle la dernière sur le bureau courant. L'applet « Fenêtres minimisées » montre une icône par fenêtre (celle de son entrée `.desktop`), un clic la rappelle au premier plan ; la rangée a une largeur nulle quand rien n'est de côté, et le rappel ne mémorise aucun bureau d'origine — la liste est lue sur `Hyprland.toplevels`, donc une fenêtre fermée ne laisse pas d'entrée fantôme. `core/app_classes.py` porte la seule règle de rapprochement classe ↔ `.desktop` (celle du systray, désormais partagée avec `tray_apps.py`). Mesuré : 1 icône de 26 px (`Image.Ready`) en moins d'une seconde après le geste, 52 px pour deux fenêtres avec rappel de la plus récente d'abord, retour à 0 px après rappel — sans relancer le shell. Sonde : `quickshell ipc -n call minimise etat`.

- **Les maquettes et les aperçus du greeter sortent du dépôt** ([`.gitignore`](.gitignore)) : `dev/mockups/` (18 rendus PNG, 24 Mo, et les pages HTML de conception) et `dev/sddm/preview/` étaient versionnés alors que ce sont des images, pas du code. Ils sont ignorés, retirés de l'index et **purgés de l'historique** (`git filter-repo`) — un clone neuf du dépôt pèse 4,9 Mo au lieu de 29. Les fichiers restent sur la machine. Deux textes qui y renvoyaient (proposition du greeter, commentaire de `screenshot_bar.qml`) ne pointent plus vers un dossier absent.

- **Le dépôt ne nomme plus personne** ([`dev/core/neutralite.py`](dev/core/neutralite.py), [`dev/core/notif_target.py`](dev/core/notif_target.py), [`dev/core/screenshot.sh`](dev/core/screenshot.sh), [`dev/sddm/50-greeter-palette.rules`](dev/sddm/50-greeter-palette.rules)) : AetherShell doit s'installer sous n'importe quel compte. `neutralite.py` lit les fichiers suivis et signale tout `/home/<nom>` qui n'est pas un espace réservé, le nom de la personne qui lance le contrôle et celui de sa machine (avec une liste de noms trop banals pour être cherchés : « portable », « localhost »). Le pré-vol du déploiement l'exécute et avertit sans bloquer ; une ligne peut porter `neutralite:ok — <raison>`. Corrigé au passage : la règle polkit du greeter nommait l'utilisateur en dur — elle accepte maintenant tout utilisateur local actif, sur ce seul programme ; la clé de hint `x-amo-open` devient `x-aethershell-open` (l'ancienne reste lue). Éprouvé : contrôle propre sous l'identité réelle, et un `/home/<nom>` injecté dans un fichier suivi est bien signalé par le pré-vol.

- **Deux crochets git gardent le dépôt, sur chaque machine** ([`dev/hooks/pre-commit`](dev/hooks/pre-commit), [`dev/hooks/pre-push`](dev/hooks/pre-push), [`dev/deploy.sh`](dev/deploy.sh)) : `.gitignore` ne protège que les fichiers **non suivis** — `git add -f` passe outre, et un `commit -a` après un force-add ne redemande rien. Le `pre-commit` refuse les chemins interdits (`dev/core/secrets.json`, `*.upstream`, `sync.sh`, `dev/sync.sh`, `dev/mockups/`, `dev/sddm/preview/`) puis passe `core/neutralite.py` sur les fichiers suivis ; le `pre-push` refait le même contrôle sur ce qui va réellement partir (`origin/master..HEAD`), parce que `git commit --no-verify` contourne le premier sans rien dire. `deploy.sh` repose `core.hooksPath = dev/hooks` à chaque déploiement **et** vérifie que le fichier existe : un `hooksPath` qui pointe dans le vide ne dit rien et laisse tout passer. Éprouvé sur cette machine : `git add -f` d'un `*.upstream` puis `git commit` → « Commit refusé », code 1, l'index intact.

### Modifié

- **L'applet des fenêtres minimisées est actif par défaut** ([`dev/core/bar_applets.json`](dev/core/bar_applets.json)) : « Fenêtres minimisées » rejoint la dotation d'une installation neuve, dans l'îlot de gauche (`haut:debut`, ordre 15, entre les bureaux et les comptes). Sa largeur est nulle tant que rien n'est de côté (`efface_vide`), donc la barre ne change pas d'aspect à l'arrivée : la place n'apparaît qu'au premier **SUPER + D**. Rien à faire sur une machine déjà réglée — `bar_applets.json` est un état local préservé au déploiement.

- **Un applet peut se refermer quand il n'a rien à montrer** ([`dev/Applet.qml`](dev/Applet.qml), [`dev/core/applets_catalogue.json`](dev/core/applets_catalogue.json)) : la rangée d'un îlot dessine ses applets avec un `spacing`, donc un applet de largeur nulle laissait un trou de la largeur d'un espace. Le catalogue porte une clé `efface_vide` pour les applets « qml » dont le contenu est transitoire (les fenêtres mises de côté) : leur place disparaît tant qu'ils sont vides. Les autres applets ne changent pas — la clé est fausse par défaut.

- **Le masque du fond et les captures retrouvent leur tiroir** ([`dev/OngletApparence.qml`](dev/OngletApparence.qml), [`dev/OngletEcrans.qml`](dev/OngletEcrans.qml), [`dev/config_panel.qml`](dev/config_panel.qml)) : la bascule du **masque de profondeur** (`depth_mask`, avec seuil et adouci) quitte le tiroir des fenêtres pour celui du fond d'écran, où elle se lit à côté de « Fond en profondeur » ; elle est aussi atteignable par la recherche du panneau. Le **dossier des captures** quitte le même tiroir pour un tiroir propre dans l'onglet « Écrans & Système » (clé `ecrans_captures`), et l'entrée de recherche pointe désormais sur le bon onglet — elle ouvrait auparavant « Apparence » sur un tiroir qui n'avait pas la ligne. Les titres des 26 tiroirs suivent un même schéma : phrase (seul le premier mot en capitale), « & » pour apparier deux termes, ni parenthèse ni tiret (`Barres du shell`, `Lanceur Spotlight`, `Énergie & horloge`, `Écran de connexion`, `Tâches suivies`…).

### Corrigé

- **Les fenêtres GTK4 retrouvent leur flou** ([`dev/core/gtk4-flou.css`](dev/core/gtk4-flou.css), [`dev/deploy.sh`](dev/deploy.sh)) : depuis GTK 4.24, GTK crée l'objet Wayland `ext-background-effect-v1` pour **chaque** surface et laisse la région de flou **vide** — une région vide veut dire « ne me floute pas », et Hyprland (≥ 0.56) obéit : plus aucune fenêtre GTK4 n'était floutée (Bazaar, ProtonVPN — GTK4 depuis sa 4.19 —, Nautilus…), sans une ligne au journal, et aucun `window_rule` ne peut forcer le flou d'une fenêtre qui l'a refusé. Le fichier livré ne déclare que la région (`window { backdrop-filter: blur(20px); }`) ; l'intensité reste celle du compositeur. `deploy.sh` le copie dans `~/.config/gtk-4.0/aethershell-flou.css` et accroche l'`@import` au `gtk.css` de la session **une seule fois** — le fichier de l'utilisateur n'est jamais réécrit, seule une ligne y est ajoutée. Mesuré par la trace Wayland (`WAYLAND_DEBUG=1`, comptes de `get_background_effect` / `set_blur_region`) : fenêtre GTK4 nue **1/0** sans le CSS, **1/2** avec ; Bazaar donne le même couple dans son bac à sable, où il lui faut **son** `~/.var/app/<app>/config/gtk-4.0/gtk.css` (un Flatpak n'a pas `xdg-config` dans ses permissions). Un Flatpak est mono-instance : le mesurer impose `flatpak kill` d'abord, sinon la trace est vide et se lit comme « pas de flou demandé ». Le CSS est lu au démarrage d'une application : seules les fenêtres ouvertes après le déploiement en profitent.

- **Le verrou du lanceur ne survit plus au shell par ses enfants** ([`dev/core/lancer_quickshell.sh`](dev/core/lancer_quickshell.sh)) : le verrou d'instance unique était un `flock` sur `$XDG_RUNTIME_DIR/aethershell.shell.lock` tenu pendant toute la vie du shell par le descripteur conservé à l'`exec` — donc **hérité par ses enfants** (`pactl subscribe`, `inotifywait`, `tray_watchdog`, `notif_target`). Un shell mort laissait derrière lui des orphelins qui gardaient le verrou : le lanceur suivant répondait « un lancement est deja en cours, rien a faire » et la barre restait absente jusqu'à ce qu'on les tue (mesuré le 2026-11-11, trois orphelins). Le verrou de vie disparaît, remplacé par deux pièces : un `flock` **court** sur `aethershell.lancement.lock`, tenu seulement le temps de la décision (attente du compositeur comprise) et **refermé juste avant l'`exec`** ; et un **jeton** `aethershell.shell.pid` qui nomme le pid du shell et son heure de démarrage (champ 22 de `/proc/<pid>/stat`, insensible au recyclage des pid), valide seulement si `/proc/<pid>/cmdline` nomme encore `quickshell` hors `-p` / `--path`. Un jeton ne se transmet pas : les orphelins d'un shell mort ne bloquent plus rien, et le lanceur en attente du compositeur est reconnu par le pid qu'il portera après son `exec`. Éprouvé sur un banc en espace de noms de pid (faux `quickshell` qui lance un enfant dormant, 20 vérifications, 0 échec) : avant, l'enfant héritait du verrou et le lanceur suivant laissait **zéro** shell après la mort du premier ; après, l'enfant n'hérite d'aucun descripteur `aethershell.*`, le shell redémarre malgré l'orphelin vivant, deux lancements simultanés n'en donnent qu'un, un `-p` ne compte pas, un jeton périmé ou forgé sur un pid étranger ne bloque rien. Vérifié en production : jeton `19131 25965`, aucun des quatre enfants ne tient de descripteur, `kill -9` du shell → nouveau shell en ~3 s avec la barre revenue (`hyprctl layers`). Récupération si un lancement reste bloqué : `rm -f $XDG_RUNTIME_DIR/aethershell.shell.pid` — l'ancien `fuser -k` n'a plus d'objet.

- **Trois entrées de la recherche du panneau ouvraient le mauvais onglet** ([`dev/config_panel.qml`](dev/config_panel.qml)) : « Arrondis des îlots », « Hauteur de la barre » et « Espaces entre les îlots » portaient encore `tab: 0, section: "quickshell_barre"` — la section de l'onglet Apparence — alors que ces trois lignes vivent dans « Barres & Applets », section `quickshell_barres`. Le clic ouvrait donc Apparence et un tiroir qui ne contenait pas la ligne visée. Les trois entrées portent le bon onglet ; celles qui visent encore `quickshell_barre` (barre et surfaces, opacité, flou des surfaces) sont bien restées dans Apparence et n'ont pas changé.

- **Une seule instance du shell au démarrage** ([`dev/core/lancer_quickshell.sh`](dev/core/lancer_quickshell.sh), [`dev/core/autostart.json`](dev/core/autostart.json)) : deux chemins de lancement coexistent (l'unité systemd et l'autostart Hyprland) et le garde-fou `pgrep -x quickshell` de l'autostart ne voit pas le `sh` du lanceur pendant qu'il attend le compositeur — mesuré au boot à froid : 16 s d'attente, puis **deux barres** (la seconde posée à `y=40`, sa zone exclusive venant sous la première), deux jeux de veilleurs (`notif_target`, `tray_watchdog`, `pactl subscribe`, `inotifywait`) et deux instances à qui parlait l'IPC `shell`. Le lanceur prend maintenant un **verrou** — `flock -n` sur `$XDG_RUNTIME_DIR/aethershell.shell.lock`, tenu pendant toute la vie du shell par le descripteur conservé à l'`exec` — et refuse, sous verrou, de doubler une instance existante ; un lancement d'une autre configuration (`-p` / `--path`, le sélecteur de fond d'écran) ne compte pas. L'entrée d'autostart passe par ce lanceur au lieu d'appeler `quickshell` en direct. Éprouvé : un second appel sort en 0 sans rien démarrer, pendant l'attente du compositeur comme pendant la vie du shell, et le verrou se libère exactement à la mort du processus.

## [0.1.5] — 2026-11-11

### Ajouté

- **Le catalogue des schémas de couleurs est lu sur le disque ([`dev/core/themes_scan.py`](dev/core/themes_scan.py), [`dev/core/veille_themes.sh`](dev/core/veille_themes.sh))** :
  - `core/palette_cache.json` porte le catalogue (nom, palette convertie, chemin), recopié des deux dossiers à chaque scan — `~/.local/share/color-schemes` et `/usr/share/color-schemes`. C'est une donnée dérivée, ignorée par git.
  - Lecture **unique au démarrage du shell** ([`dev/main.qml`](dev/main.qml)), puis relecture dès qu'un `.colors` apparaît ou disparaît dans l'un des deux dossiers : veille `inotifywait` (un processus, sans sondage), avec un regroupement de 600 ms sur les rafales de fichiers.
  - Un schéma supprimé du disque disparaît de la liste du panneau ; l'étiquette de l'active reste.
  - Option `--signature` (empreinte du disque, sans écrire) pour le diagnostic.
- **Lanceur de service ([`dev/core/lancer_quickshell.sh`](dev/core/lancer_quickshell.sh))** : vérifie que le socket Wayland existe avant de lancer Qt, attend jusqu'à 20 s (`QS_ATTENTE_S`), retrouve la signature Hyprland la plus récente, et sort en 1 sans rien démarrer si la session ne vient pas.
- `inotifywait` ajouté aux dépendances ([`dev/dependencies.txt`](dev/dependencies.txt)).
- **Les tâches de code ne s'écrivent plus toutes seules ([`dev/core/todo_worker.py`](dev/core/todo_worker.py))** : le prompt du worker interdit désormais de modifier le dépôt ou l'environnement vivant et demande une **proposition** dans `~/.cache/quickshell/propositions/<date>-<sujet>.md` (fichier visé, lignes, code actuel et proposé, points à vérifier). Un fichier déposé pendant l'exécution laisse la tâche ouverte avec la mention « proposition à valider : … » et une notification dédiée — elle ne se ferme plus sur un `✓ fait` alors que du code a été touché.

### Modifié

- **Le tiroir « disques affichés » est atteignable, et les onglets visités restent montés** ([`dev/config_panel.qml`](dev/config_panel.qml), [`dev/OngletBarres.qml`](dev/OngletBarres.qml)) : `secDisques` vit dans un `Repeater`, donc son id n'est pas dans la portée du fichier et les tables `sections` / `cibles` ne pouvaient pas le nommer — le clic milieu ouvrait l'onglet sans amener le tiroir. Il porte un `objectName`, l'onglet publie `sectionsTardives` et une recherche en profondeur, que `tiroirDe` / `cibleDe` consultent en dernier recours ; la clé de section est désormais écrite dans l'état au clic (mesuré). Côté onglets : quitter ne détruit plus le composant, tout est libéré à la fermeture du panneau — quatre visites alternées de deux onglets ne provoquent que deux chargements.

- **Taille du flou des surfaces : de 1 à 96 px, pas de 1** ([`dev/OngletApparence.qml`](dev/OngletApparence.qml), [`dev/Theme.qml`](dev/Theme.qml), [`dev/core/config_manager.py`](dev/core/config_manager.py)) : la borne basse était à 8 px et le pas à 4, ce qui interdisait les petits rayons. Vérifié : 2 px est conservé, 0 est ramené au plancher de 1.

- **`style_vars.json` ne porte plus le catalogue** ([`dev/core/style_vars.json`](dev/core/style_vars.json)) : 99 palettes → 3. Le fichier suivi perd 1 250 lignes ; la migration est automatique au premier démarrage (le scan purge les palettes importées et n'en garde aucune, sauf l'active).
- **Une seule palette importée vit dans la configuration, et seulement à l'activation** : [`dev/core/themes_scan.py`](dev/core/themes_scan.py) (`activer`) recopie ses couleurs dans `palette[active_theme]`, ce qui laisse rofi, le terminal, SDDM et `Theme` inchangés.
- [`dev/core/theme_manager.py`](dev/core/theme_manager.py) délègue à `themes_scan.activer` — il testait `theme_name in palette` et aurait refusé tous les thèmes du disque.
- [`dev/core/installer_theme_couleur.py`](dev/core/installer_theme_couleur.py) active le schéma du fichier choisi (et non le dernier ajouté, désigné par l'ordre alphabétique) et publie ses avertissements au lieu de conclure « installé avec succès ».
- [`dev/dependencies.txt`](dev/dependencies.txt) n'existe plus qu'en un exemplaire, à la racine du dépôt ; [`dev/deploy.sh`](dev/deploy.sh) le copie **après** l'élagage (sinon il était archivé puis reposé à chaque déploiement) et l'élagage l'épargne.
- [`dev/core/generate_terminal_theme.py`](dev/core/generate_terminal_theme.py) écrit les configurations de terminal de façon atomique (`.tmp` + `os.replace`) : un arrêt au mauvais moment ne laisse plus un `user.conf` ou un `alacritty.toml` tronqué.
- [`dev/core/lien_systeme.py`](dev/core/lien_systeme.py) écrit `helpers.rc`, `mimeapps.list` et les aides exo atomiquement, et conserve le préambule de commentaires de `mimeapps.list`.
- [`dev/CHANGELOG.md`](CHANGELOG.md) ne nomme plus le parc : 25 liens `file:///home/<utilisateur>/...` sont devenus des chemins relatifs.
- **Le panneau de configuration se découpe ([`dev/config_panel.qml`](dev/config_panel.qml), [`dev/OngletApparence.qml`](dev/OngletApparence.qml))** : l'onglet *Apparence* (1 499 lignes) sort dans son fichier, nommé comme le libellé du rail, chargé par URL et instancié à la première ouverture. Le panneau passe de 9 000 à 7 500 lignes ; une règle de gel en tête du fichier interdit d'y ajouter de nouvelles options (elles naissent dans leur propre composant). Les tables `targetMap` et `tiroirs` ne peuvent plus nommer les sections d'un onglet déporté : elles passent par `tiroirDe()` / `cibleDe()`, que l'onglet alimente par ses propres `sections` et `cibles` — un id absent lève sinon « ReferenceError: secTheme is not defined ».
- **Le panneau n'est plus instancié au démarrage ([`dev/main.qml`](dev/main.qml))** : son `Loader` n'avait pas d'`active`, donc les 7 500 lignes étaient analysées et montées à chaque lancement du shell. Il est désormais créé à la **première** ouverture puis conservé (onglet, tiroirs et défilement en place). Mesuré sur trois relances : 1,25 s → 0,62 s jusqu'à la barre, et aucune couche `shell-config` au démarrage ; réouverture en 0,14 s. L'ouverture par IPC avant la première création fonctionne toujours : le panneau reprend `Theme.configTarget` dans son `Component.onCompleted`.
- **Le panneau est découpé en huit composants** ([`dev/config_panel.qml`](dev/config_panel.qml), `OngletBarres/Bureau/Ecrans/Clavier/Apps/Connexion/Donnees.qml`) : 7 500 → 2 230 lignes. Chaque onglet est un fichier chargé à l'ouverture, un `Loader` nu par onglet et une seule fonction `majOnglets()` qui décide lequel vit. Deux pièges mesurés au journal, tous deux dus au chargement différé : `source:` + `onLoaded` injectait `root` **après** la création du corps, alors que ses liaisons le lisent à l'évaluation (« Cannot read property 'nuitA' of undefined ») — d'où `setSource(url, propriétés)`, qui les pose avant ; et `loader.source` vaut `undefined` et non `""` sur un Loader neuf, donc la garde testait la mauvaise condition (le panneau s'ouvrait sur un onglet vide). Le corps des onglets n'a pas bougé d'un caractère hors indentation ; le conducteur appartenait au `Flickable` et non à la racine, ce que l'indentation ne disait pas.
- **Une seule source pour les cibles de notification ([`dev/config_panel.qml`](dev/config_panel.qml), [`dev/core/config_manager.py`](dev/core/config_manager.py))** : le panneau tenait deux `FileView` — `notif_targets.json` et `app_vars.json` — pour des données que `config_manager.py state` renvoie déjà (programmes) ou peut renvoyer (`notif_targets`, ajouté au payload). Les deux `FileView` sont supprimés, le panneau lit l'état comme pour le reste : moins de fichiers surveillés, et plus de risque qu'une valeur affichée vienne d'une lecture plus ancienne que la dernière écriture. `state` est appelé à l'ouverture et après chaque commande, donc l'affichage suit toujours. Aller-retour vérifié : `notif_type_set text Files` → l'état renvoie `Files`, retour à `Editor`, fichier identique à l'original.
- **Le plancher de flou des sélecteurs est retiré, et les seuils sont écrits dans le panneau** ([`dev/SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml), [`dev/OngletApparence.qml`](dev/OngletApparence.qml)) : les deux feuilles forçaient `Math.max(Theme.shellFlouInterne, 0.85)`, donc ignoraient le réglage. Ce plancher était un doublon : elles sont des `Item` dans la fenêtre `shell-config`, déjà floutée par le compositeur. Elles suivent maintenant `shell_flou_interne` comme le reste. Deux notes dans le panneau disent ce que chaque réglage implique : sous 30 % d'opacité de surface, Hyprland cesse de flouter (`ignore_alpha`) ; au-delà de ~70 %, le verre interne n'apporte plus rien ; entre les deux, les deux flous se cumulent — celui du compositeur, fenêtres comprises, et le verre interne, fond seul.
- **Les deux sélecteurs de fichiers ne vivent que le temps d'un choix ([`dev/config_panel.qml`](dev/config_panel.qml))** : `SelecteurDossier.qml` et `SelecteurFichier.qml` (850 lignes à eux deux) étaient montés avec le panneau pour ne servir qu'après un clic sur « Choisir ». Ils sont créés au premier besoin, et relâchés 300 ms après leur fermeture (le temps que la fermeture se fasse avant la destruction de l'item). Leurs paramètres passent par `onLoaded` : l'item n'existe pas encore au moment du clic.

### Corrigé

- **Le lanceur n'accepte plus un socket mort** ([`dev/core/lancer_quickshell.sh`](dev/core/lancer_quickshell.sh), [`dev/systemd/quickshell.service`](dev/systemd/quickshell.service)) : les 204 coredumps de quickshell sont tous le même `SIGABRT` dans `QGuiApplicationPrivate::createPlatformIntegration` — Qt démarré sans compositeur joignable. Le nœud de socket survit à la session qui l'a créé, donc le test d'existence du lanceur le validait alors que plus personne n'écoutait. Sur Hyprland, le lanceur exige maintenant une **réponse** (`hyprctl -i <signature> version`), garde 45 s de patience, et sort en 1 sans rien lancer sinon ; `LimitCORE=0` sur l'unité empêche un cœur de 1,6 Mo par abandon. Éprouvé sur trois cas : session vivante (environnement correct, arguments transmis), socket mort + signature morte (sortie 1, rien de lancé), aucun socket (sortie 1).

- **Le panneau se rouvre sur son onglet, et l'onglet 0 respire** ([`dev/config_panel.qml`](dev/config_panel.qml), [`dev/CollapsibleSection.qml`](dev/CollapsibleSection.qml), [`dev/OngletApparence.qml`](dev/OngletApparence.qml)) : `libererOnglets()` décharge tout à la fermeture, mais rien ne rechargeait à la réouverture — rouvrir sur le même onglet ne change pas `currentTab`, donc `onCurrentTabChanged` ne se déclenchait pas et il ne restait que le rail. `onConfigPanelVisibleChanged` appelle maintenant `majOnglets()` à l'ouverture. Mesuré : fermé → `statut=0 item=nul`, rouvert → `item=present`, onglet complet à 348 px. Côté mise en page : la colonne de l'onglet 0 n'avait aucun `spacing` — ses quatre tiroirs se touchaient — elle passe à 10 px (mesuré : y = 0, 44, 88, 132 pour des bandeaux de 34 px), et `CollapsibleSection` gagne `espacementContenu`, mis à 8 px sur « Fonds d'écran & Captures » en y retirant les trois espaces manuels (6, 10, 2 px) qui se seraient additionnés (mesuré : écarts de 8 px entre ses éléments).

- **Les onglets du panneau ne s'empilent plus** (`Onglet*.qml`) : en cessant de décharger l'onglet qu'on quitte, ils restaient tous montés — et le `visible:` que la découpe avait retiré du corps de chaque onglet n'était plus là pour les masquer. Deux onglets se dessinaient l'un sur l'autre. Chaque composant porte de nouveau `visible: root.currentTab === <index>`. Mesuré 300 ms après chaque bascule (le gestionnaire de signal tourne avant la réévaluation des liaisons, d'où une première lecture trompeuse) : un seul onglet visible à chaque fois.

- **La diffusion des couleurs atteint enfin les terminaux ouverts** ([`dev/core/generate_terminal_theme.py`](dev/core/generate_terminal_theme.py)) : le filtre qui protège les terminaux dont le premier plan n'est pas un shell appelait `tcgetpgrp()`, refusé avec `ENOTTY` sur **tous** les ptys de cette machine — y compris depuis un service utilisateur, alors que `tcgetattr()` passe : c'est l'ioctl TIOCGPGRP qui est filtré. Le filtre répondait donc toujours « programme au premier plan » et `--broadcast-only` annonçait « 0 pseudoterminaux (4 ignorés) ». Le premier plan se lit maintenant dans `/proc/<pid>/stat` (champ terminal et champ pgrp de premier plan), avec `tcgetpgrp()` en repli. Mesuré : 2 terminaux atteints, 2 ignorés (deux sessions d'agent au premier plan), 21 séquences OSC et 295 octets portant la palette active (`bg #0c0a09`, `fg #fbf3f1`).

- **Le greeter est déployé avec le shell** ([`dev/deploy.sh`](dev/deploy.sh), [`dev/core/greeter_manager.py`](dev/core/greeter_manager.py)) : `GENERATE` et `DEV_SDDM` visaient `~/dev/quickshell_todo/dev/sddm`, avec un `HOME.glob("**/…")` de repli qui parcourait tout le home. Sur une machine où le shell est seulement déployé, refresh de palette, miniatures, installation et désinstallation échouaient. `dev/sddm/` part maintenant dans `~/.config/quickshell/sddm` (fichiers seulement : `out/`, `preview/`, `__pycache__` sont des sorties de l'outil), le pré-vol le compte, et le module résout tous ses chemins par `get_sddm_dir()` — déploiement d'abord, clone ensuite, plus de parcours du home. Vérifié : le module **déployé** rend `~/.config/quickshell/sddm`, avec `install.sh` et `generate.py` présents.

- **Une seule règle d'état machine dans `deploy.sh`, et un verrou sur `style_vars.json`** ([`dev/deploy.sh`](dev/deploy.sh), [`dev/core/verrou_etat.py`](dev/core/verrou_etat.py)) : la préservation était dite en trois endroits qui avaient divergé — le pré-vol protégeait tout `.json` de `core/` non livré, la copie ne protégeait que `PRESERVE_CORE`, l'élagage avait sa propre liste. `dependencies.txt` était annoncé « à élaguer » à chaque pré-vol alors que le déploiement l'épargnait. `est_etat_machine(nom, dossier)` est désormais appelée par les trois, et les fichiers **régénérés** par le déploiement (`colors.lua`, `programs.lua`, `autostart_cmds.txt`, `hypridle.conf`…) en sont exclus : les traiter comme de l'état laissait un `.upstream` orphelin. Pré-vol comparé avant/après : 164 identiques, 7 modifiés, 2 nouveaux, 24 préservés, et **0 à élaguer** au lieu d'un faux positif ; déploiement réel passé, quatre `.upstream` avant comme après.
- **Trois écrivains de `style_vars.json` ne se perdent plus** ([`dev/core/verrou_etat.py`](dev/core/verrou_etat.py), [`dev/core/config_manager.py`](dev/core/config_manager.py), [`dev/core/themes_scan.py`](dev/core/themes_scan.py)) : chaque écriture était atomique, mais deux lecture-modification-écriture qui se croisaient perdaient une modification. Le verrou porte sur un fichier voisin (`flock`), jamais sur la cible que `os.replace` remplace. `config_manager` le tient pour toute la durée d'une commande (sauf `state`, qui n'écrit rien), `themes_scan` autour de `synchroniser` et `activer`. Mesuré, dix écritures concurrentes sur dix clés distinctes : **1 modification conservée avant, 10 après**.

- **Deux exécutions pour une seule tâche** ([`dev/core/todo_applet.py`](dev/core/todo_applet.py)) : `prendre()` écrivait sans verrou et **sans tester l'état** — douze processus concurrents repartaient tous avec « prise » (mesuré), donc douze agents sur une tâche. Les modifications de la file passent par `_maj_file()` sous `flock`, et la prise n'accepte qu'une demande encore en `attente`. Éprouvé : douze processus, une seule prise, les onze autres reçoivent « déjà prise ».

- **Les libellés des boutons des sélecteurs étaient décentrés** ([`dev/SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml)) : le script de la refonte en surface remplaçait `anchors.centerIn: parent` **partout** dans le fichier, pas seulement sur la carte qu'il fallait faire passer en `anchors.fill`. Quatre centrages perdus dans le sélecteur de dossier, six dans celui de fichier — « Annuler » et « Choisir » collés au coin haut-gauche. Restaurés un par un, et vérifiés par comparaison du nombre d'occurrences avec la version d'avant (5 → 4 et 7 → 6 : la carte, elle, remplit la fenêtre).

- **Les sélecteurs de fichiers sont des surfaces à part** ([`dev/SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml), [`dev/core/config_manager.py`](dev/core/config_manager.py)) : une `layer_rule` de flou ne floute qu'**entre** surfaces. Tant que la carte vivait dans la fenêtre du panneau, le verre interne ne pouvait montrer que le fond d'écran — jamais le panneau, donc jamais ce qu'il y a réellement derrière. Chaque feuille a maintenant sa propre fenêtre, de la taille de la carte (le compositeur ne floute que la région peinte : le panneau est flouté derrière, et rien ailleurs), et `shell-selecteur` entre dans `SHELL_BLUR_NAMESPACES`. `PanelWindow` se règle en `implicitWidth`/`implicitHeight` — avec `width`/`height` la surface restait de taille nulle et ne se mappait pas. Le `HyprlandFocusGrab` s'arme 150 ms après l'ouverture : Hyprland retire un grab posé sur une surface pas encore mappée, ce qui refermait la feuille à l'instant de son ouverture. Le voile plein écran disparaît avec — c'était lui qui assombrissait le panneau ; un clic hors de la carte referme, par le grab.

- **Les réglages du flou des surfaces sont dans le tiroir « Surfaces & Verre du shell »** ([`dev/OngletApparence.qml`](dev/OngletApparence.qml)) : le verre interne (« intensité », « taille », « passes ») et sa note avaient été posés dans « Fenêtres Hyprland », alors qu'ils ne concernent que les surfaces du shell. Ils sont déplacés en fin de tiroir « Surfaces & Verre du shell », avec l'opacité des surfaces, le flou Quickshell et le seuil de transparence.

- **La teinte passe au-dessus du verre** ([`dev/config_panel.qml`](dev/config_panel.qml), [`dev/main.qml`](dev/main.qml)) : le panneau et les quatre îlots de la barre peignaient leur couleur sur la même surface que le `FlouFond`, donc **sous** lui. Monter le flou interne faisait ressortir le fond d'écran à travers la teinte : à 70 %, le verre dominait à 70 % et les couleurs saturaient. La couleur vit maintenant dans une couche au-dessus du verre — fond d'écran flouté → teinte du thème → contenu. Effet de bord assumé : la `Behavior on color` des îlots n'anime plus qu'une couleur transparente ; l'animation de palette ne se voit plus sur la barre.

- **Taille et passes du flou des surfaces sont réglables** ([`dev/FlouFond.qml`](dev/FlouFond.qml), [`dev/Theme.qml`](dev/Theme.qml), [`dev/OngletApparence.qml`](dev/OngletApparence.qml)) : Hyprland ne règle `size` et `passes` qu'en global, fenêtres comprises — une `layer_rule` ne peut pas donner aux surfaces une diffusion à part. Les deux réglages vivent donc dans le verre interne, sous « Flou interne » : `shell_flou_taille` (rayon de base, 8–96 px) et `shell_flou_passes` (1–8), le rayon effectif valant `taille × passes / 3`, plafonné à 160 px. Les défauts reproduisent l'ancien rendu figé (48 px, 3 passes, 0,85). Mesuré : sans clé dans `style_vars.json`, le verre rend 0,84 et 48 px ; à taille 80 et 6 passes, 160 px. Le flou du compositeur, lui, reste global : ces curseurs ne touchent que le verre interne, donc le fond d'écran.

- **La barre de capture et l'historique des notifications suivent les réglages de verre** ([`dev/screenshot_bar.qml`](dev/screenshot_bar.qml), [`dev/notif_history.qml`](dev/notif_history.qml)) : les deux surfaces gardaient leur opacité en dur (0,88 et 0,92) et n'avaient aucun flou interne — elles ignoraient donc `shell_opacity` comme `shell_flou_interne`, alors que le panneau, les îlots de la barre et les sélecteurs suivent les deux. Elles passent à `Theme.surfaceBg` et reçoivent un `FlouFond`, avec la même intensité que le panneau. Mesuré, deux réglages successifs : la barre rend une opacité de 0,40 puis 0,90 quand `shell_opacity` passe de 0,4 à 0,9, et son flou suit 0,6 puis 0,2 ; le tiroir d'historique rend 0,40. Le commentaire du tiroir disait « pas de flou sur cette surface » — vrai pour une règle de flou du compositeur, puisque sa fenêtre est plein écran et qu'une `layer_rule` flouterait tout l'écran ; c'est précisément ce que `FlouFond` évite, en redessinant le fond d'écran **dans** la surface. Les cartes du tiroir suivent la même règle : `surfaceVariant` (opaque) devient `surfaceVariantBg`, soit l'opacité des surfaces plus 8 points — 0,48 avec le réglage actuel. `Qt.lighter` conserve l'alpha, donc survol et sélection restent translucides. Le flou derrière le tiroir, lui, ne peut pas venir du verre interne : `FlouFond` redessine le fond d'écran, jamais les fenêtres. Le namespace `shell-notif-history` entre donc dans `SHELL_BLUR_NAMESPACES` et le compositeur floute ce qui est réellement derrière — les fenêtres comprises. Le verre interne reste, à l'intensité du réglage, pour le cas du bureau nu. À savoir : `ignore_alpha` (0,30) borne l'ensemble — sous cette opacité de surface, Hyprland ne floute plus.

- **Accordéon des tiroirs rétabli, et tiroirs fermés par défaut** ([`dev/config_panel.qml`](dev/config_panel.qml), `Onglet*.qml`) : le découpage a vidé la table `tiroirs` du panneau, or quatre endroits la parcouraient — `fermerAutresTiroirs`, `setPanelSection`, `rafraichirTiroirs` et le calcul du bandeau collant. Une boucle sur un objet vide ne fait rien, sans lever d'erreur : ouvrir un tiroir n'en refermait plus aucun, et l'invariant « un seul ouvert par onglet » n'était plus tenu. Les quatre passent par `nomsTiroirs()`, qui réunit la table du panneau et les `sections` des onglets chargés — l'onglet affiché suffit, l'accordéon ne referme que des tiroirs du même onglet. Les neuf sections dont le défaut était `true` passent à `false`, et l'état accumulé est remis à zéro (quinze tiroirs marqués ouverts, plus une clé parasite `secTheme` écrite à la place d'un nom de tiroir). Vérifié sur le fichier vivant : ouvrir `quickshell_applets` referme `quickshell_barres`, ouvrir `quickshell_visualiseur` referme `quickshell_applets`, et aucune section n'est ouverte à l'ouverture du panneau.
- **Boucle de crash au démarrage du shell** ([`dev/systemd/quickshell.service`](dev/systemd/quickshell.service)) : `WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"` ne couvrait que la variable absente, pas une valeur périmée — Qt démarrait sans platform plugin et abandonnait (SIGABRT), relancé toutes les 3 s. Mesuré : 194 coredumps en sept jours, compteur de relance à 42. Le lanceur vérifie le socket et l'unité borne les relances (`StartLimitBurst=5`, `StartLimitIntervalSec=90`).
- **Toasts perdus quand un popup était ouvert** ([`dev/island_right.qml`](dev/island_right.qml)) : le compte à rebours de 4,5 s courait à l'**arrivée** de la notification, pas pendant l'affichage. Une alerte qui arrivait pendant qu'un panneau était ouvert était bien retardée (la fenêtre est réactive), mais son minuteur expirait entre-temps et elle ne se montrait jamais — mesuré : popup ouvert 7 s, aucun toast ; popup refermé au bout de 2 s, toast affiché. Le minuteur suit maintenant la visibilité (`toastVisible`), et une péremption de 60 s empêche une alerte différée de surgir un quart d'heure après les faits. C'est le cas des notifications de l'applet Tâches : cocher une case laisse son popup ouvert.
- **La croix du centre de notifications ne retirait plus les cartes** ([`dev/NotifsApplet.qml`](dev/NotifsApplet.qml), [`dev/island_right.qml`](dev/island_right.qml)) : après une relance du shell la liste vive est vide, et le centre affiche son repli — les cartes lues dans `notifications-history.jsonl`. Ces entrées ne sont connues d'aucun serveur, donc « oublier » n'avait rien à retirer (journal : « absente de la liste vive », quatre fois), et une carte retirée de la liste vive revenait par le repli. La croix retire désormais aussi l'entrée de l'historique, et « tout effacer » vide le fichier — vérifié : 125 entrées d'historique → 115 après dix retraits.
- **`FlouFond` réclamait un `fond-ecran.png` absent** ([`dev/FlouFond.qml`](dev/FlouFond.qml)) : 13 avertissements « Cannot open » par minute, en continu, pour tout fond sans profil de profondeur. Une tentative par surface, puis un drapeau (`ecranIndisponible`) — il reste un avertissement par surface au démarrage, aucun ensuite.
- **Les couleurs du terminal n'atteignaient pas les nouveaux shells** : `~/.bashrc.d/10-aethershell-theme.sh` était écrit mais jamais sourcé (Arch ne lit pas `~/.bashrc.d`). La ligne est posée une fois dans `~/.bashrc`, gardée par un marqueur.
- **Diffusion des couleurs dans les terminaux ouverts** : elle n'écrit plus dans un pty dont le premier plan n'est pas un shell (un programme plein écran voyait les séquences s'intercaler dans son flux), et publie le compte des ignorés.
- **`alacritty.toml` pouvait ne plus démarrer** : la clé `import` était insérée même quand la section `[general]` en portait déjà une, ce que TOML refuse. Le tableau est complété, un import multiligne n'est pas réécrit, et le résultat est validé par `tomllib` avant écriture.
- **Lanceur de terminal (exo / « Ouvrir un terminal ici »)** : le dossier est passé entre guillemets (mesuré : « Mes Docs » arrivait coupé en deux arguments sur foot et konsole) ; le gabarit printf de xterm — cassé par son apostrophe interne, le binaire ne recevait **aucun** argument — disparaît, xterm héritant du `cd`.

### Sécurité

Trois chemins permettaient à une donnée de commande de traverser une frontière de privilège ou de périmètre. Les trois sont fermés, et chacun est éprouvé par un cas concret.

- **Le greeter valide les identifiants avant le `rm -rf` en root** ([`dev/core/greeter_manager.py`](dev/core/greeter_manager.py)) : les noms de thème étaient interpolés entre apostrophes dans un script exécuté par `pkexec bash` — une apostrophe dans un nom suffisait à sortir des quotes et à faire exécuter autre chose, en root. `valider_identifiants()` refuse **la liste entière** (pas de filtrage silencieux) si un nom sort de `^[A-Za-z0-9._-]+$`, et les chemins du script généré passent par `shlex.quote`. Éprouvé : `x'; rm -rf /`, `../etc`, `a b` et `a'b` sont refusés, un nom normal passe.
- **L'extraction d'archive de thème est bornée** ([`dev/core/installer_theme_couleur.py`](dev/core/installer_theme_couleur.py)) : 256 Kio par schéma, 4 Mio au total, 64 schémas au plus, et la copie compte les octets réellement écrits — les tailles d'en-tête d'une archive peuvent mentir. Un `.colors` sans `[Colors:Window]` ni `[General]` est refusé, et tout refus est listé dans le champ `ignores` du résultat au lieu d'être filtré en silence. Six cas éprouvés : valides installés, gros, menteur, vide et surplus refusés avec motif.
- **Le worker todo ne traite que la liste du shell, et l'intitulé est une donnée** ([`dev/core/todo_worker.py`](dev/core/todo_worker.py), [`dev/core/todo_applet.py`](dev/core/todo_applet.py)) : `hermes -z "<titre>"` faisait d'un intitulé copié d'ailleurs une consigne pour un agent qui a le shell. Le périmètre est réduit au fichier nommé « shell » (refus explicite, avant toute prise en charge), et l'intitulé est encadré dans le prompt avec la mention qu'il décrit un travail sans le commander. Éprouvé : une demande venue du fichier homelab est refusée sans lancer Hermes, une demande du shell part avec l'encadrement.

## [0.1.4] — 2026-11-10

### Ajouté

- **Intégration universelle des couleurs du thème dans le terminal (`generate_terminal_theme.py`)** :
  - **Diffusion dynamique universelle par séquences d'échappement OSC** : émission directe sur tous les pseudo-terminaux actifs (`/dev/pts/*`) des séquences OSC 10 (texte), OSC 11 (arrière-plan avec respect du fond sombre/clair), OSC 12 (curseur), OSC 17/19 (sélection) et OSC 4 (palette complète des 16 couleurs ANSI dérivée du thème actif).
  - **Script d'initialisation shell persistant** : génération automatique de `~/.config/aethershell/terminal-colors.sh` sourcé à l'ouverture des nouveaux shells (`~/.bashrc.d/10-aethershell-theme.sh`).
  - **Profils natifs multi-terminaux synchronisés** : génération automatique des fichiers de configuration dédiés avec respect du flou et de l'opacité :
    - **Ghostty** : `~/.config/ghostty/themes/aethershell` et activation de `theme = aethershell` dans `user.conf`.
    - **Kitty** : `~/.config/kitty/aethershell-theme.conf` avec inclusion automatique dans `kitty.conf`.
    - **Alacritty** : `~/.config/alacritty/aethershell-theme.toml` avec import dynamique dans `alacritty.toml`.
    - **Foot** : `~/.config/foot/themes/aethershell.ini`.
  - Intégration dans [`dev/core/generate_rofi_theme.sh`](dev/core/generate_rofi_theme.sh) pour une mise à jour immédiate à chaque changement de fond d'écran ou sélection de palette.

- **Bouton d'installation de thèmes de couleurs téléchargés ([`dev/core/installer_theme_couleur.py`](dev/core/installer_theme_couleur.py))** :
  - **Bouton « Installer un thème »** dans le tiroir *Palettes & Thèmes* de [`dev/config_panel.qml`](dev/config_panel.qml).
  - Ouvre [`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml) configuré avec l'icône `palette` et filtre actif par défaut sur les extensions `.colors`.
  - **Bouton filtre débrayable** dans le sélecteur permettant de basculer en 1 clic entre le filtre `.colors` et l'affichage de tous les fichiers (archives `.zip`, `.tar.gz`, etc.).
  - Extraction et copie sécurisée dans `~/.local/share/color-schemes/` puis synchronisation immédiate du catalogue de thèmes via `themes_scan.py --sync`.
  - Ajout du glyphe `filter` (`\u{F0232}`) dans [`dev/Icon.qml`](dev/Icon.qml).

- **Réglage dédié des arrondis des sélecteurs modaux (`selecteur_radius`)** :
  - Ajout de la propriété réactive `selecteurRadius` dans [`dev/Theme.qml`](dev/Theme.qml) (0 = suit automatiquement `globalRadius`).
  - Prise en charge dans [`dev/core/config_manager.py`](dev/core/config_manager.py) et persistance dans `style_vars.json`.
  - Curseur « Arrondis sélecteurs » ajouté dans l'onglet *Gestion Quickshell* (tiroir *Barre et surfaces du shell*) de [`dev/config_panel.qml`](dev/config_panel.qml).

### Modifié

- **Harmonisation visuelle et flou des sélecteurs modaux ([`dev/SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml))** :
  - **Alignement des arrondis** : la courbure des fenêtres de sélecteurs suit désormais `Theme.globalRadius` par défaut au lieu d'une valeur fixe exagérée (`Theme.globalRadius * 3`).
  - **Flou de verre dépoli autonome (`FlouFond`)** : chaque carte modale bénéficie du flou interne du fond d'écran à courbure exacte (`FlouFond` avec intensité garantie ≥ 85 %), superposé avec un calque teinté `Theme.surfaceBg` et bordure contrastée.
  - Voile de fond sombre semi-transparent (`Qt.alpha(Theme.bg, 0.65)`) pour détacher la feuille modale du panneau hôte.

### Corrigé

- **Stabilité Qt Quick & Correction de crash (SIGSEGV)** :
  - Suppression du composant `ShaderEffectSource` ciblant un item ancêtre (`root.parent.parent`) dans `SelecteurFichier.qml` et `SelecteurDossier.qml`, éliminant les cycles d'invalidation dans le scene graph Qt 6 (`QQuickItemPrivate::addToDirtyList()`) survenus lors de la fermeture ou du changement d'état.
- **Gestion de la touche Échap et restauration du focus clavier** :
  - Ajout d'une méthode `annulerEtFermer()` fermant proprement le sélecteur, émettant `annule()` et rétablissant le focus clavier sur le champ de recherche `searchInput`.
  - Ajout d'un écouteur racine `Keys.onEscapePressed` dans [`dev/config_panel.qml`](dev/config_panel.qml) fermant en priorité le sélecteur actif s'il est ouvert, ou refermant le panneau de configuration en l'absence de modal.

## [0.1.3] — 2026-11-10

### Ajouté

- **Sélecteur de fichier graphique pour les fichiers Markdown suivis (onglet Données & Comptes)** :
  - **Bouton « Choisir »** dans le tiroir *Tâches — fichiers suivis* de [`dev/config_panel.qml`](dev/config_panel.qml), reprenant le design et l'ergonomie des sélecteurs de dossiers de fonds d'écran et de captures.
  - **Harmonisation visuelle des sélecteurs de dossiers** : ajout du glyphe `folder` sur les deux boutons « Choisir » du tiroir *Fonds d'écran & Captures* (onglet Apparence) pour une cohérence graphique parfaite dans tout le panneau.
  - **Feuille modale dédiée ([`dev/SelecteurFichier.qml`](dev/SelecteurFichier.qml))** : surface intégrée au panneau avec fond en verre et flou interne (`FlouFond`), navigation par dossier (`↑`), filtre automatique sur les extensions `.md` et `.markdown`, sélection par simple clic et validation par double-clic ou bouton « Choisir ».
  - **Script de lecture arborescente ([`dev/core/lister_fichiers.py`](dev/core/lister_fichiers.py))** : listing JSON rapide des dossiers et fichiers filtrés, ignorant les entrées cachées et gérant les erreurs d'accès de manière robuste.
  - **Remplissage automatique intelligent** : la sélection insère le chemin sous forme abrégée `~/...` et pré-remplit automatiquement le nom suggéré du fichier si le champ nom est vide.
  - **Glyphes dédiés dans [`dev/Icon.qml`](dev/Icon.qml)** : ajout des icônes `markdown` (`\u{F0354}`) et `file-document` (`\u{F0214}`).

- **Gestionnaire de déploiement — Sauvegarde fine granulaire & Moteur de pré-vol ([`dev/deploy.sh`](dev/deploy.sh))** :
  - **Moteur de pré-vol (`--diff` / `--dry-run`)** : analyse comparative exhaustive de l'arborescence du dépôt (`dev/`) par rapport à l'environnement vivant (`~/.config/hypr` et `~/.config/quickshell`).
  - Rapport catégorisé avec métriques claires : fichiers préservés (états locaux protégés : palettes, applets, secrets, binds, etc.), fichiers modifiés (avec comptage précis `+X / -Y` lignes), nouveaux fichiers, fichiers orphelins à élaguer, et fichiers générés post-déploiement.
  - Robustesse totale sous `set -euo pipefail` : isolation des sorties d'erreurs et des retours unitaires de comparaison.
  - **Snapshots fins granulaires décompressés** : création systématique à chaque déploiement d'un snapshot miroir navigable dans `~/.config/backups_env/snapshots/<horodatage>/` avec métadonnées (`manifest.json` : horodatage, distro, origine, commit git, nombre de fichiers) et table d'empreintes sha256 (`checksums.sha256`).
  - Rotation automatique synchronisée (`HQ_RETENTION=5`) assurant un historique maîtrisé.
  - **Restauration granulaire par fichier (`--restore-file <chemin> [snapshot]`)** : permet de restaurer un fichier unique précis depuis un snapshot vers le vivant, avec copie de sauvegarde préalable de la version écrasée.
  - **Déploiement direct sans sauvegarde (`deploy_only` / `--deploy-only` / `--no-backup`)** : ajout d'une fonction et d'une entrée dédiée dans le menu (option 2) pour déployer rapidement les mises à jour sans réitérer une sauvegarde quand l'environnement vivant a déjà été archivé.
  - **Commandes CLI directes et menu enrichi** : options `--diff`, `--dry-run`, `--backup`, `--deploy-only`, `--no-backup`, `--snapshots`, `--restore-file` et menu interactif enrichi pour lister, comparer, déployer ou restaurer à la carte.

- **Hermes — Surveillance et contrôle de la passerelle (Gateway & Daemon)** :
  - Intégration de la surveillance du service systemd utilisateur `hermes-gateway.service`, de l'état du démon (`~/.hermes/gateway_state.json`) et de la vivacité du PID.
  - Visualisation en direct du statut (actif/inactif, PID, profils desservis, version, âge du battement ticker).
  - Contrôle et relance rapide en 1-clic (`systemctl --user restart hermes-gateway.service`) depuis le popup de la barre supérieure ([`dev/HermesPopup.qml`](dev/HermesPopup.qml)) et le widget de bureau.
- **Hermes — Planifications et moteur Cron** :
  - Lecture et affichage des tâches cron planifiées (`~/.hermes/cron/jobs.json`) et du battement de cœur (`ticker_heartbeat`).
  - Actions rapides intégrées : déclenchement d'un passage manuel (`⚡ Tick` via `hermes cron tick`) et diagnostic d'intégrité (`🔍 Doctor` via `hermes cron doctor`).
- **Hermes — Widget de bureau enrichi, dépliable et scrollable ([`dev/widgets/hermes.qml`](dev/widgets/hermes.qml))** :
  - Vue compacte par défaut préservant l'espace du bureau (sessions récentes, jetons du jour, état global).
  - Bouton interactif « Détails & Actions ▾ » / « Replier ▴ » pour afficher à la demande le volet d'administration et de diagnostic.
  - Zone scrollable (`Flickable`) bornée à hauteur maximale avec ascenseur discret : le widget s'adapte sans jamais déborder du bureau et reste navigable à la molette.
  - Barre d'actions rapides : ouverture immédiate d'un terminal Ghostty dédié (`hermes`), relance de passerelle, tick cron et diagnostic doctor.
  - Journal en direct (tail sur les dernières lignes de `~/.hermes/logs/agent.log`) avec coloration contextuelle des statuts, avertissements et erreurs.

- **Aperçus du greeter SDDM isolés sur un bureau dédié (`workspace 99`)** :
  - Modification de [`dev/core/greeter_preview.sh`](dev/core/greeter_preview.sh) : mémorisation du bureau actif et bascule automatique sur le workspace 99 avant de lancer `sddm-greeter-qt6 --test-mode`.
  - Règle de fenêtre Hyprland dédiée dans [`dev/hypr_modular/windows.lua`](dev/hypr_modular/windows.lua) contraignant la fenêtre du greeter sur le workspace 99.
  - Restauration automatique du bureau de travail d'origine lors de la fermeture (appui sur `Échap`, expiration du délai de sécurité ou fermeture normale).
  - Protection absolue : en cas de blocage ou d'erreur dans un thème testé, le bureau de travail courant n'est jamais masqué ni immobilisé.

- **Minuterie de mise en veille automatique (Système & Écrans)** :
  - Ajout d'un réglage interactif par pilules dans l'onglet *Système & Écrans* (tiroir *Alimentation, Veille & Horloge*) de [`dev/config_panel.qml`](dev/config_panel.qml).
  - Délais configurables : 15 min, 30 min, **1 heure (par défaut)**, 2 heures, 3 heures, ou Jamais (désactivé).
  - Synchronisation immédiate avec la règle de suspension de [`dev/hypr_modular/hypridle.conf`](dev/hypr_modular/hypridle.conf) et `~/.config/hypr/hypridle.conf`.
  - Redémarrage à chaud automatique du démon utilisateur `hypridle.service` lors du clic.
  - Indexation dans le moteur de recherche interne du panneau (`searchIndex`) sous les termes « veille », « suspend », « inactivité », « sleep », « timer ».

- **Pont Todo ↔ Hermes & Interrupteur de surveillance des cases (Étape 1)** :
  - Ajout d'un interrupteur de surveillance dans le popup Tâches ([`dev/TodoPopup.qml`](dev/TodoPopup.qml)) et dans le panneau de configuration ([`dev/config_panel.qml`](dev/config_panel.qml)).
  - Persistance de l'option dans `core/todo.json` (`"surveillance": true/false`) et contrôle CLI via `todo_applet.py surveillance [on|off|toggle]`.
  - Conditionnement de la file d'attente : cocher une case alimente `todo-demandes.json` uniquement si la surveillance est activée. En mode désactivé, la coche reste une manipulation Markdown locale classique sans solliciter l'agent.
  - Implémentation du worker d'exécution [`dev/core/todo_worker.py`](dev/core/todo_worker.py) : prise en charge des demandes en attente, exécution automatique par Hermes (`hermes -z`), notifications bureau de début et fin, réécriture du Markdown en `✓ fait le <date>` en cas de succès ou alerte `⚠` en cas d'échec.
  - Indicateur visuel `⚡ hermes` dans le widget de bureau ([`dev/widgets/todo.qml`](dev/widgets/todo.qml)) signalant quand la surveillance est active.

## [0.1.2] — 2026-11-09

### Ajouté

- **Filtres de thèmes dans l'onglet Connexion (Installés / Non installés / Tous)** : ajout d'une barre
  de sélection par pilules au-dessus de la grille des miniatures permettant de filtrer la vue. Par défaut,
  seuls les thèmes installés sont affichés, masquant les thèmes désinstallés (qui restent dans le cache local) ;
  un clic sur « Non installés » ou « Tous » permet de les réafficher pour inspection ou réinstallation.
- **Désinstallation multi-thèmes SDDM dans le panneau (onglet Connexion)** : ajout de cases à cocher
  sur les vignettes des thèmes installés non-actifs (`qylock`), permettant une multi-sélection rapide
  avec bouton d'action contextuel « Désinstaller (N) » et bouton « Annuler ».
- **Action de désinstallation sécurisée (`greeter_manager.py uninstall`)** :
  - Support de la désinstallation par lot dans `dev/core/greeter_manager.py` et dans le helper
    privilégié `dev/sddm/greeter-palette`.
  - Protection absolue : interdiction stricte de désinstaller le thème de base Astronaut
    (`sddm-astronaut-theme`) ainsi que le thème SDDM actuellement actif.
  - Gestion de l'élévation Polkit avec mise à niveau automatique du helper pour les suppressions futures.
- **Bouton « Installer » pour les thèmes SDDM qylock dans le panneau** : lorsqu'un thème complet
  récupéré dans le cache local n'a pas encore été posé dans `/usr/share/sddm/themes`, l'onglet
  *Connexion* affiche désormais un bouton d'action dédié qui déclenche directement l'élévation
  `pkexec` via `greeter_manager.py install <id>` et bascule automatiquement sur « Appliquer » dès
  la pose terminée, sans devoir passer par le terminal.

### Corrigé

- **Visibilité et focus des invites Polkit au-dessus du panneau de configuration** :
  - Le panneau de configuration (`configOverlayWindow` dans [`dev/main.qml`](dev/main.qml))
    passe de la couche `WlrLayer.Overlay` avec `aboveWindows: true` à la couche `WlrLayer.Top`.
  - Masquage et restauration automatiques : lorsqu'une opération réclame une authentification Polkit
    (comme l'installation de thème), le panneau s'efface automatiquement après 180 ms pour laisser
    l'invite Polkit totalement visible, centrée et dégagée au premier plan. Dès la validation
    ou l'annulation de l'invite, le panneau réapparaît instantanément avec son message de statut à jour.
  - Les opérations sans mot de passe (comme la désinstallation via le helper mis à niveau)
    s'exécutent en moins de 180 ms sans clignotement du panneau.
- **Appel IPC Quickshell (`quickshell ipc -n`)** : les raccourcis (`SUPER + H` pour le panneau,
  `SUPER + R` pour le spotlight, `SUPER + K`, notifications) et scripts OSD/capture passent
  désormais le drapeau `-n` à l'IPC pour cibler l'instance active la plus récente, évitant de
  dialoguer avec une instance zombie ou en cours de fermeture.
- **Déploiement et redémarrage de session** : `deploy.sh` s'assure de tuer les processus
  Quickshell résiduels (`pkill -x quickshell`) avant de redémarrer le service systemd
  utilisateur, évitant l'accumulation d'instances concurrentes.
- **Panneau d'énergie & Luminosité sur portable** : l'applet `LuminositeApplet.qml` embarque
  directement son panneau complet (batterie, état, bascule du seuil de charge à 80 %,
  luminosité et identification de la machine hôte), réparant l'ouverture au clic sur les
  environnements où l'applet séparée `gestion-energie` n'est pas instanciée.
- **Limitation de charge batterie (80 %)** :
  - `system_service.py` détecte désormais dynamiquement toutes les batteries (`BAT*`, ex. `BAT1`
    sur Lenovo Yoga sous Fedora) au lieu du seul `BAT0`.
  - Prise en charge conjointe de `charge_control_end_threshold` et de `conservation_mode`
    (`ideapad_acpi`).
  - Élévation par `pkexec` pour l'écriture sysfs lorsque `sudo` sans mot de passe n'est pas
    disponible.
  - Fermeture automatique du popup (`Theme.activePopup = ""`) au clic pour libérer immédiatement
    l'écran lors de la demande d'authentification.
- **Agent Polkit sous Fedora & compatibilité Arch** :
  - Autostart mis à jour avec le chemin KDE 6 Fedora (`/usr/libexec/kf6/polkit-kde-authentication-agent-1`)
    en tête de recherche, assurant l'utilisation de l'agent KDE thémé (Breeze / `kdeglobals`) sur
    Fedora au lieu de l'agent brut LXQt.
  - Règle de fenêtre Hyprland élargie (`(?i).*(polkit|policykit).*`), fenêtre définie en
    flottante, centrée, épinglée (`pin = true`), avec focus forcé (`stay_focused = true`) et fond
    tamisé (`dim_around = true`).
  - Veilleur de focus `core/polkit_focus.py` étendu au motif `policykit`.
- **Flou de surface du panneau** : ajout du namespace `shell-config` dans `general.lua`
  pour garantir le flou d'arrière-plan sous le panneau de configuration.

## [0.1.1] — 2026-11-08

### Ajouté

- **Résumés d'état dans le panneau** : chaque tiroir replié montre, à droite de son titre,
  l'état des réglages qu'il contient — palette active, chemins des fonds, gaps et flou,
  opacité du shell, nombre d'applets, de widgets et de raccourcis, fuseau, NTP, mode nuit,
  disposition du clavier… Un onglet se lit d'un coup d'œil, sans rien déplier.
- **Sélecteur de dossier dans la surface du panneau** : le choix des dossiers Wallpapers et
  Screenshots est dessiné par le shell, avec son verre. Un dialogue Qt ouvrait une vraie
  fenêtre, recouverte par la surface de couche du panneau — donc inatteignable. Navigation,
  remontée au parent, entrées cachées écartées.
- **Cadenas de déplacement des widgets** (`widgets_locked`) : posé, le raccourci de
  placement (SUPER + SHIFT + clic) ne bouge plus rien, et un déplacement en cours est annulé
  sans écriture.
- **Bouton « Installer les paquets manquants »** (onglet *Apps & Alertes*) :
  `core/deps_install.py` lit `dependencies.txt` — désormais déployé avec le shell —, filtre
  la portée de la distribution, contrôle chaque binaire et élève par `pkexec`. Sans
  `pkexec`, il affiche la commande au lieu d'échouer en silence.

### Modifié

- Tiroir *Pilule de lancement* : respiration entre le choix de position et la ligne
  d'historique ; bouton « Vider » ramené à 0,8 de la taille du bouton voisin.
- `deploy.sh` copie `dependencies.txt` dans `core/` : le panneau n'a plus besoin de savoir
  où le dépôt a été cloné.

### En attente — présent dans le code, non livré

- Masque de profondeur rendu par un `MultiEffect` par widget : le code est en place
  (`layer.effect` dans `main.qml`, masque publié par `CalqueProfondeur.qml`, clé
  `widgets_multieffect` lue par `Theme`), mais le rendu n'est pas juste — alignement du
  masque et sens de l'inversion à reprendre. Désactivé, et sans bascule dans le panneau.

## [0.1.0] — 2026-11-08

Première version publiée. Un shell complet pour Hyprland 0.57 (configuration Lua) sous
Quickshell 0.3.2 : barre, barres annexes, panneau de réglages, widgets de bureau, launcher,
notifications, capture, et les services Python qui les alimentent.

### Ajouté

- **Barre principale en trois îlots dans une seule capsule**, avec espaces entre les îlots
  rendus transparents et sans flou ; barre du bas et deux barres latérales, où les applets
  s'empilent du bord extérieur vers l'intérieur.
- **Vingt applets et treize widgets de bureau.** Un widget se pose où on veut et se
  restreint à certains bureaux par un menu au clic milieu.
- **Panneau de configuration unique** : huit onglets, vingt-cinq tiroirs, index de recherche,
  réglages appliqués à chaud. Ouverture par la barre, par clic milieu sur un applet, ou par
  `quickshell ipc call shell toggleConfig`.
- **Pilule de lancement multi-modes** : index d'applications, alias, commandes shell (`>`),
  calculatrice locale (`=`), conversions d'unités (`~`), devises au taux BCE (`$`), émojis français (`;`),
  tueur de processus (`%`), presse-papiers (`"`), recherche de fichiers (`/`) et recherche de contenu
  (`:`, extraction PDF/DOCX/ODT avec cache RAM tmpfs déchiffré), avec volet d'aperçu latéral dynamique
  de 400 px.
- **Barres annexes et mode vertical complet** : ancrage directionnel des popups (`ancrePopupX/Y`),
  rendu vertical adapté sans texte tronqué (icônes agrandies ×1,45, date courte `06/11`, systray en grille
  verticale), flou Hyprland (`layer_rule`) appliqué aux barres du bas et latérales, et panneaux
  autonomes (`CalendrierPanneau.qml`, `MediaPanneau.qml`) rattachés à leur applet.
- **Composant `Defilement.qml`** : animation fluide en aller-retour avec temporisation aux extrémités
  pour les textes longs dans les applets (titres musicaux, etc.) sans coupure arbitraire.
- **Notifications** : centre, historique, et action au clic — la cible est figée à la
  réception, puis résolue par cascade (indication de l'émetteur → table par application →
  action native → chemin ou URL présent dans le texte → application émettrice). Fermeture par Échap
  et clic extérieur fiabilisé.
- **Services système & Confort** :
  - Applet `MajApplet.qml` multi-distribution (`pacman`/`yay` sur Arch, `dnf` sur Fedora).
  - Applet et widget Homelab (conteneurs Docker, unités systemd, pings parallèles, API Proxmox).
  - Mode nuit piloté par `hyprsunset` avec timer persistant dans `main.qml`.
  - Service Bluetooth non interactif via `bluetoothctl` avec bascule confirmée.
- **Systray maison** : menu rendu aux couleurs du shell depuis le DBusMenu (sous-menus
  compris) au lieu de la fenêtre interne de Quickshell ; double clic sur une icône met la
  fenêtre de l'application au premier plan, ou la lance si elle n'en a pas.
- **Capture d'écran et vidéo** : région ou écran entier, dans une barre dédiée.
- **Aide-mémoire des raccourcis**, généré depuis `binds.lua`.
- **Fonds d'écran en profondeur** : trois calques découpés dans une capture du compositeur,
  avec parallaxe au changement de bureau ; **masque de premier plan** (Depth Anything V2
  Small en ONNX, exécution locale) ; **flou interne** des surfaces du shell.
- **Onze variantes de flou de compositeur** réglables au panneau, avec le coût mesuré de
  chacune (acrylic ≈ 1,5 × kawase sous charge continue de flou).
- **Programmes par défaut du shell propagés au système** : `helpers.rc` d'exo, aides exo,
  `mimeapps.list`, `xdg-settings`, `kdeglobals`, `gsettings` — chaque couche écrite seulement
  si l'outil existe. Le lanceur de terminal traduit le dossier demandé par `exo` vers
  l'option du terminal et force une instance neuve.
- **Disques via udisks2**, y compris le cycle LUKS verrouiller / déverrouiller, avec la
  phrase passée par fichier temporaire et jamais en argument de commande.
- **Greeter SDDM** thémé depuis les réglages du shell, et **assistant de premier lancement**.
- **Déploiement et Sauvegardes HQ** (`dev/deploy.sh --arch | --fedora | --deps`) : menu interactif
  avec sauvegardes horodatées complètes (`hypr/` et `quickshell/`), rotation sur 5 versions,
  restauration sécurisée avec sauvegarde préalable automatique, et préservation des fichiers d'état
  (`style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `secrets.json`,
  `homelab.json`, `launch_history.json`) et modules Hyprland locaux (`input.lua`, `binds.lua`,
  `general.lua`).
- **Confidentialité structurelle du dépôt** : neutralisation totale des noms d'hôtes et chemins locaux
  dans le dépôt partagé (`hardware-arch.lua`, `hardware-fedora.lua`, détection par `/etc/os-release`
  et batterie).

### Modifié

- Panneau de configuration redistribué en huit onglets et vingt-cinq tiroirs ; listes et
  sections rassemblées par usage, greeter et pilule de lancement mis en tiroir.
- Schémas de couleurs KDE détectés et importés (63 sur une machine de test), deux formats
  d'écriture acceptés.
- Raccourcis regroupés en six rubriques dans `binds.lua`, sans changer une seule combinaison.
- Barre : teinte neutre qui assombrit sans décaler la couleur du thème.

### Corrigé

- **Isolation du singleton Theme (moteurs QML multiples)** : les `Loader` d'applets et de popups
  utilisent des chemins relatifs plutôt que des URL absolues `file://`, évitant la recompilation
  dans un second moteur QML et la scission du singleton `Theme`.
- **Alignement et positionnement des widgets** : cellules de texte vides remplacées par une espace
  dans `widgets/llm.qml` pour préserver le calcul de hauteur, et largeur dynamique liée à
  `implicitWidthChanged` dans `widgets/comptes.qml`.
- **Veilleur de focus Polkit & Disques** : `core/polkit_focus.py` lit le socket Hyprland actif
  le plus récent (`.socket2.sock`) à chaque tour pour survivre aux rechargements du compositeur.
- **Boucle de recherche du lanceur** : élimination du ré-appel cyclique de `build()` dans
  `spotlight.qml` lors de la réception des résultats asynchrones, stabilisant la capsule.
- Cache partiel de l'applet Système : toutes les mesures sont mises en cache, le filtre
  s'applique à la lecture (un appel filtré ne laissait auparavant que la mesure demandée).
- Compteur de tâches de la barre non rafraîchi après une coche.
- Verre de la barre et des cartes : découpe du fond au rapport de l'image décodée, plus de
  débord du flou hors de la surface, voile qui s'efface avec l'intensité.
- Surface du panneau floutée sur tout son pourtour par une règle de couche héritée.
- Menus GTK translucides mais **non floutés**, donc illisibles : `decoration:blur:popups`
  activé, les menus reçoivent le même flou que les surfaces du shell.
- Menu du systray figé à 0,92 d'opacité alors que le reste du shell suit `shellOpacity`.
- Lanceur de terminal qui ignorait le dossier demandé : le lanceur doit être dans le `PATH`,
  aucune aide exo du même nom, et le terminal ne doit pas réutiliser une instance ouverte.

### Retiré

- Veille planifiée qui cochait les étapes du fichier de tâches ; la coche est désormais
  manuelle ou faite à la demande.

[0.2.2]: https://github.com/onewheelamo/aethershell/releases/tag/v0.2.2
[0.2.1]: https://github.com/onewheelamo/aethershell/releases/tag/v0.2.1
[0.2.0]: https://github.com/onewheelamo/aethershell/releases/tag/v0.2.0
[0.1.5]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.5
[0.1.4]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.4
[0.1.3]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.3
[0.1.2]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.2
[0.1.1]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.1
[0.1.0]: https://github.com/onewheelamo/aethershell/releases/tag/v0.1.0
