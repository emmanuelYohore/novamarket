-- =====================================================================
-- S3 · 21_index.sql : index retenu (B-tree sur la colonne filtrée)
-- Coût de construction mesuré avec \timing, taille avec pg_relation_size.
-- =====================================================================
\timing on
DROP INDEX IF EXISTS benchmark.benchmark_sales_store_idx;
CREATE INDEX benchmark_sales_store_idx ON benchmark.benchmark_sales (store_id);
\timing off
ANALYZE benchmark.benchmark_sales;
SELECT pg_size_pretty(pg_relation_size('benchmark.benchmark_sales'))              AS taille_table,
       pg_size_pretty(pg_relation_size('benchmark.benchmark_sales_store_idx'))    AS taille_index,
       pg_relation_size('benchmark.benchmark_sales_store_idx')                    AS taille_index_octets;
