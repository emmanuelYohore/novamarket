-- =====================================================================
-- S3 · 22_analyse_critique.sql : cas d'index inefficace, multiplication
-- de lignes par jointure, écarts estimé / réel. Rejouable (les réglages
-- SET sont locaux à la session, les statistiques étendues sont supprimées à la fin).
-- =====================================================================
\pset footer off

\echo '== C1. Index inefficace : Q_B (store_id = 1, 95 % de la table) en forçant l''index =='
SET enable_seqscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1;
RESET enable_seqscan;

\echo '== C2. Filtre intermédiaire (stores 2 à 1001 : ~100 000 lignes, 1 %) : plan choisi =='
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(amount_cents) FROM benchmark.benchmark_sales WHERE store_id BETWEEN 2 AND 1001;
\echo '== C2 bis. Même filtre sans index (référence) =='
SET enable_indexscan = off; SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(amount_cents) FROM benchmark.benchmark_sales WHERE store_id BETWEEN 2 AND 1001;
RESET enable_indexscan; RESET enable_bitmapscan;

\echo '== C3. Multiplication des lignes : ventes du magasin 42 x campagnes =='
SELECT 'sans jointure' AS calcul, count(*) AS lignes, sum(amount_cents) AS ca_simule_cents
FROM benchmark.benchmark_sales WHERE store_id = 42
UNION ALL
SELECT 'jointure directe campagnes', count(*), sum(s.amount_cents)
FROM benchmark.benchmark_sales s JOIN benchmark.campaign_assignments c ON c.store_id = s.store_id
WHERE s.store_id = 42
UNION ALL
SELECT 'filtre EXISTS (grain vente conservé)', count(*), sum(s.amount_cents)
FROM benchmark.benchmark_sales s
WHERE s.store_id = 42 AND EXISTS (SELECT 1 FROM benchmark.campaign_assignments c WHERE c.store_id = s.store_id);

\echo '== C3 bis. Plan de la jointure : lignes en entrée / sortie =='
EXPLAIN (ANALYZE, BUFFERS) SELECT c.campaign_id, count(*), sum(s.amount_cents)
FROM benchmark.benchmark_sales s JOIN benchmark.campaign_assignments c ON c.store_id = s.store_id
WHERE s.store_id = 42 GROUP BY c.campaign_id;

\echo '== C4. Écart estimé / réel : colonnes corrélées zone_id et channel_id =='
SELECT count(*) FILTER (WHERE zone_id = channel_id) AS lignes_zone_egale_canal, count(*) AS total
FROM benchmark.benchmark_sales;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 3;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 4;

\echo '== C4 bis. Après statistiques étendues (dépendances fonctionnelles) =='
CREATE STATISTICS benchmark.sales_zone_canal_stx (dependencies, mcv) ON zone_id, channel_id FROM benchmark.benchmark_sales;
ANALYZE benchmark.benchmark_sales;
EXPLAIN SELECT count(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 3;
EXPLAIN SELECT count(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 4;
DROP STATISTICS benchmark.sales_zone_canal_stx;
ANALYZE benchmark.benchmark_sales;

\echo '== C5. Statistiques de store_id vues par le planificateur =='
SELECT n_distinct, most_common_vals::text AS mcv, most_common_freqs::text AS mcf
FROM pg_stats WHERE schemaname = 'benchmark' AND tablename = 'benchmark_sales' AND attname = 'store_id';
