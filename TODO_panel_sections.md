# TODO — Refonte du panneau de configuration en catégories dépliables

Statut : EN ATTENTE — bloquée sur le retour de la commande `quickshell`
(fichiers dev modifiés récemment : blur réglable + OSD — bugs à corriger avant toute évolutions UI)

## Objectif général
Remplacer les blocs plats de chaque onglet par des catégories collapsibles :
en-tête cliquable (titre + flèche ▼/▶) qui masque/déplie le contenu.
Décisions actées :
- A. swatches hex custom -> catégorie "Thème"
- B. hauteur de barre + bouton config -> catégorie "Aspect technique"
- C. toutes les catégories FERMÉES par défaut (évite l'effet "c'est tout ce qu'il y a")
- D. catégorisation des binds (onglet Contrôles) : EN STAND BY, pas dans ce chantier

## Décision actée — blur
Le réglage blur du panneau s'applique à toutes les fenêtres Hyprland via
`hyprctl eval hl.config({ decoration.blur = ... })` : toute fenêtre transparente
(opacité 0.85) laisse voir le flou. Les fenêtres à opacité 1.0 ne sont pas
concernées (rien à flouter derrière). Les îlots Quickshell gardent une simple
transparence 0.85 (le blur Hyprland ne s'applique pas aux couches layer-shell ;
un MultiEffect serait à peine visible à cette opacité).

## Évolution future — blur aussi sur les éléments Quickshell
Si l'opacité globale passe sous ~0.7, appliquer un vrai flou derrière les
îlots/popups Quickshell via `MultiEffect` en `layer.effect` sur chaque surface
(barre, popups wifi/calendrier/power, panneau de config, OSD).
QtQuick.Effects est déjà installé. À prévoir quand l'opacité sera réduite.

## 0. Composant réutilisable (fondation)
- Nouveau fichier `dev/CollapsibleSection.qml`
  - props : `title` (string), `expanded` (bool), `icon` optionnel
  - en-tête : Row titre + flèche ("▼" ouvert / "▶" fermé), fond surfaceVariant, clic toggle
  - contenu : Column avec visible/clip + Behavior sur height
  - style cohérent : Theme.globalRadius, couleurs Theme
- État d'expansion persisté dans `style_vars.json` sous `"panel_sections": {...}`
  -> nouveau handler `panel_section` dans `core/config_manager.py`

## 1. Onglet 0 "Esthétique" -> 2 sous-catégories
- "🎨 Thème & Fond d'écran" (fermée par défaut)
  - jeux de couleurs (dynamic / tokyo-night / catppuccin)
  - bouton 🖼 Fonds d'écran + dossier wallpapers
  - schéma Matugen + contraste + bouton Sync Matugen
  - swatches de la palette active + édition hex custom (décision A)
- "⚙️ Aspect technique du bureau" (fermée par défaut)
  - gaps in/out, arrondis, opacité générale (géométrie 132/6/28 conservée)
  - flou blur On/Off + taille + passes
  - hauteur de barre + visibilité du bouton config (décision B)

## 2. Onglet 3 "Applications" -> 2 sous-catégories
- "⌨️ Programmes par défaut des raccourcis" : app_vars.json actuel (Terminal, Music, Browser...) -> programs.lua
- "▶️ Programmes lancés au démarrage" (NOUVEAU) :
  - nouveau `core/autostart.json` (liste {alias, command, enabled})
  - `exec.lua` lit ce JSON au lieu du hardcod (quickshell, hypridle, polkit)
  - UI liste éditable + ajouter/supprimer/activer
  - handlers `autostart_set` / `autostart_del` / `autostart_toggle` dans config_manager.py

## 3. Onglet 2 "Contrôles" (binds)
- STAND BY (décision D) : pas de sous-catégories par univers pour l'instant
- l'onglet reste tel quel dans ce chantier

## 4. Fichiers impactés
| Fichier | Changement |
|---|---|
| dev/CollapsibleSection.qml | NOUVEAU composant |
| dev/config_panel.qml | réorg onglets 0 et 3 en sections collapsibles |
| dev/core/config_manager.py | handlers panel_section + autostart_* |
| dev/core/style_vars.json | clé panel_sections |
| dev/core/autostart.json | NOUVEAU |
| dev/hypr_modular/exec.lua | autostart depuis JSON |
| dev/deploy_portable.sh / deploy_station.sh | copier CollapsibleSection.qml + autostart.json |

## 5. Ordre de réalisation
0. D'ABORD : corriger les bugs du dernier batch (blur + OSD) signalés par `quickshell` en terminal
1. CollapsibleSection.qml + intégration onglet Esthétique (test visuel)
2. Persistance panel_sections
3. Onglet Applications + autostart.json + exec.lua
4. Tests, déploiement portable puis station
