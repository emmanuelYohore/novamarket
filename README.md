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
