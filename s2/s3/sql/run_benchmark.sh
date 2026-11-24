#!/usr/bin/env bash
# Protocole : pour chaque requête, 1 passage isolé (1er passage) puis 5 répétitions ;
# on conserve le plan complet de chaque passage et la médiane des répétitions.
# Usage : bash s3/sql/run_benchmark.sh <etiquette>   (ex. avant_index / apres_index)
set -euo pipefail
ETQ=${1:?etiquette}
PSQL=${PSQL:-"psql -X -q -v ON_ERROR_STOP=1"}
OUT=s3/preuves/$ETQ; mkdir -p "$OUT"
declare -A Q=(
  [QA_store42]="SELECT count(*), sum(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42"
  [QB_store1]="SELECT count(*), sum(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1"
)
echo "requete;passage;execution_ms;planning_ms" > "$OUT/mesures.csv"
for k in QA_store42 QB_store1; do
  for i in 0 1 2 3 4 5; do
    $PSQL -c "EXPLAIN (ANALYZE, BUFFERS) ${Q[$k]}" > "$OUT/${k}_passage$i.txt"
    ex=$(grep -oP 'Execution Time: \K[0-9.]+' "$OUT/${k}_passage$i.txt")
    pl=$(grep -oP 'Planning Time: \K[0-9.]+' "$OUT/${k}_passage$i.txt")
    echo "$k;$i;$ex;$pl" >> "$OUT/mesures.csv"
  done
done
cat "$OUT/mesures.csv"
