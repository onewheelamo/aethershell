# AetherShell

Un environnement de bureau pour Hyprland : une barre, des panneaux, des widgets de bureau
et un visualiseur audio, écrits en QML et exécutés par [Quickshell](https://quickshell.org).

AetherShell n'est pas un thème. C'est un shell complet — il remplace la barre par défaut de
Hyprland et regroupe ce qu'on consulte en permanence : bureaux, horloge, réseau, volume,
batterie, disques, services, presse-papiers, agent Hermes, homelab. Le tout se règle depuis
un panneau unique, et les réglages s'appliquent à chaud.

## Le shell

### Une barre en trois îlots, dans une seule capsule

Les applets sont répartis en trois îlots — gauche, centre, droite — peints dans une capsule
continue. Les deux espaces qui les séparent peuvent être rendus **transparents, sans flou** :
le fond d'écran reste net entre les îlots. Ce n'est pas un retour à trois pilules
indépendantes : la découpe est une option de peinture, les espaces restent des objets à part
entière, et c'est là que s'affiche le visualiseur audio.

### Des barres annexes

La même découpe s'applique à une barre du bas et à deux barres latérales, chacune avec ses
applets, ses zones et ses espaces transparents. Sur les côtés, les applets s'empilent du bord
extérieur vers l'intérieur.

### Vingt applets, treize widgets

Un applet vit dans une barre ; un widget vit sur le bureau, posé où on veut, et peut être
restreint à certains bureaux (un seul, plusieurs, ou tous) par un menu au clic milieu.
L'applet Hermes et son widget lisent tous deux la base de l'agent pour dire ce qu'il fait,
dans quel profil, avec quelle consommation.

Panneaux, launcher, notifications, OSD, sélecteur de capture et aide-mémoire des raccourcis
complètent l'ensemble, tous soumis au même réglage de flou.

### Un visualiseur audio

Deux modes : une onde (moteur `pwscope`, capture PipeWire) ou des barres de spectre (cava).
Il s'éteint après dix secondes de silence et se réveille à la première source audio, plutôt
que de capturer en permanence.

## Prérequis

- [Quickshell](https://quickshell.org) 0.3.2 ou plus récent ;
- Hyprland 0.57, configuration en Lua (les modules sont dans `dev/hypr_modular/`) ;
- les binaires listés dans [`dev/dependencies.txt`](dev/dependencies.txt), avec leurs
  portées : `#: commun`, `#: arch`, `#: fedora`.

## Installation

```sh
cd dev
./deploy.sh --deps      # liste résolue des dépendances, sans rien installer
./deploy.sh --arch      # ou --fedora
```

La cible se déduit de `/etc/os-release` ; le drapeau ne sert qu'à la forcer. Le déploiement
copie le shell vers `~/.config/quickshell` et la configuration Hyprland vers `~/.config/hypr`,
après une sauvegarde dans `~/.config/backups_env`.

Deux familles de fichiers ne sont **jamais** écrasées : les réglages et les données
(`style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `secrets.json`…) et
les modules Hyprland qu'on édite à la main (`input.lua`, `binds.lua`, `general.lua`). Le
fichier vivant fait foi ; le dépôt propose une version de départ.

## Configuration

Le panneau s'ouvre par la barre ou par IPC :

```sh
quickshell ipc call shell toggleConfig
```

Un clic milieu sur un applet ouvre directement sa section. Les réglages sont écrits dans
`~/.config/quickshell/core/` :

| Fichier | Ce qu'il porte |
|---|---|
| `style_vars.json` | couleurs, rayons, opacité et flou, transparence des espaces |
| `bar_applets.json` | quels applets, dans quelle barre, à quelle place |
| `widgets.json` | widgets de bureau : position, taille, bureaux |
| `applets_catalogue.json` | le catalogue : ce qui existe, et dans quelles îles c'est permis |

## Structure du dépôt

```
dev/                le shell (QML) et ses services
  core/             services Python : réseau, disques, énergie, Hermes, visualiseur…
  widgets/          les widgets de bureau
  hypr_modular/     la configuration Hyprland, en modules Lua
  sddm/             le greeter
  deploy.sh         déploiement et contrôle des dépendances
```

## Inspirations

AetherShell a été écrit en regardant d'autres shells, et en reprenant franchement ce qu'ils
faisaient mieux. Les plugins ci-dessous viennent de la collection communautaire de
[Noctalia](https://github.com/noctalia-dev/community-plugins) ; ils sont tous sous licence
MIT, et tout code repris garde son en-tête de provenance d'origine.

| Plugin | Auteur | Ce qui en vient |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-dev/community-plugins/tree/main/visualizerp) | al3x | le moteur de capture `pwscope.c`, **repris tel quel** (compilé localement) ; le rendu QML est réécrit |
| [Agentik](https://github.com/noctalia-dev/community-plugins/tree/main/agentik) | notfinaldev | la lecture de la base de l'agent en lecture seule, l'appariement processus ↔ session, la règle « statut inconnu plutôt qu'inventé » |
| [USB Manager](https://github.com/noctalia-dev/community-plugins/tree/main/usb-manager) | Marco Ziliani | le duo applet/widget qui lit l'état dans sysfs et udev, sans processus de fond |
| [To Do](https://github.com/noctalia-dev/community-plugins/tree/main/todo) | nightwatch75 | le duo applet/widget pour une liste de tâches priorisée |
| [NVTOP](https://github.com/noctalia-dev/community-plugins/tree/main/nvtop) | tordex | les idées du duo de surveillance système : tri par colonne, outil lancé seulement quand le panneau est ouvert |
| [Wallpaper Depth](https://github.com/noctalia-dev/official-plugins/tree/main/wallpaper_depth) | noctalia | l'idée du masque de premier plan tiré d'une carte de profondeur (Depth Anything V2 Small, Apache-2.0), pour faire passer les widgets derrière le décor proche ; le service et le calque sont réécrits pour AetherShell |

Les idées, les dispositions et les protocoles ne s'héritent pas ; les remerciements, si.

## Licence

AetherShell est distribué sous licence MIT — voir [`LICENSE`](LICENSE).
