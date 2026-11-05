# Widget de consommation des services LLM — de DeepSeek aux autres

Le widget `deepseek` devient la base d'une famille de widgets « compte LLM » : un
widget affiche l'état d'**un** service.

## Ce que chaque service expose réellement (vérifié le 05/11)

| Service | Point d'entrée | Clé nécessaire | Ce qu'on peut afficher |
|---|---|---|---|
| DeepSeek | `GET /user/balance` | clé API ordinaire | solde total, offert, rechargé, `is_available` |
| Ollama Cloud | `GET /api/balance` + `GET /api/usage` | clé de `ollama.com` | enveloppe incluse restante (`balance_usd`/`allowance_usd`), crédits achetés, coût sur 24 h / 7 j / 30 j, tokens |
| OpenRouter | `GET /api/v1/credits` | **clé de gestion** (management) | crédits achetés, consommés, restants |
| OpenAI | `GET /v1/organization/costs` | **clé admin** d'organisation | coût par période — pas de solde |
| Anthropic | Usage & Cost Admin API | **clé admin** (indisponible en compte individuel) | usage et coût par période |
| Ollama local (`:11434`) | `GET /api/tags`, `GET /api/ps` | aucune | modèles installés et chargés — rien de monétaire |

Correction du 05/11 : la première version de cette note disait « Ollama : aucun
quota ». C'était vrai du démon local, faux du service cloud — `api/usage` répond
aussi bien en local qu'en cloud (même schéma, `scope: self`), et `/api/balance`
donne l'enveloppe incluse du mois. Ollama Cloud est donc dans la famille
« solde », la mieux servie des trois.

Conséquence à garder en tête : il n'existe pas d'indicateur uniforme. Deux
familles — « solde » (DeepSeek, Ollama Cloud, OpenRouter) et « usage » (OpenAI,
Anthropic, avec une clé admin) — plus un cas local sans argent. Un widget qui
prétendrait afficher « le pourcentage de quota » pour tous mentirait sur la
moitié d'entre eux.

## Configuration : un fichier, pas du code

`core/llm_providers.json`, préservé au déploiement (`PRESERVE_CORE`), lu par
`core/llm_providers.py` :

    { "providers": [
        { "id": "deepseek", "label": "DeepSeek", "kind": "balance",
          "base_url": "https://api.deepseek.com", "key": "deepseek.api_key",
          "service": "core/deepseek_service.py", "widget": "deepseek",
          "hint": "sk-…", "summary": "solde de l'API" },
        { "id": "ollama", "label": "Ollama Cloud", "kind": "balance",
          "base_url": "https://ollama.com", "key": "ollama.api_key",
          "service": "core/ollama_service.py", "widget": "ollama",
          "hint": "clé de ollama.com",
          "summary": "solde restant et coût des 7 derniers jours" } ] }

Chaque entrée porte : `id`, `label`, `kind`, `base_url` (modifiable : proxy,
auto-hébergement, passerelle d'entreprise), la référence de clé dans
`secrets.json` (« section.nom »), le script qui interroge le service (utilisé
pour tester la clé à l'enregistrement), le type de widget, et deux textes
d'affichage.

Les services lisent ce fichier pour l'adresse et la clé : changer `base_url` ne
touche à aucun code. Le panneau, section « Accès API », dessine **une ligne par
entrée** (champ masqué, bouton Enregistrer, état « clé enregistrée (…9f2a) »,
« clé refusée ») — ajouter OpenAI, Claude ou Gemini ne demande aucune retouche de
l'interface.

## État au 05/11

Fait :

- `core/llm_providers.json` + `core/llm_providers.py` (lecture, valeurs par
  défaut, accès clé/adresse) ;
- panneau « Accès API » piloté par le fichier (une ligne par fournisseur) ;
- `core/deepseek_service.py` et `core/ollama_service.py`, ce dernier rendant
  solde, enveloppe incluse, date de remise à zéro et coût sur 7 jours ;
- `widgets/ollama.qml` : montant restant, et « <coût> sur 7 j » en second ;
- seuils : alerte sous 1 $ côté Ollama (≈ une heure de consommation au rythme
  constaté), sous 5 unités côté DeepSeek.

Reste :

1. `widgets/llm.qml` générique, alimenté par `provider` en option, pour remplacer
   `deepseek.qml` et `ollama.qml` — à faire quand le troisième fournisseur
   arrivera, pas avant (deux widgets explicites se lisent mieux qu'une
   abstraction à deux cas).
2. Les adaptateurs `usage` (OpenAI, Anthropic) : les deux exigent une clé
   d'organisation/admin que le compte individuel n'a pas. Sans elle, l'entrée
   existe mais ne peut rien afficher — à ne poser qu'avec une clé en main.
3. Gemini : endpoint à vérifier avant d'écrire quoi que ce soit (probablement
   `cloudbilling`, donc clé de service Google Cloud).

## Ce qui manque pour finir DeepSeek

Rien côté code : le solde réel s'affiche depuis le 05/11 (clé saisie dans le
panneau, `$19.96`). L'archive d'export `usage_data_*.zip` reste vide côté serveur,
donc l'historique par clé n'est pas exploitable — le solde reste la seule donnée.
