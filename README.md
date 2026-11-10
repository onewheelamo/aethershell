# AetherShell

Un environnement de bureau pour [Hyprland](https://hyprland.org), composé d'une barre en îlots, de panneaux modulaires, de widgets de bureau et d'outils du quotidien, écrit en QML/Qt et animé par [Quickshell](https://quickshell.org).

> **Note :** AetherShell n'a pas la prétention de réinventer la roue ni de s'imposer comme un standard. C'est simplement un environnement personnel parmi d'autres, encore jeune et en plein rodage (cycle `0.1.x`), conçu pour répondre à un flux de travail quotidien et s'ajuster au fil de l'expérience.

---

## 1. Vue d'ensemble

Plutôt qu'un simple thème de barre, AetherShell regroupe les éléments visuels et utilitaires de la session graphique :

* **Barre principale & capsule modulaire** : une disposition en trois îlots (gauche, centre, droite) logés dans une capsule commune. Les séparations entre les îlots peuvent être rendues transparentes pour laisser transparaître le fond d'écran net tout en maintenant un conteneur unifié.
* **Barres annexes optionnelles** : support d'une barre basse et de barres latérales verticales suivant la même logique de composants.
* **Panneau de configuration unifié** : accessible en un raccourci (`SUPER + H`) ou par clic milieu sur n'importe quel applet. Il permet d'ajuster l'apparence (palettes, flous, rayons, opacité), les applications préférées, les écrans, la minuterie de veille (`hypridle`), le démarrage automatique et les secrets locaux, avec application à chaud sans redémarrer la session.
* **Widgets de bureau ancrables** : des blocs déplaçables (tâches, surveillance système, météo, musique, horloge, agent...) configurables et filtrables par bureau virtuel (clic milieu pour restreindre un widget à un ou plusieurs workspaces).
* **Visualiseur audio réactif** : intégration discrète d'une onde PipeWire native (`pwscope`) ou de barres spectrales (`cava`), avec extinction automatique après dix secondes de silence pour préserver les ressources GPU/CPU.
* **Suivi de tâches & intégration Hermes** : gestion locale de checklists Markdown (`- [ ]`) avec sélecteur de fichiers graphique et interrupteur de surveillance optionnel confiant l'exécution des tâches cochées à l'agent Hermes via un worker d'arrière-plan.
* **Sélecteurs graphiques intégrés** : feuilles modales dessinées directement dans la surface du shell ([`SelecteurDossier.qml`](dev/SelecteurDossier.qml), [`SelecteurFichier.qml`](dev/SelecteurFichier.qml)), contournant la limitation des dialogues Wayland traditionnels qui s'ouvriraient sous la surface de couche (`Overlay`).
* **Gestionnaire d'écran de connexion (SDDM)** : réglage du thème Astronaut et de variantes Qylock depuis le panneau, avec un lanceur de prévisualisation sécurisé isolant le test sur un bureau dédié (`workspace 99`) pour ne jamais bloquer la session active.

---

## 2. Déploiement & Mises à jour

Le déploiement est piloté par le script [`dev/deploy.sh`](dev/deploy.sh), compatible avec **Arch Linux** et **Fedora** (détection automatique par `/etc/os-release`) :

```sh
cd dev

# Inspecter les dépendances nécessaires sans rien installer
./deploy.sh --deps

# Analyse comparative pré-vol (Dépôt ➜ Vivant) sans modification
./deploy.sh --diff

# Déploiement complet avec sauvegarde préalable (tarball + snapshot fin)
./deploy.sh --arch    # ou ./deploy.sh --fedora

# Déploiement rapide sans nouvelle sauvegarde (quand l'état est déjà archivé)
./deploy.sh --deploy-only
```

### Protection stricte des données locales
Le déploiement ne remplace jamais aveuglément les fichiers vivants :
* **États locaux protégés** : `style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `todo.json`, `secrets.json`, etc. ne sont jamais écrasés s'ils existent déjà sur la machine cible.
* **Configuration Hyprland personnalisée** : `binds.lua`, `input.lua`, `general.lua` et les profils matériels restent maîtres. En cas de différence avec le dépôt, une copie comparative `.upstream` est générée sans toucher au fichier actif.
* **Filet de sécurité granulaire** : chaque déploiement crée une archive `.tar.gz` de secours et un snapshot décompressé miroir sous `~/.config/backups_env/snapshots/<horodatage>/` avec table d'empreintes sha256 (`manifest.json`), permettant de restaurer un seul fichier en cas de besoin (`./deploy.sh --restore-file <chemin>`).

---

## 3. Prérequis

* **Compositeur** : [Hyprland](https://hyprland.org) 0.57 ou plus récent (configuration modulaire en Lua) ;
* **Moteur d'interface** : [Quickshell](https://quickshell.org) 0.3.2 ou supérieur ;
* **Police d'icônes** : `0xProto Nerd Font` (installeur fourni dans `dev/core/install_fonts.sh`) ;
* **Dépendances système** : répertoriées par distribution dans [`dev/dependencies.txt`](dev/dependencies.txt) (`rofi`, `matugen`, `wireplumber`, `NetworkManager`, `cava`, etc.).

---

## 4. Organisation du projet

```
dev/
├── core/             # Services Python (réseau, disques, tâches, Hermes, lister_fichiers...)
├── widgets/          # Composants de bureau (horloge, todo, système, météo...)
├── hypr_modular/     # Configuration Hyprland modulaire en Lua
├── hyprquickpaper/   # Moteur de fond d'écran et gestion de palette
├── sddm/             # Scripts et helpers pour l'écran de connexion SDDM
├── systemd/          # Définitions des unités utilisateur (quickshell.service...)
├── deploy.sh         # Gestionnaire de déploiement, pré-vol et sauvegardes
└── *.qml             # Surfaces Quickshell (barre, panneau, popups, sélecteurs...)
```

---

## 5. Remerciements & Emprunts de code

AetherShell n'est pas né dans le vide : il emprunte des briques, des concepts et des portions de code à d'autres projets open source dont les approches étaient pertinentes. Un grand merci aux auteurs suivants pour leur travail partagé sous licence libre (notamment la collection [Noctalia Community Plugins](https://github.com/noctalia-dev/community-plugins), sous licence MIT) :

| Composant / Idée | Auteur d'origine | Description du partage |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-dev/community-plugins/tree/main/visualizerp) | **al3x** | Moteur de capture PipeWire en C (`pwscope.c`), compilé localement pour alimenter l'onde audio. |
| [Agentik](https://github.com/noctalia-dev/community-plugins/tree/main/agentik) | **notfinaldev** | Principes de lecture non bloquante de l'état de l'agent, appariement processus/session et gestion du statut. |
| [USB Manager](https://github.com/noctalia-dev/community-plugins/tree/main/usb-manager) | **Marco Ziliani** | Architecture de lecture matérielle directe dans `sysfs` et `udev` sans nécessiter de démon résident lourd. |
| [To Do](https://github.com/noctalia-dev/community-plugins/tree/main/todo) | **nightwatch75** | Inspiration initiale pour le découplage entre l'applet de barre et le widget de bureau pour les listes de tâches. |
| [NVTOP](https://github.com/noctalia-dev/community-plugins/tree/main/nvtop) | **tordex** | Principe de surveillance système à la demande (processus lancé uniquement lorsque la vue est ouverte). |
| [Wallpaper Depth](https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth) | **noctalia** | Concept d'immersion visuelle des îlots via masques de profondeur (Depth Anything V2). |
| **Quickshell & Hyprland** | **outfoxxed & vaxerski** | Pour ces deux projets majeurs qui rendent possible la construction d'un shell Wayland moderne et performant. |

---

## 6. Licence

AetherShell est distribué sous licence MIT — voir le fichier [`LICENSE`](LICENSE) pour plus de détails.
