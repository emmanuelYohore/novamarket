#!/usr/bin/env bash
# Rejoue S2 puis S3 depuis novamarket/ (S1 doit avoir été rejoué avant : bash scripts/run_s1.sh)
set -euo pipefail
P="docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket"
docker compose exec -T postgres mkdir -p /s2/donnees 2>/dev/null || true
docker compose cp s2/donnees/. postgres:/s2/donnees/
mkdir -p s2/preuves s3/preuves
$P < s2/sql/10_catalogue.sql  > s2/preuves/10_catalogue.txt
$P < s2/sql/11_analyses.sql   > s2/preuves/11_analyses.txt
# Benchmark : génération (une seule fois), référence sans index, index, mesures après, analyse
$P -c "SELECT 1 FROM pg_namespace WHERE nspname='benchmark'" | grep -q 1 || $P < s3/generer.sql > s3/preuves/00_generation.txt
$P -c "DROP INDEX IF EXISTS benchmark.benchmark_sales_store_idx"
PSQL="$P" bash s3/sql/run_benchmark.sh avant_index
$P < s3/sql/21_index.sql > s3/preuves/02_index.txt
PSQL="$P" bash s3/sql/run_benchmark.sh apres_index
$P < s3/sql/22_analyse_critique.sql > s3/preuves/03_analyse_critique.txt
