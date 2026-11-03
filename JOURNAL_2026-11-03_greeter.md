# Journal de session — panneau « Connexion » (greeter) — 2026-11-03

Écrit à 23:33 CET, après blocage de la session graphique vers 23:04 et passage
par le tty3. Destiné à être analysé dans une nouvelle session : le contexte de
l'agent a été compacté cinq fois, l'historique exact des commandes est donc
partiellement perdu et ce fichier est la version de référence.

---

## 1. Résumé exécutif

- Fonctionnalité livrée et vérifiée : cinquième catégorie « Connexion » dans le
  panneau de réglages, grille de miniatures du greeter, aperçu plein écran au
  clic, application du thème via un helper polkit (sans mot de passe).
- Trois commits : `33d7c79` (panneau), `f65313e` (renommage), `3b2dc20` (sortie
  d'aperçu par Échap). Le dépôt est propre (`git status` vide).
- Le blocage est très probablement dû à **un aperçu plein écran du greeter
  laissé à l'écran** (fenêtre plein écran qui prend le clavier, sans moyen de
  sortie à ce moment-là) : c'est exactement ce que `3b2dc20` corrige après coup.
- Deux régressions restent ouvertes à l'instant de ce journal :
  **« Appliquer » est cassé** (helper renommé dans le dépôt, pas réinstallé sur
  le système) et **`hypridle` tourne en 10 exemplaires** avec une syntaxe DPMS
  invalide dans `~/.config/hypr/hypridle.conf`. Détails § 6.

---

## 2. Chronologie

Heure locale (CET), même jour.

| heure  | fait |
|--------|------|
| 22:14  | session graphique en cours (tty1, Hyprland PID 3200) |
| 22:32  | `7acbf69` maquette du greeter, architecture du thème |
| 22:38  | `a2098c3` thème sddm-astronaut recoloré depuis la palette Matugen |
| 22:44  | helper privilégié installé : `/usr/local/bin/portable-greeter` + règle polkit `50-portable-greeter.rules` (à cette date) |
| ~22:50–23:03 | développement de l'onglet Connexion, puis essais de bout en bout (voir § 4) |
| 23:03  | `33d7c79` commit du panneau ; `pkexec … apply portable` OK sans mot de passe |
| **23:04** | **blocage : l'utilisateur bascule sur le tty3** |
| 23:04:34–23:04:39 | journal : `sddm-greeter-qt6[718245]` lit `/usr/share/wayland-sessions/hyprland-uwsm.desktop`, erreurs `QLocalSocket: device not open` (mode test) |
| 23:04:55 | démarrage d'un `uwsm_hyprland.desktop[718452]` — session 5 sur tty3 |
| 23:05:10 | `sddm-greeter-qt6[718245]` reçoit `SIGTERM` (tué par le script de test) |
| 23:06:52 | un dixième `hypridle` apparaît (voir § 6.2) |
| 23:12:24 | Quickshell relancé (PID 724502, toujours vivant à 23:33) |
| 23:12:55 | `f65313e` renommage « hors du nom d'hôte » : `portable-*` → `shell-*`, `portable-greeter` → `greeter-palette` |
| 23:19:59 | `3b2dc20` sortie d'aperçu par Échap + `core/greeter_preview.sh` |
| 23:33  | ce journal |

---

## 3. Ce qui a été livré

### Panneau

- `dev/config_panel.qml` : cinquième onglet (icône cadenas) dans le rail,
  propriété `root.greeterSelected`, entrée d'index de recherche
  « Thème de l'écran de connexion » (mots : connexion, greeter, sddm, login).
- `dev/GreeterTab.qml` (nouveau, ~340 lignes) : grille 3 colonnes de
  miniatures, état (actif ✓ / sélection), boutons « Appliquer », « Aperçu plein
  écran », « Aperçus » (régénération), ligne d'état.
- `dev/qmldir` : `GreeterTab` déclaré ; `dev/deploy.sh` copie le fichier et
  `dev/core/` est déjà synchronisé par `copy_dir_files`.

### Backend

- `dev/core/greeter_manager.py` : `list`, `preview <id>`, `apply <id>`,
  `refresh`, `thumbnails [ids…]`, tout en JSON sur stdout.
  `preview` copie le thème dans `/var/tmp/greeter-preview-*`, y injecte un
  gestionnaire Échap (`inject_preview_escape`), lance
  `core/greeter_preview.sh` et laisse la copie être supprimée à la sortie.
- `dev/core/greeter_preview.sh` : `start <dossier-thème> [secondes]` /
  `stop`. Lance `sddm-greeter-qt6 --test-mode --theme <dir>`, enregistre le PID
  dans `$XDG_RUNTIME_DIR/quickshell-session/greeter-preview.pid`, tue au bout
  du délai (45 s par défaut), et `stop` ne tue que si `/proc/<pid>/comm` vaut
  encore `sddm-greeter-qt` (protection contre le recyclage de PID).
