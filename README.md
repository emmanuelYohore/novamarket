# NovaMarket

Projet pédagogique cumulatif PostgreSQL, ingestion HTTP, dbt et volumétrie.
La base utilise PostgreSQL 17 dans Docker. Tous les montants sont exprimés en centimes
d’euro sauf indication contraire.

## Organisation

```text
novamarket/
├── compose.yaml
├── requirements-v3.txt
├── s1/               # SQL relationnel
├── s2/               # catalogue et fonctions SQL
├── ingestion/        # collecteur S3
├── s4/               # image dbt et profil local
├── transformation/   # chargeur PostgreSQL et projet dbt
└── README.md
```

## PostgreSQL

```bash
docker compose up -d --wait postgres
docker compose ps
docker compose exec postgres psql -X -U atelier -d novamarket
```

Connexion hôte : `127.0.0.1:15432`. Le mot de passe local est configuré dans
`compose.yaml` pour l’environnement de démonstration.

# NovaMarket S1 — SQL relationnel

Rejouer les scripts S1 :

```bash
docker compose up -d --wait postgres
bash s1/scripts/run_s1.sh
```

| Script | Rôle |
| --- | --- |
| `01_ddl.sql` | Schémas, tables, clés, contraintes et index |
| `02_import_reception.sql` | Import brut sans nettoyage |
| `03_integration.sql` | Validation, rejets et insertion métier |
| `04_controles_volumes.sql` | Bilan des lignes reçues, intégrées et rejetées |
| `05_indicateurs.sql` | Indicateurs commerciaux |
| `06_anomalies.sql` | Doublons, orphelins, jointures et périmètre du CA |
| `07_controles_essentiels.sql` | Contrôles attendus |

État validé :

- 1 897 lignes reçues, 1 894 intégrées et 3 rejetées.
- 320 commandes `completed`, 40 `pending`, 40 `cancelled`.
- 30 clients sans commande.
- CA `completed` : 2 621 000 centimes.
- Panier moyen : 81,91 €.

Décisions métier :

- Le CA retenu correspond aux lignes des commandes `completed`.
- Les doublons exacts et références orphelines sont rejetés et journalisés.
- Les tables agrégées au grain commande évitent la multiplication des paiements.

# NovaMarket S2 — Catalogue et analyses SQL

Créer les données du catalogue :

```bash
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 \
  -U atelier -d novamarket -f /s2/sql/10_catalogue.sql
```

Utiliser les scripts suivants :

```text
s2/sql/10_catalogue.sql
s2/sql/11_analyses.sql
s2/s3/sql/20_requetes.sql
s2/s3/sql/21_index.sql
s2/s3/sql/22_analyse_critique.sql
```

Les preuves sont conservées dans `s2/preuves/` et `s2/s3/preuves/`.

# NovaMarket S3 — Ingestion asynchrone

Préparer l’environnement Python :

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-v3.txt
docker compose up -d --build --wait fournisseur
python ingestion/tests/disponibilite.py
python ingestion/exemple.py
```

Contrat HTTP :

```text
GET /health
GET /offers?page=1&scenario=atelier&run=groupe01-essai01
```

L’API expose les fournisseurs F01, F02 et F03. Les sorties sont conservées dans
`ingestion/data/raw/`, `ingestion/data/valid/`, `ingestion/data/rejected/` et
`ingestion/data/bilans/`. Ne publiez pas un lot incomplet comme valide.

Fichier de secours pour S4 :

```text
transformation/secours/offres.jsonl
```

# NovaMarket S4 — Chargement PostgreSQL et dbt

## État

| Mission | État |
| --- | --- |
| M1 — Chargeur Python | Fait : transaction, validation, rejets et rejeu idempotent |
| M2 — Sources dbt | Fait : source `fournisseur.offres` déclarée |
| M3 — Staging | Fait : modèle de vue `stg_offres` |
| M4 — Intermediate et mart | Fait : modèle éphémère et table par produit/jour |
| M5 — Vérification | Fait : `debug`, `compile`, `run` et `build` validés |

## Arborescence

```text
s4/
├── Dockerfile
├── dbt-dependances.txt
├── exemple/
└── travail/profil/profiles.yml

