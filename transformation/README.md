# NovaMarket S4

## Rejouer le chargeur

Depuis la racine du dépôt :

```bash
export NOVAMARKET_DSN='host=127.0.0.1 port=15432 dbname=novamarket user=atelier'
# Fournir le mot de passe avec PGPASSFILE ou la configuration PostgreSQL locale.
docker compose up -d --wait postgres
python transformation/exemple.py
python transformation/chargement_postgres.py
python transformation/chargement_postgres.py
```

Le chargeur lit par défaut `ingestion/data/valid/offres.jsonl`, puis le fichier de secours
si le lot S3 n'existe pas. La clé métier est `(offer_id, observed_on)`. Les lignes sont
validées dans une transaction et les rejets restent dans `fournisseur.rejets`.

## Grain et limites

- Une observation représente une offre fournisseur pour un produit à une date donnée.
- La clé `(offer_id, observed_on)` permet plusieurs observations datées sans doublons.
- Les contrôles portent sur les types, EUR, les unités/prix non négatifs, les fournisseurs
  connus (F01/F02/F03) et la référence produit dans `metier.products`.
- Les rejets sont conservés dans `fournisseur.rejets` sans modifier les offres valides.
- Le deuxième passage du même lot ne crée aucune nouvelle ligne.

## Construire dbt

```bash
mkdir -p s4/travail/profil
docker compose --profile transfo build dbt
read -rs DBT_ENV_SECRET_PASSWORD
export DBT_ENV_SECRET_PASSWORD
export DBT_DATABASE=novamarket
docker compose --profile transfo run --rm --no-deps --user "$(id -u):$(id -g)" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt debug --profiles-dir /work/profil
docker compose --profile transfo run --rm --no-deps --user "$(id -u):$(id -g)" \
  -w /projet -e DBT_ENV_SECRET_PASSWORD -e DBT_DATABASE dbt \
  dbt build --profiles-dir /work/profil
```
