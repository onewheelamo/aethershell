# PROJET QUICKSHELL — STATION (Arch Linux Tour) & PORTABLE (Fedora Laptop)
État d'avancement : [==========] 100% (Prêt pour déploiement sur Station)

## ÉTAPE 1 : Fondations & Style (TERMINÉ)
- [x] Configuration de Matugen (Génération palette couleurs + hook `hyprquickpaper`)
- [x] Fichier de Styles Global (Variables, Opacité 0.85, Thèmes, Singleton `Theme.qml`)
- [x] Structure du Layout Principal (Positionnement des 3 îlots sous Quickshell)
- [x] Synchronisation Matugen <-> Hyprland (`colors.lua` + injection dynamique des bordures/arrondis)

## ÉTAPE 2 : Îlot Central (TERMINÉ)
- [x] Affichage Heure et Date (+ bouton roue crantée de configuration)
- [x] Panneau éphémère au survol (Météo locale & Emplacement dynamiques avec cache)
- [x] Calendrier interactif & Intégration Nextcloud (Navigation mensuelle, points de couleur CalDAV, extension au clic sur un jour avec détail des événements)

## ÉTAPE 3 : Îlot de Gauche (TERMINÉ)
- [x] Liaison Workspaces Hyprland (Temps réel via `Quickshell.Hyprland` + `workspace_service.py`, Kanji 一..五, molette et clic)
- [x] Rendu visuel des indicateurs (États actif, occupé avec point indicateur, vide, urgent + animations Matugen)

## ÉTAPE 4 : Îlot de Droite & Adaptation Matérielle Tour/Laptop (TERMINÉ)
- [x] Systray & Réseau (Systray `StatusNotifierItem` cliquable + Centre de Notifications + WiFi & Ethernet auto-détectés)
- [x] Contrôles Système adaptatifs : masquage automatique de la batterie, du limiteur 80% et de la luminosité d'écran interne sur la tour (`Station`), conservés sur le laptop (`Portable`)
- [x] Menu Alimentation dynamique (`Station` / `Portable`)

## ÉTAPE 5 : Clavier au Premier Lancement (100% Souris) & Déploiement Arch Linux (TERMINÉ)
- [x] Fenêtre d'accueil au premier lancement permettant de choisir la disposition clavier à la souris (`fr` AZERTY par défaut, `us` QWERTY, etc.)
- [x] Synchronisation automatique de `input.lua` et conversion de la nomenclature explicite des Workspaces 1 à 5 dans `binds.lua` (`ampersand..parenleft` <-> `1..5`)
- [x] Détection automatique du hostname via `/etc/hostname` en minuscules dans `hyprland.lua` + ajout de `hardware-station.lua` (NVIDIA RTX 4070 + `HDMI-A-1`)
- [x] Script de déploiement dédié `deploy_station.sh` (Arch Linux / `pacman`)