transformation/
├── chargement_postgres.py
├── exemple.py
├── secours/offres.jsonl
├── preuves/S4_verifications.txt
└── dbt/
    ├── dbt_project.yml
    ├── profiles.exemple.yml
    └── models/
        ├── sources.yml
        ├── staging/stg_offres.sql
        ├── intermediate/int_offres_par_observation.sql
        └── marts/mart_offres_par_produit.sql
```

Le projet dbt unique est `transformation/dbt/`, monté dans le conteneur sur `/projet`.
Le profil privé est `s4/travail/profil/profiles.yml`, ignoré par Git.

## Initialiser les données

Depuis la racine du dépôt :

```bash
docker compose up -d --wait postgres
bash s1/scripts/run_s1.sh
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 \
  -U atelier -d novamarket -f /s2/sql/10_catalogue.sql
```

## Charger les offres

Configurer la DSN locale sans écrire le mot de passe dans le dépôt :

```bash
export NOVAMARKET_DSN='host=127.0.0.1 port=15432 dbname=novamarket user=atelier'
```

Fournir le mot de passe avec `PGPASSFILE` ou la configuration PostgreSQL locale.

```bash
python transformation/exemple.py
python transformation/chargement_postgres.py
python transformation/chargement_postgres.py
```

Le chargeur lit `ingestion/data/valid/offres.jsonl`, puis le fichier de secours
`transformation/secours/offres.jsonl` si le lot validé n’existe pas.

### Grain et contrôles

- Une observation représente une offre fournisseur pour un produit à une date.
- La clé métier est `(offer_id, observed_on)`.
- Les identifiants sont non vides.
- Les fournisseurs doivent être F01, F02 ou F03.
- La devise est EUR.
- Le prix et les unités disponibles sont des entiers non négatifs.
- La date suit le format ISO `AAAA-MM-JJ`.
- Le produit doit exister dans `metier.products`.
- Les rejets sont conservés dans `fournisseur.rejets`.
- Le second chargement du même lot ne crée aucune duplication.

## Construire dbt

```bash
docker compose config -q
docker compose --profile transfo build dbt
mkdir -p s4/travail/profil

read -rs DBT_ENV_SECRET_PASSWORD
export DBT_ENV_SECRET_PASSWORD
export DBT_DATABASE=novamarket

docker compose --profile transfo run --rm --no-deps --user "0:0" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt debug --profiles-dir /work/profil

docker compose --profile transfo run --rm --no-deps --user "0:0" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt compile --profiles-dir /work/profil

docker compose --profile transfo run --rm --no-deps --user "0:0" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt run --profiles-dir /work/profil

docker compose --profile transfo run --rm --no-deps --user "0:0" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt build --profiles-dir /work/profil
```

Le profil `novamarket_dbt` correspond à `profile: novamarket_dbt` dans
`transformation/dbt/dbt_project.yml`. Le mot de passe n’est fourni que par
`DBT_ENV_SECRET_PASSWORD`.

## Résultats vérifiés

- Premier passage : 20 lignes examinées, 20 chargées, aucun rejet.
- Second passage : 20 lignes inchangées, aucune nouvelle ligne.
- Source `fournisseur.offres` : 20 lignes.
- Vue `dbt_dev.stg_offres` : 20 lignes.
- Table `dbt_dev.mart_offres_par_produit` : 20 lignes.
- Mart : 488 unités disponibles.
- `dbt debug` : toutes les vérifications réussies.
- `dbt build` : 8 contrôles/modèles réussis, aucune erreur ni alerte.

La preuve consolidée est disponible dans
`transformation/preuves/S4_verifications.txt`.

## Limites

- Le chargeur vérifie les références produit uniquement si `metier.products` existe.
- Le mart agrège au grain produit/jour ; il ne compare pas plusieurs jours.
- Les données brutes S3 ne sont pas modifiées.
- Ne committez ni `.env`, ni mot de passe, ni volume Docker, ni dossiers `target/` ou `logs/`.
