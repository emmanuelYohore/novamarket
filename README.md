# NovaMarket – S1 : SQL relationnel et premiers indicateurs

Base PostgreSQL 17 (Docker) construite à partir de `customers.csv`, `orders.csv`, `order_items.csv`, `payments.ndjson` (+ `categories`/`products`). Montants en **centimes d'euro**. Données fictives.

## Exécuter

Depuis `novamarket/` :

```bash
docker compose up -d --wait postgres
bash s1/scripts/run_s1.sh          # rejoue 01 -> 07 dans l'ordre
```

Connexion manuelle : `docker compose exec postgres psql -X -U atelier -d novamarket` (hôte : `127.0.0.1:15432`).

| Script (`s1/scripts/`) | Rôle |
| --- | --- |
| `01_ddl.sql` | Schémas `reception`, `rejets`, `metier` ; tables, clés, contraintes, index |
| `02_import_reception.sql` | `\copy` des CSV et du NDJSON, sans nettoyage |
| `03_integration.sql` | Validation, journal des rejets, insertion dans `metier` |
| `04_controles_volumes.sql` | Bilan reçues / intégrées / rejetées |
| `05_indicateurs.sql` | Indicateurs M3 et cohérences |
| `06_anomalies.sql` | M4 : doublons, orphelins, multiplication de jointure, périmètre du CA |
| `07_controles_essentiels.sql` | M5 : contrôles OK/KO sur les valeurs attendues |
| `run_s1.sh` | Enchaîne les scripts via Docker |

Les fichiers bruts (`s1/donnees/`) ne sont jamais modifiés. Pour rejouer à neuf : `docker compose down -v` puis relancer.

## Organisation du dépôt

```
novamarket/
├── README.md
├── compose.yaml
├── s1/
│   ├── donnees/      # sources brutes, lecture seule
│   ├── scripts/      # 01 à 07 + run_s1.sh
│   └── preuves/      # livrable-pipeline.docx, sorties des scripts
```

## État du projet

| Mission | État |
| --- | --- |
| M1 Modélisation | Fait : schéma, 3 couches reception / rejets / metier |
| M2 Création et import | Fait : 1 897 lignes reçues, 1 894 intégrées, 3 rejetées (journal conservé) |
| M3 Indicateurs | Fait : 320/40/40 commandes, 30 clients sans commande, CA completed 2 621 000 cts, panier 81,91 € |
| M4 Anomalies | Fait : tableau anomalie / détection / effet / décision dans le livrable |
| M5 Cumulatif | Fait : `07_controles_essentiels.sql` et ce README. **À rejouer avant le commit** : coller la sortie dans `s1/preuves/` |
| A1 Approfondissement | Non traité |

## Décisions métier retenues

- **CA = lignes des commandes `completed`** ; `pending` et `cancelled` sont rapportées à part.
- **Panier moyen = CA ÷ commandes terminées** (320).
- **Jamais de jointure directe `order_items` × `payments`** : chaque table est agrégée au grain commande avant la jointure.
- Les doublons exacts et les références orphelines sont **rejetés et journalisés**, pas supprimés des sources.

## Limites connues

- Aucun contrôle de cohérence temporelle (`paid_on` vs `ordered_on`).
- Des paiements `captured` existent sur des commandes `cancelled` (328 375 cts) : cause non établie (remboursement manquant ou erreur de statut ?). À confirmer avec le métier.
- Le prix de ligne est celui de la transaction ; il n'est pas comparé au catalogue.

# NovaMarket S2


## Démarrer et vérifier

Depuis `novamarket/` :

```bash
docker compose up -d --wait postgres
docker compose ps
docker compose exec postgres psql -X -U atelier -d novamarket
```

Dans `psql`, utilisez `SELECT current_database();`, `\dt` et `\d nom_table` pour retrouver la base.

## Sources à importer

CSV UTF-8 séparés par des virgules, avec en-têtes. Les dates sont au format `AAAA-MM-JJ`.

| Fichier | Colonnes et sens | Grain |
| --- | --- | --- |
| `donnees/categories.csv` | `category_id` code, `category_name` libellé, `parent_category_id` code du parent ou champ vide pour une racine. | Une catégorie du catalogue. |
| `donnees/products.csv` | `product_id` code partagé avec les lignes S1, `sku` référence commerciale, `product_name` libellé, `category_id` code de classement, `first_listed_on` date déclarée de première mise en vente. | Une fiche produit à la source, dont l'unicité reste à contrôler. |

Pour transférer les fichiers vers le client `psql` conteneurisé, quitter `psql` avec `\q` puis lancer ces commandes depuis `novamarket/` :

```bash
docker compose exec -T postgres mkdir -p /tmp/novamarket-s2
docker compose cp s2/donnees/. postgres:/tmp/novamarket-s2/
docker compose exec -T postgres ls -l /tmp/novamarket-s2
```

Créez vos tables de réception et utilisez `\copy` depuis `psql`. Gardez le brut disponible pour vos contrôles. Inspectez les champs vides, les identifiants et la couverture des codes produit de S1 avant d'intégrer le catalogue. Importez les catégories avant les produits. Décidez comment garantir l'intégrité des liens, en tenant compte de votre schéma S1 et des lignes qu'il contient déjà. Travaillez par transaction et vérifiez vos comptages avant de valider. Si vous utilisez des tables temporaires, gardez ouverte la session qui les a créées.

## Missions S2

| Mission | Travail du groupe |
| --- | --- |
| **M1 — Enrichissement** | Intégrer le catalogue dans la base S1 et vérifier la couverture des codes produit. Examiner les multiplicités à la réception avant d'ajouter des contraintes ou de joindre les ventes. |
| **M2 — Classements** | Classer les produits et les clients selon leurs performances commerciales. Justifier les groupes de comparaison et le traitement des ex æquo. Mesurer l'effet de duplications sur au moins un classement. |
| **M3 — Évolution** | Comparer les ventes entre périodes avec `LAG()` et `LEAD()`. Contrôler la couverture des périodes et la cohérence des dates entre ventes et catalogue. Distinguer une évolution inhabituelle d'une incohérence démontrée. |
| **M4 — Segmentation** | Segmenter les clients selon leurs performances avec `NTILE()`. Expliciter la population, la mesure, l'ordre et le traitement des égalités. |


Consignez le grain, le périmètre de vente et les limites d'interprétation avec chaque résultat. Les décisions d'analyse et les requêtes sont à construire en groupe.

## Exemple indépendant et dépannage

Depuis `novamarket/`, exécutez la démonstration sur des grandeurs d'atelier, sans tables permanentes :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket < s2/exemple.sql
```

Sous Windows, exécutez ces commandes dans le terminal WSL2. Si un fichier manque dans le conteneur après sa recréation, refaites la copie. Si le service est indisponible, consultez `docker compose logs --tail=50 postgres`. Si un import échoue, vérifiez les noms et types avec `\d`, confirmez le chemin et l'en-tête, puis annulez la transaction en échec avec `ROLLBACK;`. En cas d'erreur de clé, inspectez la réception avant de relancer. [Guide S1](../s1/DEMARRAGE.md) · [Référence SQL](../REFERENCE_SQL.md)
