# Widget de consommation des services LLM — de DeepSeek aux autres

Un seul composant, `widgets/llm.qml`, affiche l'état d'**un** service ; il est
alimenté par le contrat JSON normalisé de `core/llm_contrat.py` et déduit le
fournisseur de l'id du widget (« deepseek-3 » → deepseek).

## Ce que chaque service expose réellement (vérifié le 05/11)

| Service | Point d'entrée | Clé nécessaire | Ce qu'on peut afficher |
|---|---|---|---|
| DeepSeek | `GET /user/balance` | clé API ordinaire | solde total, offert, rechargé, `is_available` |
| Ollama Cloud | `GET /api/balance` + `GET /api/usage` | clé de `ollama.com` | enveloppe incluse restante (`balance_usd`/`allowance_usd`), crédits achetés, coût sur 24 h / 7 j / 30 j, tokens |
| Antigravity (Google AI Pro) | `POST /v1internal:retrieveUserQuota` (Code Assist) | jeton OAuth du CLI, dans le trousseau | fraction restante **par modèle**, heure de reset **par fenêtre** (5 h et hebdo) |
| OpenRouter | `GET /api/v1/credits` | **clé de gestion** (management) | crédits achetés, consommés, restants — non implémenté |
| OpenAI | `GET /v1/organization/costs` | **clé admin** d'organisation | coût par période — pas de solde, non implémenté |
| Anthropic | Usage & Cost Admin API | **clé admin** (indisponible en compte individuel) | usage et coût par période — non implémenté |
| Ollama local (`:11434`) | `GET /api/tags`, `GET /api/ps` | aucune | modèles installés et chargés — rien de monétaire |

Correction du 05/11 : la première version de cette note disait « Ollama : aucun
quota ». C'était vrai du démon local, faux du service cloud — `api/usage` répond
aussi bien en local qu'en cloud (même schéma, `scope: self`), et `/api/balance`
donne l'enveloppe incluse du mois. Ollama Cloud est donc dans la famille
« solde », la mieux servie des trois.

Conséquence à garder en tête : il n'existe pas d'indicateur uniforme. Trois
familles — « solde » (DeepSeek, Ollama Cloud, OpenRouter), « usage » (OpenAI,
Anthropic, avec une clé admin) et « quota d'abonnement » (Antigravity), plus un
cas local sans argent. Un widget qui prétendrait afficher « le pourcentage de
quota » pour tous mentirait sur la moitié d'entre eux.

Les trois fournisseurs payants restants (OpenAI, Anthropic, Gemini API) ne sont
lisibles qu'avec une **clé d'administration d'organisation** qu'un compte
individuel n'obtient pas. Trois adaptateurs qui ne peuvent jamais s'exécuter
seraient du code mort : ils ne sont pas écrits.

## Antigravity : un quota pour les trois à la fois

L'abonnement Google AI Pro donne accès, via Antigravity, à Gemini (4 Argon),
**Claude (Opus 5.5 / Sonnet 5.5)** et **GPT-OSS 120B** — vérifié par
`agy models`. Un seul plafond couvre donc les trois fournisseurs dont les API
demanderaient une clé admin.

**Correction du 05/11 (second passage) : il est interrogeable.** Les logs 429
nomment l'URL que le CLI essaie d'atteindre —
`daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels` — et son
endpoint frère `v1internal:retrieveUserQuota` rend, par modèle, une
`remainingFraction` et un `resetTime`. L'authentification est le jeton OAuth que
`agy` range dans le trousseau libsecret (`service=gemini`,
`username=antigravity`) : il est lu à la volée, jamais copié sur disque ni
journalisé. Le hub local en protobuf n'a donc plus besoin d'être décodé.

Ce que l'API montre (relevé du 05/11) : deux fenêtres, distinguées par leur heure
de reset — 5 h pour les modèles Gemini (96 % restants), hebdomadaire pour
Claude Opus/Sonnet 5.5 et GPT-OSS 120B (0 %, réouverture le 07/11 à 17:15). Les
logs ne disaient rien de tel : ils ne nomment aucun modèle.

Le jeton expire en une heure environ et n'est renouvelé que lorsque le CLI
s'exécute. Passé ce délai, le service retombe sur l'inférence par les logs
(`RESOURCE_EXHAUSTED … Resets in 151h24m24s` → échéance, puis décompte local) et
`api_error` dit pourquoi. Les deux chemins sont exercés et testés.

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
- `widgets/llm.qml` : un seul composant pour les trois fournisseurs (valeur en
  grand, mesures en petit, décompte si le service ne connaît qu'une échéance) ;
- `core/llm_contrat.py` : le contrat d'affichage (mesures, alerte, icône, `fin` /
  `releve`) que chaque service compose côté Python ;
- `core/antigravity_service.py` : pourcentage par modèle et par fenêtre via l'API
  Code Assist, repli sur les logs quand le jeton a expiré ;
- seuils : alerte sous 1 $ côté Ollama (≈ une heure de consommation au rythme
  constaté), sous 5 unités côté DeepSeek.

Une entrée sans clé (Antigravity) affiche « aucune clé — la donnée est lue
localement » au lieu d'un champ vide, et la liste par défaut est fusionnée avec
le fichier déployé : un fournisseur ajouté plus tard apparaît sans que
l'utilisateur ait à retoucher son fichier préservé.

Reste :

1. ~~`widgets/llm.qml` générique~~ — fait le 05/11 : `deepseek.qml`, `ollama.qml`
   et `antigravity.qml` ont disparu, le fournisseur se déduit de l'id du widget.
2. OpenRouter, si une clé de gestion arrive un jour : le seul des quatre restants
   à exposer un vrai solde sans compte d'entreprise.
3. OpenAI / Anthropic / Gemini API : rien à faire tant qu'il n'y a pas de clé
   admin — le panneau afficherait « clé absente » indéfiniment.

## Ce qui manque pour finir DeepSeek

Rien côté code : le solde réel s'affiche depuis le 05/11 (clé saisie dans le
panneau, `$19.96`). L'archive d'export `usage_data_*.zip` reste vide côté serveur,
donc l'historique par clé n'est pas exploitable — le solde reste la seule donnée.
