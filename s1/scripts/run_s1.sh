#!/usr/bin/env bash
# Rejoue tout S1 (M2 + M3) depuis novamarket/ : bash s1/sql/run_s1.sh
set -euo pipefail
docker compose up -d --wait postgres
for f in 01_ddl 02_import_reception 03_integration 04_controles_volumes 05_indicateurs; do
  echo "=== $f ==="
  docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U atelier -d novamarket -f "/s1/sql/$f.sql"
done
