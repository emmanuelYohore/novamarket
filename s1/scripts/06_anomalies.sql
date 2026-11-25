-- 06_anomalies.sql : M4 - investiguer les anomalies (lecture seule, rejouable)
-- Hypothèse de nommage : schémas reception / metier. Adapter les noms de tables
-- de réception (order_items_raw, orders_raw, products_raw) à ceux de 01_ddl.sql.

\echo '== A1. Doublons de lignes d''articles (réception) =='
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents,
       COUNT(*) AS n
FROM reception.order_items_raw
GROUP BY order_item_id, order_id, product_id, quantity, unit_price_cents
HAVING COUNT(*) > 1;                       -- attendu : order_item_id 7, n = 2

\echo '== A1bis. Même identifiant, contenu différent (faux doublons) =='
SELECT order_item_id, COUNT(*) AS n, COUNT(DISTINCT (order_id, product_id, quantity, unit_price_cents)) AS contenus
FROM reception.order_items_raw
GROUP BY order_item_id
HAVING COUNT(*) > 1 AND COUNT(DISTINCT (order_id, product_id, quantity, unit_price_cents)) > 1;  -- attendu : 0 ligne

\echo '== A2. Doublon produit (réception) =='
SELECT product_id, COUNT(*) AS n FROM reception.products_raw GROUP BY product_id HAVING COUNT(*) > 1;  -- attendu : 3

\echo '== A3. Lignes d''articles dont la commande n''existe pas =='
SELECT i.order_item_id, i.order_id,
       i.quantity::integer * i.unit_price_cents::integer AS montant_cents
FROM reception.order_items_raw i
WHERE NOT EXISTS (SELECT 1 FROM reception.orders_raw o WHERE o.order_id = i.order_id);  -- attendu : 801 -> 9999

\echo '== A3bis. Paiements sans commande (métier) =='
SELECT p.payment_id, p.order_id FROM metier.payments p
WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = p.order_id);          -- attendu : 0 ligne

\echo '== B1. Jointure directe articles x paiements (INCORRECT, démonstration) =='
SELECT COUNT(*)                                AS lignes_jointes,      -- attendu : 960
       SUM(p.amount_cents)                     AS paiements_naif,      -- attendu : 6 543 500
       SUM(i.quantity * i.unit_price_cents)    AS lignes_naif          -- > 3 271 750
FROM metier.order_items i
JOIN metier.payments p ON p.order_id = i.order_id;

\echo '== B2. Pré-agrégation au grain commande (CORRECT) =='
WITH l AS (SELECT order_id, SUM(quantity * unit_price_cents) AS lignes_cents
           FROM metier.order_items GROUP BY order_id),
     p AS (SELECT order_id, SUM(amount_cents) AS paye_cents
           FROM metier.payments GROUP BY order_id)
SELECT COUNT(*)                                        AS commandes,            -- attendu : 400
       SUM(l.lignes_cents)                             AS lignes,               -- attendu : 3 271 750
       SUM(p.paye_cents)                               AS paiements,            -- attendu : 3 271 750
       COUNT(*) FILTER (WHERE l.lignes_cents IS DISTINCT FROM p.paye_cents) AS ecarts  -- attendu : 0
FROM l JOIN p ON p.order_id = l.order_id;

\echo '== C. Quatre définitions du CA (centimes) =='
WITH lignes AS (
  SELECT o.order_id, o.status, SUM(i.quantity * i.unit_price_cents) AS montant
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  GROUP BY o.order_id, o.status)
SELECT 'completed (retenue)'  AS definition, COUNT(*) AS commandes, SUM(montant) AS cents FROM lignes WHERE status = 'completed'
UNION ALL
SELECT 'completed + pending',  COUNT(*), SUM(montant) FROM lignes WHERE status IN ('completed','pending')
UNION ALL
SELECT 'toutes commandes',     COUNT(*), SUM(montant) FROM lignes
UNION ALL
SELECT 'encaissé (captured)',  COUNT(DISTINCT order_id), SUM(amount_cents) FROM metier.payments WHERE status = 'captured';

\echo '== D. Commandes annulées avec paiement encaissé =='
SELECT COUNT(DISTINCT o.order_id) AS commandes, SUM(p.amount_cents) AS encaisse_cents   -- encaisse attendu : 328 375
FROM metier.orders o JOIN metier.payments p ON p.order_id = o.order_id
WHERE o.status = 'cancelled' AND p.status = 'captured';
