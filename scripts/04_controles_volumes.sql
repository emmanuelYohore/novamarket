-- =====================================================================
-- S1 · M2 · 04_controles_volumes.sql : bilan bruts / intégrés / rejetés
-- Invariant à vérifier : reçues = intégrées + rejetées (écart = 0).
-- =====================================================================
WITH recu AS (
  SELECT 'categories.csv' AS source_file, 'categories' AS cible, count(*) AS recues FROM reception.categories_raw
  UNION ALL SELECT 'products.csv',     'products',    count(*) FROM reception.products_raw
  UNION ALL SELECT 'customers.csv',    'customers',   count(*) FROM reception.customers_raw
  UNION ALL SELECT 'orders.csv',       'orders',      count(*) FROM reception.orders_raw
  UNION ALL SELECT 'order_items.csv',  'order_items', count(*) FROM reception.order_items_raw
  UNION ALL SELECT 'payments.ndjson',  'payments',    count(*) FROM reception.payments_raw),
integre AS (
  SELECT 'categories' AS cible, count(*) AS integrees FROM metier.categories
  UNION ALL SELECT 'products',    count(*) FROM metier.products
  UNION ALL SELECT 'customers',   count(*) FROM metier.customers
  UNION ALL SELECT 'orders',      count(*) FROM metier.orders
  UNION ALL SELECT 'order_items', count(*) FROM metier.order_items
  UNION ALL SELECT 'payments',    count(*) FROM metier.payments),
rejete AS (
  SELECT source_file, count(*) AS rejetees FROM rejets.journal GROUP BY source_file)
SELECT r.source_file, r.recues, i.integrees, COALESCE(j.rejetees, 0) AS rejetees,
       r.recues - i.integrees - COALESCE(j.rejetees, 0) AS ecart_non_explique
FROM recu r
JOIN integre i USING (cible)
LEFT JOIN rejete j USING (source_file)
ORDER BY r.source_file;

-- Journal des rejets (cause conservée)
SELECT rejet_id, source_file, ligne_no, cle_source, motif, contenu_brut
FROM rejets.journal ORDER BY rejet_id;

-- Rejets par motif
SELECT source_file, motif, count(*) AS nb FROM rejets.journal GROUP BY 1, 2 ORDER BY 1, 2;
