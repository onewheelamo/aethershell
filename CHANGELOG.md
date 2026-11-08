# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), versionnage
sémantique. Tant que le format des fichiers de configuration (`style_vars.json`,
`bar_applets.json`, `widgets.json`) n'est pas figé, les versions restent en `0.x` : une
montée de mineure peut demander une adaptation des réglages.

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
- **Pilule de lancement** (applications, presse-papiers, fichiers, commandes, historique).
- **Notifications** : centre, historique, et action au clic — la cible est figée à la
  réception, puis résolue par cascade (indication de l'émetteur → table par application →
  action native → chemin ou URL présent dans le texte → application émettrice).
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
- **Déploiement** `dev/deploy.sh --arch | --fedora | --deps` : sauvegarde préalable, et
  fichiers d'état (`style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`,
  `secrets.json`) ou modules Hyprland édités à la main (`input.lua`, `binds.lua`,
  `general.lua`) jamais écrasés.

### Modifié

- Panneau de configuration redistribué en huit onglets et vingt-cinq tiroirs ; listes et
  sections rassemblées par usage, greeter et pilule de lancement mis en tiroir.
- Schémas de couleurs KDE détectés et importés (63 sur une machine de test), deux formats
  d'écriture acceptés.
- Raccourcis regroupés en six rubriques dans `binds.lua`, sans changer une seule combinaison.
- Barre : teinte neutre qui assombrit sans décaler la couleur du thème.

### Corrigé

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

[0.1.1]: https://github.com/onewheelamo/quickshell_todo/releases/tag/v0.1.1
[0.1.0]: https://github.com/onewheelamo/quickshell_todo/releases/tag/v0.1.0
