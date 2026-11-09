# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), versionnage
sémantique. Tant que le format des fichiers de configuration (`style_vars.json`,
`bar_applets.json`, `widgets.json`) n'est pas figé, les versions restent en `0.x` : une
montée de mineure peut demander une adaptation des réglages.

## [0.1.3] — 2026-11-09

### Ajouté

- **Hermes — Surveillance et contrôle de la passerelle (Gateway & Daemon)** :
  - Intégration de la surveillance du service systemd utilisateur `hermes-gateway.service`, de l'état du démon (`~/.hermes/gateway_state.json`) et de la vivacité du PID.
  - Visualisation en direct du statut (actif/inactif, PID, profils desservis, version, âge du battement ticker).
  - Contrôle et relance rapide en 1-clic (`systemctl --user restart hermes-gateway.service`) depuis le popup de la barre supérieure ([`dev/HermesPopup.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/HermesPopup.qml)) et le widget de bureau.
- **Hermes — Planifications et moteur Cron** :
  - Lecture et affichage des tâches cron planifiées (`~/.hermes/cron/jobs.json`) et du battement de cœur (`ticker_heartbeat`).
  - Actions rapides intégrées : déclenchement d'un passage manuel (`⚡ Tick` via `hermes cron tick`) et diagnostic d'intégrité (`🔍 Doctor` via `hermes cron doctor`).
- **Hermes — Widget de bureau enrichi, dépliable et scrollable ([`dev/widgets/hermes.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/widgets/hermes.qml))** :
  - Vue compacte par défaut préservant l'espace du bureau (sessions récentes, jetons du jour, état global).
  - Bouton interactif « Détails & Actions ▾ » / « Replier ▴ » pour afficher à la demande le volet d'administration et de diagnostic.
  - Zone scrollable (`Flickable`) bornée à hauteur maximale avec ascenseur discret : le widget s'adapte sans jamais déborder du bureau et reste navigable à la molette.
  - Barre d'actions rapides : ouverture immédiate d'un terminal Ghostty dédié (`hermes`), relance de passerelle, tick cron et diagnostic doctor.
  - Journal en direct (tail sur les dernières lignes de `~/.hermes/logs/agent.log`) avec coloration contextuelle des statuts, avertissements et erreurs.

- **Aperçus du greeter SDDM isolés sur un bureau dédié (`workspace 99`)** :
  - Modification de [`dev/core/greeter_preview.sh`](file:///home/<utilisateur>/dev/quickshell_todo/dev/core/greeter_preview.sh) : mémorisation du bureau actif et bascule automatique sur le workspace 99 avant de lancer `sddm-greeter-qt6 --test-mode`.
  - Règle de fenêtre Hyprland dédiée dans [`dev/hypr_modular/windows.lua`](file:///home/<utilisateur>/dev/quickshell_todo/dev/hypr_modular/windows.lua) contraignant la fenêtre du greeter sur le workspace 99.
  - Restauration automatique du bureau de travail d'origine lors de la fermeture (appui sur `Échap`, expiration du délai de sécurité ou fermeture normale).
  - Protection absolue : en cas de blocage ou d'erreur dans un thème testé, le bureau de travail courant n'est jamais masqué ni immobilisé.

- **Minuterie de mise en veille automatique (Système & Écrans)** :
  - Ajout d'un réglage interactif par pilules dans l'onglet *Système & Écrans* (tiroir *Alimentation, Veille & Horloge*) de [`dev/config_panel.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/config_panel.qml).
  - Délais configurables : 15 min, 30 min, **1 heure (par défaut)**, 2 heures, 3 heures, ou Jamais (désactivé).
  - Synchronisation immédiate avec la règle de suspension de [`dev/hypr_modular/hypridle.conf`](file:///home/<utilisateur>/dev/quickshell_todo/dev/hypr_modular/hypridle.conf) et `~/.config/hypr/hypridle.conf`.
  - Redémarrage à chaud automatique du démon utilisateur `hypridle.service` lors du clic.
  - Indexation dans le moteur de recherche interne du panneau (`searchIndex`) sous les termes « veille », « suspend », « inactivité », « sleep », « timer ».

- **Pont Todo ↔ Hermes & Interrupteur de surveillance des cases (Étape 1)** :
  - Ajout d'un interrupteur de surveillance dans le popup Tâches ([`dev/TodoPopup.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/TodoPopup.qml)) et dans le panneau de configuration ([`dev/config_panel.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/config_panel.qml)).
  - Persistance de l'option dans `core/todo.json` (`"surveillance": true/false`) et contrôle CLI via `todo_applet.py surveillance [on|off|toggle]`.
  - Conditionnement de la file d'attente : cocher une case alimente `todo-demandes.json` uniquement si la surveillance est activée. En mode désactivé, la coche reste une manipulation Markdown locale classique sans solliciter l'agent.
  - Implémentation du worker d'exécution [`dev/core/todo_worker.py`](file:///home/<utilisateur>/dev/quickshell_todo/dev/core/todo_worker.py) : prise en charge des demandes en attente, exécution automatique par Hermes (`hermes -z`), notifications bureau de début et fin, réécriture du Markdown en `✓ fait le <date>` en cas de succès ou alerte `⚠` en cas d'échec.
  - Indicateur visuel `⚡ hermes` dans le widget de bureau ([`dev/widgets/todo.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/widgets/todo.qml)) signalant quand la surveillance est active.

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
  - Le panneau de configuration (`configOverlayWindow` dans [`dev/main.qml`](file:///home/<utilisateur>/dev/quickshell_todo/dev/main.qml))
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

[0.1.2]: https://github.com/onewheelamo/quickshell_todo/releases/tag/v0.1.2
[0.1.1]: https://github.com/onewheelamo/quickshell_todo/releases/tag/v0.1.1
[0.1.0]: https://github.com/onewheelamo/quickshell_todo/releases/tag/v0.1.0
