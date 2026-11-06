# Proposition — applet et widget Hermes

Validé par Amo le 2026-11-06, **à réaliser plus tard**. Rien n'est implémenté.

## Le principe

Un **observatoire et un lanceur de tâches**, pas un client de chat. Le chat
reste dans Discord et dans le terminal : dupliquer une interface de conversation
dans le shell ne ferait que créer un troisième endroit à maintenir, moins bon
que les deux autres.

## Applet (barre)

- **L'état en un glyphe** : repos, en cours, attente d'accord, erreur. Un badge
  donne le nombre de tâches actives ; la couleur d'alerte suit l'état
  (`Theme.warn` pour une attente, `Theme.error` pour un échec).
- **Clic → popup** : les cinq dernières exécutions, avec durée et résultat. Deux
  actions par ligne : relancer, annuler.
- Le nom de l'applet est au survol, comme les autres ; en colonne, l'icône seule.

## Widget

La même matière, plus grand, plus le contexte :

- la file d'attente des tâches, et le log en fin de tâche (`tail` en direct) ;
- les cron avec leur prochaine exécution et leur dernier résultat ;
- la consommation de tokens par jour et par tâche, en petit à côté de l'état ;
- deux ou trois **modèles de tâches** d'un clic (« résume mes commits du jour »).

## Approbations — c'est l'usage qui justifie le duo

Répondre à une demande d'accord depuis le widget, sans ouvrir un terminal. C'est
le chaînon manquant quand on pilote Hermes depuis Discord : la demande arrive
dans un canal, mais l'accord se donne ailleurs.

Les alertes restent **discrètes** : un badge, jamais une notification.

## Le prérequis, et c'est une décision

Hermes doit **exposer son état** : un fichier JSON rafraîchi suffit pour l'état,
la file et les cron ; les approbations demandent en plus un canal de réponse —
un socket local, ou un fichier de requête/réponse. Tout le reste découle de ce
choix. À trancher avant d'écrire une ligne de QML.

## Ce que je n'y mettrais pas

- le chat continu (Discord et le terminal le font mieux) ;
- les formulaires complexes (créer une tâche à rallonge) ;
- la gestion des profils, skills et secrets : ça reste au CLI.
