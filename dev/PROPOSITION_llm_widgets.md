# Widget de consommation des services LLM — de DeepSeek aux autres

Le widget `deepseek` devient la base d'une famille de widgets « compte LLM » :
un widget affiche l'état d'**un** service, choisi par son option `provider`.

## Ce que chaque service expose réellement (vérifié le 05/11)

| Service | Point d'entrée | Clé nécessaire | Ce qu'on peut afficher |
|---|---|---|---|
| DeepSeek | `GET /user/balance` | clé API ordinaire | solde total, offert, rechargé, `is_available` |
| OpenRouter | `GET /api/v1/credits` | **clé de gestion** (management) | crédits achetés, consommés, restants |
| OpenAI | `GET /v1/organization/costs` | **clé admin** d'organisation | coût par période — pas de solde |
| Anthropic | Usage & Cost Admin API | **clé admin** (indisponible en compte individuel) | usage et coût par période |
| Ollama | `GET /api/tags`, `GET /api/ps` | aucune (local) | modèles installés, modèles chargés — aucun quota |

Conséquence à garder en tête : il n'existe pas d'indicateur uniforme. Deux familles
de fournisseurs — « solde » (DeepSeek, OpenRouter) et « usage » (OpenAI, Anthropic,
avec une clé admin) — plus un cas local sans notion d'argent. Un widget qui
prétendrait afficher « le pourcentage de quota » pour tous mentirait sur la moitié
d'entre eux.

## Configuration laissée à l'utilisateur

`core/llm_providers.json`, préservé au déploiement :

    [ { "id": "deepseek",  "label": "DeepSeek",  "kind": "balance",
        "base_url": "https://api.deepseek.com", "key": "deepseek.api_key" },
      { "id": "openrouter", "label": "OpenRouter", "kind": "balance",
        "base_url": "https://openrouter.ai/api/v1", "key": "llm.openrouter.api_key" },
      { "id": "ollama", "label": "Ollama (local)", "kind": "local",
        "base_url": "http://localhost:11434", "key": "" } ]

`base_url` est modifiable (service auto-hébergé, proxy, passerelle d'entreprise) et
la clé vit dans `secrets.json` sous la référence indiquée. Le panneau, section
« Accès API », affiche une ligne par fournisseur : adresse, champ de clé masqué,
état (« clé enregistrée (…9f2a) », « clé refusée », « injoignable »).

## Découpage prévu

1. `core/llm_usage_service.py --provider <id>` : un adaptateur par `kind`
   (`balance`, `usage`, `local`), cache 5 min comme `deepseek_service.py`, et
   toujours une sortie JSON exploitable même en échec.
2. `widgets/llm.qml` : le rendu actuel, avec l'unité et le libellé tirés de
   l'adaptateur (`¥ 42.10 · DeepSeek`, `3 modèles chargés · Ollama`).
3. Le widget `deepseek` reste en place jusqu'à ce que `llm` sache le remplacer
   (son option `provider: "deepseek"`), puis il est retiré.

## Ce qui manque pour finir DeepSeek

Une clé réelle saisie dans le panneau : le chemin réseau a été vérifié avec une clé
bidon (« clé refusée », 401), mais jamais un solde effectivement affiché.
