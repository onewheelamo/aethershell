# 9 — Spotlight pill — MAQUETTE + IMPLÉMENTATION

> État : **livré (v1, applications)** dans `dev/spotlight.qml`. Cette fiche garde
> la géométrie et la palette validées ; les écarts réels et les pièges sont
> consignés dans `fine_tune.md` §9.

Maquette statique de la pilule bas-centre qui remplacerait fuzzel.
Rendus : `spotlight_typing.png` (frappe), `spotlight_idle.png` (repliée),
`spotlight_detail.png` et `spotlight_idle_detail.png` (détails ×2).
Source : `spotlight_mock.html` — palette et wallpaper lus dans l'état courant du
shell (`palette.dynamic` : bg `#050b12`, fg `#eff5ff`, accent `#99cbff`).

## Géométrie

| Élément | Valeur | Pourquoi |
|---------|--------|----------|
| Largeur | 720 px | place pour un nom long + sa catégorie sans ellipse |
| Hauteur repliée | 62 px | même gabarit que la barre (36) + respiration |
| Ligne de résultat | 46 px | 6 résultats max. visibles, sans scroll |
| Pied | 36 px | rappel des touches, compteur de résultats |
| Marge basse | 44 px | la pilule flotte, elle ne touche pas le bord |
| Rayon | 26 px | plus rond que `globalRadius` (18) : c'est une bulle, pas un panneau |
| Fond | `surface` à 90 % + flou 24 px | même famille que le panneau, un cran plus opaque pour rester lisible sur un fond clair |
| Bordure | accent à 26 % | rappel de la capsule de la barre |

## États

1. **Repliée** — icône loupe, « Rechercher une application, une commande… », chip
   `ÉCHAP` à droite. C'est l'état par défaut à l'ouverture.
2. **Frappe** — la liste s'ouvre sous le champ (4 à 6 lignes), la première est
   sélectionnée d'office, la sous-chaîne trouvée est soulignée dans le nom.
3. **Sans résultat** — une ligne unique « Aucun résultat pour “xyz” », le pied
   reste affiché.
4. **Commande** — préfixe `>` : la ligne de saisie passe en couleur `info` et la
   liste montre des commandes shell (historique + binaires du PATH).

## Interaction

- `↑` `↓` naviguer, `Entrée` lancer, `Tab` compléter le nom sélectionné,
  `Échap` fermer (ou vider le champ s'il est rempli, puis fermer).
- Clic sur une ligne = lancer ; clic hors de la pilule = fermer (le bind
  `launcher_click_close.sh` devient inutile, la pilule est une surface du shell).
- Les résultats mêlent trois sources : entrées `.desktop`, alias déclarés dans
  `app_vars.json` (« Ouvrir firefox sur le bureau 2 » = commande prédéfinie), et
  commandes shell si le préfixe `>` est saisi.

## Décisions à prendre

1. **Largeur** : 720 px (maquette) ou 680 px ? À 680 le nom le plus long
   (« Firefox Developer Edition » + « NAVIGATEUR ») tient encore.
2. **Raccourci** : garder `SUPER + R` (fuzzel aujourd'hui) ou passer à
   `SUPER + Espace` et laisser `R` à autre chose ?
3. **Commandes shell en v1** : le préfixe `>` est utile mais demande un parseur
   et un historique ; on peut livrer la v1 en applications seules.
4. **Fuzzel en secours** : on garde le binaire installé (le temps du rodage) ou on
   débranche le bind dès la première version de la pilule ?

## Ce que ça supprime

- Le bind souris non-consommant et `core/launcher_click_close.sh` (la pilule est
  une `PanelWindow` du shell : clic hors surface = `MouseArea` de fermeture).
- La dépendance à `fuzzel.ini` et à ses couleurs, qui ne suivent pas la palette
  Matugen.
