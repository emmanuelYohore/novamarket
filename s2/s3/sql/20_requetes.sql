-- =====================================================================
-- S3 · 20_requetes.sql : requêtes de mesure du benchmark (lecture seule)
-- Q_A : filtre très sélectif  (store_id = 42 -> ~100 lignes sur 10 M)
-- Q_B : filtre très large     (store_id = 1  -> 9,5 M lignes sur 10 M)
-- Même agrégat de sortie pour les deux : 1 ligne (nb ventes, CA simulé).
-- =====================================================================
-- Q_A
SELECT count(*) AS ventes, sum(amount_cents) AS ca_simule_cents
FROM benchmark.benchmark_sales WHERE store_id = 42;
-- Q_B
SELECT count(*) AS ventes, sum(amount_cents) AS ca_simule_cents
FROM benchmark.benchmark_sales WHERE store_id = 1;
