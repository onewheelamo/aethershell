# Reste à faire — état consolidé au 2026-11-04

Ce fichier remplace `fine_tune.md`, `TODO_panel_sections.md`,
`CLEANUP_PROPOSAL_2026-11-03.md`, `JOURNAL_2026-11-03_greeter.md`,
`dev/PROJECT_TODO.md`, `dev/POINT{4,9,11}_PROPOSAL.md` et les notes de cadrage
`*.txt` de la racine. Il ne garde que ce qui **n'est pas fait**.

Source de vérité du code : `dev/`. Le déploiement reste une étape séparée
(`dev/deploy.sh --station|--portable`) ; le greeter a son propre point d'entrée
(`dev/sddm/setup.sh`, voir `dev/sddm/GREETER_PROPOSAL.md`, conservé).

## 1. Ce qui est livré (vérifié dans le code le 04/11)

Îlots, capsule continue, workspaces, calendrier + NextCloud, systray/réseau,
notifications en cartes, OSD unique, spotlight (apps, alias, commandes,
historique), verrou hyprlock, panneau 620 px à onglets + `CollapsibleSection`
avec persistance `panel_sections`, `autostart.json` → `exec.lua`, flou shell
réglable, opacité shell séparée, écran de connexion SDDM (astronaut re-coloré
**et** 42 thèmes qylock, miniatures et panneau).

Réparations vérifiées, à ne pas rouvrir : helper `greeter-palette` installé et
seul (plus de `portable-greeter`), `pgrep -c hypridle` = 1 avec
`hl.dsp.dpms("off"/"on")` dans le dépôt **et** dans `~/.config/hypr`,
`hyprctl configerrors` vide, glyphes `⏻` remplacés par `Icon`, bind `Échap` +
`greeter_preview.sh stop` en place.

## 2. Points ouverts

### 2.1 Bloqué sur des assets — Depth wallpaper (fiche 7) — L

Fond en 2–3 calques avec parallaxe de 6–10 px au changement de workspace, les
îlots posés entre les calques. Fichiers : `dev/hyprquickpaper/shell.qml`,
`config.json` (mode `depth` dans le carrousel existant, un manifeste par image
décrivant les calques).

**Blocage réel** : il faut des wallpapers découpés en calques avec alpha. La
segmentation automatique est un autre projet. Ne pas commencer le QML avant
d'avoir choisi le format et deux images de test.

Décision du 04/11 : on n'y touche pas pour l'instant, ni le QML ni le mode
`depth` du carrousel.

### 2.2 Reporté par décision — Which-key par submap (fiche 10) — M

Overlay deux colonnes listant les binds du submap courant. Rien à coder tant que
les sous-cartes n'existent pas : `hyprctl binds -j` expose déjà `submap`,
`submap_universal` et `description`, donc **aucun parseur de `binds.lua` n'est
nécessaire**. Aujourd'hui 67 binds, tous dans la racine, aucun `description`.

Le coût est la taxonomie : quelles touches quittent la racine, comment on entre
et sort (Échap, expiration), remplir les `description`, et garder `SUPER + R` +
les workspaces via `submap_universal`.

### 2.3 En attente de décision — scripts hors périmètre (Tier 2)

`rotate.sh`, `sync_to_portable.sh`, `sync_to_station.sh` sont conservés et
protégés de l'élagage. À supprimer seulement sur décision explicite.

### 2.4 En stand-by — catégorisation des binds (onglet Contrôles)

Décision actée : pas de sous-catégories par univers pour l'instant ; l'onglet
reste tel quel. À reprendre seulement si les binds deviennent illisibles.

### 2.5 Idées en réserve, non commencées

- **Capsule à trois segments** : garder la capsule, rendre transparentes les
  deux zones de séparation (trois `Rectangle` partageant rayons et paddings,
  booléen `Theme.capsuleGaps` + largeur de coupe). Sans impact sur les îlots.
- **Variante `acrylic` du flou** : `decoration.blur.variant = "acrylic"`,
  `clarity 0.82`, `refraction 24`. Le variant est global — il change aussi le
  flou des fenêtres flottantes. À essayer seul, avec mesure GPU.
- **Flou Quickshell si l'opacité descend sous ~0,7** : `MultiEffect` en
  `layer.effect` sur chaque surface (barre, popups, panneau, OSD). QtQuick.Effects
  est déjà installé ; sans intérêt à l'opacité actuelle (0,85).
- **Aperçus du greeter sur un workspace dédié**, pour qu'un échec n'immobilise
  pas le workspace courant.

### 2.6 À valider sur portable — `dev/sddm/setup.sh`

Le script n'a été exercé qu'en `--check`, `--dry-run` (branches arch et fedora)
et exécution partielle sans root sur station. La branche Fedora réelle
(`sudo`, `dnf`, clone de l'astronaut, chemin `/etc/sddm.conf`) n'a jamais tourné :
portable n'est pas joignable en ssh depuis station. Premier lancement là-bas =
premier vrai test.

### 2.7 Confort, non prioritaire — bouton « Installer » dans le panneau

Un thème qylock récupéré mais pas encore posé s'affiche « (à installer) »,
l'application échoue et renvoie la commande à lancer. Aujourd'hui les 39 sont
posés, donc le cas est rare ; un bouton déclenchant
`install.sh --qylock` (une invite polkit) supprimerait l'aller-retour terminal.

## 3. Règle de travail à conserver

Ne jamais afficher une fenêtre plein écran qui prend le clavier sans porte de
sortie testée **avant** de l'afficher ; pour les essais, armer le tueur de PID
avant le lancement. (C'est ce qui a produit l'incident du 03/11 : aperçu du
greeter au focus, clavier avalé.)