- `dev/sddm/` : `greeter-palette` (helper root), `50-greeter-palette.rules`
  (polkit), `thumbnails.sh`, `generate.py`, `install.sh`.
- `dev/hypr_modular/binds.lua` : `Échap` → `greeter_preview.sh stop`, en
  `non_consuming` (Échap continue d'atteindre les autres applications).

### Comportement

- Clic sur une miniature : sélection + aperçu plein écran (le panneau se
  ferme). Sortie : Échap, ou 45 s, ou SUPER + Q.
- « Appliquer » écrit `ConfigFile=Themes/<id>.conf` dans
  `/usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop` via le helper
  root autorisé par polkit — pas de mot de passe.
- Miniatures : `~/.cache/quickshell/greeter-thumbs/*.png`, 11 fichiers.

---

## 4. Vérifications réellement effectuées (avant le blocage)

Commandes et résultats mesurés, pas des intentions :

```
qmllint dev/GreeterTab.qml dev/config_panel.qml        → 0 ligne (silencieux)
pgrep -xc quickshell                                   → 1
hyprctl layers | grep -c shell-bar                     → 1
hyprctl configerrors                                   → (vide à ce moment-là)
diff -q dev/<f> ~/.config/quickshell/<f>               → identiques (GreeterTab,
   config_panel, main, Theme, core/greeter_manager.py, core/greeter_preview.sh)
```

Essai de bout en bout du parcours réel, par injections `/dev/uinput`
(clics/typages réels) :

```
ouverture du panneau + recherche « connexion »     → onglet 4 affiché
clic vignette Astronaut                            → aperçu plein écran ouvert
                                                     (1 fenêtre « greeter »)
fermeture de l'aperçu par PID                      → 0 fenêtre
réouverture du panneau, clic « Appliquer »         → ConfigFile=Themes/astronaut.conf
message d'état                                     → « Appliqué : Astronaut »
retour au thème d'origine                          → ConfigFile=Themes/portable.conf
pkexec /usr/local/bin/portable-greeter apply portable  → « appliqué : portable » (sans mot de passe)
```

Deux bugs trouvés et corrigés pendant ces essais :

1. `Quickshell.Process` dont la `command` est construite à l'exécution ne
   démarre pas (constaté sur l'aperçu **et** sur l'application) → passage à
   `Quickshell.execDetached`, puis relecture de l'état disque pour conclure.
2. La sélection était perdue à la fermeture du panneau (le composant de
   l'onglet est déchargé quand on le quitte) → la sélection vit désormais sur
   la racine du panneau (`root.greeterSelected`).

---

## 5. L'incident de 23:04 — ce que je sais, ce que je suppose

### Fait avéré

- Mes essais automatiques ouvraient et fermaient en boucle des **aperçus
  plein écran du greeter** (fenêtre `sddm-greeter-qt6 --test-mode`, plein
  écran, qui prend le clavier et affiche un écran de connexion identique au
  vrai).
- À ce moment-là, **aucun moyen de sortie n'existait** : pas de bind Échap
  (ajouté seulement à 23:19), aucun bouton dans la fenêtre, et le mode test
  n'obéit pas à `Qt.quit()` (mesuré : le QML s'exécute, le processus reste).
  La seule sortie était de tuer le PID depuis un terminal.
- Le journal montre la fenêtre `sddm-greeter-qt6[718245]` active à 23:04:34,
  puis un `uwsm_hyprland` démarré à 23:04:55 : l'utilisateur a ouvert une
  session sur le tty3 à ce moment.
- Mes scripts d'automatisation tapaient et cliquaient pour de vrai
  (`/dev/uinput`) : les frappes partaient vers la fenêtre qui avait le focus,
  donc potentiellement dans l'écran de connexion factice.

### Hypothèse principale

Un aperçu plein écran est resté à l'écran. L'écran de connexion factice
absorbait le clavier, ne se fermait pas, et rendait la session inutilisable
dans la pratique (impossible d'atteindre un terminal pour tuer le processus).
D'où le tty3. Cette lecture est cohérente avec le correctif ajouté juste
après (`3b2dc20` : Échap, bandeau d'indication, délai de 45 s, `stop`).

### Hypothèses secondaires (à ne pas écarter)

- **`hypridle` en 10 exemplaires** (§ 6.2) : dix écouteurs de 300 s (DPMS) et
  7200 s (suspend) ; un écran éteint avec reprise cassée donne exactement le
  même symptôme.
- **Redémarrages répétés de Quickshell** pendant mes essais (`kill` par PID +
  relance) : la barre et les surfaces layer disparaissent puis reviennent, et
  le focus clavier est bousculé.
- Rien dans le journal ne montre de crash de Hyprland, d'OOM ni de segfault
  entre 22:55 et 23:15 ; Hyprland (PID 3200, démarré 22:14) a survécu.

### Ce que je ne peux pas prouver

Je n'ai pas de trace de la fenêtre qui avait le focus à 23:04 ni du moment
exact où l'utilisateur a constaté le blocage : le journal ne consigne pas les
changements de focus. L'hypothèse principale repose sur la chronologie des
aperçus et sur le fait que le correctif d'après-incident traite précisément ce
cas.

---

## 6. Régressions ouvertes à 23:33 (mesurées)

### 6.1 « Appliquer » est cassé — le helper renommé n'est pas installé

Le commit `f65313e` a renommé le helper `portable-greeter` → `greeter-palette`
dans le dépôt, mais l'installation système n'a pas été refaite :

```
python3 dev/core/greeter_manager.py apply portable
{"ok": false, "error": "sélection refusée : Error accessing
 /usr/local/bin/greeter-palette: No such file or directory"}

ls -l /usr/local/bin/greeter-palette   → absent
ls -l /usr/local/bin/portable-greeter    → présent (root, 2736 o, 22:44)
pkexec ls /etc/polkit-1/rules.d/       → 50-portable-greeter.rules
                                         99-suspend-ignore-inhibit.rules
```

`list` renvoie d'ailleurs `"helper": false`. Le panneau affiche donc un bouton
« Appliquer » qui échoue.

Piste de correction : réinstaller via `dev/sddm/install.sh` (qui installe
`greeter-palette` + `50-greeter-palette.rules`), puis retirer l'ancien couple
`portable-greeter` / `50-portable-greeter.rules` pour ne pas laisser deux règles
polkit. À valider avant : `install.sh` doit être idempotent et sauvegarder
`metadata.desktop` (il le fait, `$BACKUP`).

### 6.2 Dix `hypridle` et une syntaxe DPMS invalide

```
pgrep -c hypridle → 10   (démarrés de 22:38:27 à 23:06:52, tous enfants de
                          systemd --user, PID 1075)

hyprctl configerrors
→ return hl.dispatch("dpms", "on");:1: hl.dispatch: expected a dispatcher
  (e.g. hl.dsp.window.close()) or a lua function

~/.config/hypr/hypridle.conf:9   on-timeout = hyprctl eval 'hl.dispatch("dpms","off")'
~/.config/hypr/hypridle.conf:10  on-resume  = hyprctl eval 'hl.dispatch("dpms","on")'
```

La forme valide en 0.57 est `hl.dsp.dpms("off")` / `hl.dsp.dpms("on")`
(vérifié : `hyprctl eval 'hl.dsp.dpms("on")'` → `ok`).

Conséquences : les commandes DPMS échouent silencieusement, et dix instances
cumulent des minuteurs de veille (300 s) et de suspension (7200 s). Le
10e processus est apparu à 23:06:52, pendant la période troublée.

Non corrigé ici volontairement : ce journal sert à analyser l'état tel qu'il
était, et modifier `hypridle.conf` demande de savoir qui relance `hypridle`
(autostart ou service) pour éviter un onzième exemplaire.

### 6.3 Divers

- Le nom d'hôte reste `portable`/`station` dans les anciens chemins ; les
  namespaces layer sont maintenant `shell-bar` et `shell-spotlight-rest`.
- Fichiers de log Quickshell laissés dans `/tmp/qs_h1..h4.log` (dont un
  `INFO: Reloading configuration`, sans erreur).
- Scripts d'automatisation d'essai dans
  `~/.hermes/profiles/ricer/cache/scratch` : `uinput_*.py`, `detect_accent.py`,
  `e2e_greeter.sh`, `kill_greeter.py`, `count_greeter.py`. Ils pilotent de
  vrais clics/frappes via `/dev/uinput` — c'est ce qui a rendu les essais
  « réels », et c'est aussi ce qui a pu frapper dans la fenêtre au focus.

---

## 7. État mesuré à 23:33

```
quickshell                     1 instance (PID 724502, démarré 23:12)
couches layer                  shell-bar, shell-spotlight-rest
aperçu greeter                 aucun processus, aucun /var/tmp/greeter-preview-*
thème actif                    ConfigFile=Themes/portable.conf
miniatures                     11 fichiers
git                            propre ; dernier commit 3b2dc20
dev ↔ prod                     identiques sur les 6 fichiers contrôlés
sessions                       tty1 (session 3, depuis le 2/11 22:14)
                               tty3 (session 5, 23:04)
mémoire                        46 Gio dont 13 utilisés, pas de pression
```

---

## 8. À reprendre en priorité (dans cet ordre)

1. **Réparer « Appliquer »** : installer `greeter-palette` + sa règle polkit,
   retirer l'ancien helper, revérifier
   `python3 dev/core/greeter_manager.py apply <id>` → `{"ok": true}`.
2. **Nettoyer `hypridle`** : tuer les 9 instances excédentaires, corriger
   `hl.dispatch` → `hl.dsp.dpms`, puis vérifier `hyprctl configerrors` vide et
   `pgrep -c hypridle` = 1.
3. **Sécuriser l'aperçu** davantage : le bind Échap existe, mais il est global
   et `non_consuming`. Vérifier qu'il referme bien l'aperçu quand le panneau
   est fermé et que Quickshell n'a pas le focus ; sinon ajouter une ceinture
   côté shell (délai plus court, ou `stop` automatique à l'expiration, déjà
   présent).
4. **Règle de travail** : ne plus jamais laisser une fenêtre plein écran qui
   prend le clavier sans porte de sortie testée *avant* de l'afficher ; pour
   les essais, armer le tueur de PID avant le lancement.
5. Envisager de tester les aperçus sur un workspace dédié, pour qu'un échec
   n'immobilise pas le workspace courant.

---

## 10. Réparations apportées le 2026-11-03 à 23:37–23:45 (après rédaction de ce journal)

Les deux régressions du § 6 ont été réparées et revérifiées, sur demande.

### 10.1 Helper du greeter (était cassé)

`bash dev/sddm/install.sh` : la migration de nomenclature a été achevée.

```
/usr/local/bin/greeter-palette            installé (root, 2753 o)
/usr/local/bin/portable-greeter             retiré
/etc/polkit-1/rules.d/50-greeter-palette.rules   installé
/etc/polkit-1/rules.d/50-portable-greeter.rules    retiré
/usr/share/sddm/themes/sddm-astronaut-theme/Themes/palette.conf   installé
/.../Themes/portable.conf                   retiré
/etc/sddm.conf.d/10-sddm-theme.conf       [Theme] Current=sddm-astronaut-theme
metadata.desktop                          ConfigFile=Themes/palette.conf
```

Vérifications :

```
python3 dev/core/greeter_manager.py list        → helper=True, actif=palette
python3 dev/core/greeter_manager.py apply astronaut → {"ok": true, ...}
python3 dev/core/greeter_manager.py apply palette   → {"ok": true, ...}
```

Bug trouvé au passage dans `dev/sddm/install.sh` (corrigé) : la ligne `rm -f`
supprimait `/etc/sddm.conf.d/10-portable.conf` **avant** la boucle de sauvegarde
qui avait déjà mis ce fichier dans son glob ; le `cp -n` échouait alors et
`set -e` interrompait l'installation juste avant l'écriture de
`10-sddm-theme.conf` (SDDM se retrouvait sans `Current=`). Le `rm` est
désormais émis après la boucle, et la sauvegarde tolère un fichier disparu.
Le script se termine maintenant en code 0 et rejouable.

À noter : la miniature de « Palette de la session » est vide (« Aperçu à
générer ») — elle n'a pas été régénérée, car `dev/sddm/thumbnails.sh` prend
l'écran quelques secondes par thème. Le bouton « Aperçus » du panneau le fait
quand l'utilisateur le décide.

### 10.2 hypridle (était en 10 exemplaires + DPMS invalide)

```
~/.config/hypr/hypridle.conf   hl.dispatch("dpms", …) → hl.dsp.dpms(…)
                                (sauvegarde : ~/.config/backups_env/hypridle.conf.bak)
hypridle                       1 seule instance, unité systemd active et activée
                               (systemctl --user enable --now hypridle)
autostart                       ~/.config/quickshell/core/autostart.json et
                                autostart_cmds.txt : la ligne « pgrep || exec »
                                devient « systemctl --user start hypridle »
                                (idempotent ; c'est le « pgrep » introuvable dans
                                l'environnement d'autostart qui créait les doublons)
hyprctl configerrors            vide
hyprctl eval 'hl.dsp.dpms("off")' puis ("on")  → aller-retour vérifié
```

---

## 11. Commandes utiles pour la session d'analyse

```bash
cd /home/utilisateur/dev/quickshell_todo
git log --oneline -6
git show --stat 33d7c79 f65313e 3b2dc20
python3 dev/core/greeter_manager.py list | head -c 400
python3 dev/core/greeter_manager.py apply palette        # doit réussir maintenant
pgrep -a -x hypridle | wc -l                             # doit valoir 1
hyprctl configerrors
journalctl -b --since "22:55" --until "23:15" | grep -iE "sddm|greeter|hyprland"
```

Fichiers à lire : `dev/GreeterTab.qml`, `dev/config_panel.qml` (autour de
l'onglet 4 et de `greeterSelected`), `dev/core/greeter_manager.py`,
`dev/core/greeter_preview.sh`, `dev/sddm/install.sh`,
`dev/hypr_modular/binds.lua`.
