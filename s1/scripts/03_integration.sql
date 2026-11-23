-- =====================================================================
-- S1 · M2 · 03_integration.sql : réception -> métier (+ journal des rejets)
-- Principe : chaque table de réception a une vue v_<table> qui attribue à
-- chaque ligne un MOTIF de rejet (NULL = ligne valide). Les lignes à motif
-- vont dans rejets.journal, les autres dans metier.* après conversion de type.
-- Ordre d'intégration = ordre des dépendances (parents avant enfants).
-- Règle de doublon : on garde la 1re occurrence (plus petit ligne_no).
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;

TRUNCATE rejets.journal RESTART IDENTITY;
TRUNCATE metier.payments, metier.order_items, metier.orders, metier.customers,
         metier.products, metier.categories;

-- ---- categories ----
CREATE OR REPLACE VIEW reception.v_categories AS
SELECT r.ligne_no, r.category_id, r.category_name, r.parent_category_id,
 CASE
  WHEN r.category_id IS NULL OR NOT pg_input_is_valid(r.category_id, 'integer')
       THEN 'cle_invalide'
  WHEN r.category_name IS NULL OR btrim(r.category_name) = ''
       THEN 'nom_manquant'
  WHEN r.parent_category_id IS NOT NULL AND NOT pg_input_is_valid(r.parent_category_id,'integer')
       THEN 'parent_invalide'
  WHEN r.parent_category_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM reception.categories_raw p WHERE p.category_id = r.parent_category_id)
       THEN 'parent_inconnu'
  WHEN EXISTS (SELECT 1 FROM reception.categories_raw d WHERE d.category_id = r.category_id AND d.ligne_no < r.ligne_no AND d.category_name IS NOT DISTINCT FROM r.category_name AND d.parent_category_id IS NOT DISTINCT FROM r.parent_category_id)
       THEN 'doublon_exact'
  WHEN EXISTS (SELECT 1 FROM reception.categories_raw d WHERE d.category_id = r.category_id AND d.ligne_no < r.ligne_no)
       THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM reception.categories_raw r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'categories.csv', ligne_no, category_id, motif, (to_jsonb(v) - 'motif' - 'ligne_no')::text
FROM reception.v_categories v WHERE motif IS NOT NULL;
INSERT INTO metier.categories (category_id, category_name, parent_category_id)
SELECT category_id::integer, btrim(category_name), parent_category_id::integer
FROM reception.v_categories WHERE motif IS NULL;

-- ---- products ----
CREATE OR REPLACE VIEW reception.v_products AS
SELECT r.ligne_no, r.product_id, r.sku, r.product_name, r.category_id, r.first_listed_on,
 CASE
  WHEN r.product_id IS NULL OR NOT pg_input_is_valid(r.product_id, 'integer')
       THEN 'cle_invalide'
  WHEN r.sku IS NULL OR btrim(r.sku) = ''
       THEN 'sku_manquant'
  WHEN r.product_name IS NULL OR btrim(r.product_name) = ''
       THEN 'nom_manquant'
  WHEN r.category_id IS NULL OR NOT pg_input_is_valid(r.category_id, 'integer')
       THEN 'categorie_invalide'
  WHEN r.first_listed_on IS NULL OR r.first_listed_on !~ '^\d{4}-\d{2}-\d{2}$' OR NOT pg_input_is_valid(r.first_listed_on, 'date')
       THEN 'date_invalide'
  WHEN NOT EXISTS (SELECT 1 FROM metier.categories c WHERE c.category_id = r.category_id::integer)
       THEN 'categorie_inconnue'
  WHEN EXISTS (SELECT 1 FROM reception.products_raw d WHERE d.product_id = r.product_id AND d.ligne_no < r.ligne_no AND d.sku IS NOT DISTINCT FROM r.sku AND d.product_name IS NOT DISTINCT FROM r.product_name AND d.category_id IS NOT DISTINCT FROM r.category_id AND d.first_listed_on IS NOT DISTINCT FROM r.first_listed_on)
       THEN 'doublon_exact'
  WHEN EXISTS (SELECT 1 FROM reception.products_raw d WHERE d.product_id = r.product_id AND d.ligne_no < r.ligne_no)
       THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM reception.products_raw r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'products.csv', ligne_no, product_id, motif, (to_jsonb(v) - 'motif' - 'ligne_no')::text
FROM reception.v_products v WHERE motif IS NOT NULL;
INSERT INTO metier.products (product_id, sku, product_name, category_id, first_listed_on)
SELECT product_id::integer, btrim(sku), btrim(product_name), category_id::integer, first_listed_on::date
FROM reception.v_products WHERE motif IS NULL;

-- ---- customers ----
CREATE OR REPLACE VIEW reception.v_customers AS
SELECT r.ligne_no, r.customer_id, r.customer_name, r.city,
 CASE
  WHEN r.customer_id IS NULL OR NOT pg_input_is_valid(r.customer_id, 'integer')
       THEN 'cle_invalide'
  WHEN r.customer_name IS NULL OR btrim(r.customer_name) = ''
       THEN 'nom_manquant'
  WHEN r.city IS NULL OR btrim(r.city) = ''
       THEN 'ville_manquante'
  WHEN EXISTS (SELECT 1 FROM reception.customers_raw d WHERE d.customer_id = r.customer_id AND d.ligne_no < r.ligne_no AND d.customer_name IS NOT DISTINCT FROM r.customer_name AND d.city IS NOT DISTINCT FROM r.city)
       THEN 'doublon_exact'
  WHEN EXISTS (SELECT 1 FROM reception.customers_raw d WHERE d.customer_id = r.customer_id AND d.ligne_no < r.ligne_no)
       THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM reception.customers_raw r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'customers.csv', ligne_no, customer_id, motif, (to_jsonb(v) - 'motif' - 'ligne_no')::text
FROM reception.v_customers v WHERE motif IS NOT NULL;
INSERT INTO metier.customers (customer_id, customer_name, city)
SELECT customer_id::integer, btrim(customer_name), btrim(city)
FROM reception.v_customers WHERE motif IS NULL;

-- ---- orders ----
CREATE OR REPLACE VIEW reception.v_orders AS
SELECT r.ligne_no, r.order_id, r.customer_id, r.ordered_on, r.status,
 CASE
  WHEN r.order_id IS NULL OR NOT pg_input_is_valid(r.order_id, 'integer')
       THEN 'cle_invalide'
  WHEN r.customer_id IS NULL OR NOT pg_input_is_valid(r.customer_id, 'integer')
       THEN 'client_invalide'
  WHEN r.ordered_on IS NULL OR r.ordered_on !~ '^\d{4}-\d{2}-\d{2}$' OR NOT pg_input_is_valid(r.ordered_on, 'date')
       THEN 'date_invalide'
  WHEN r.status IS NULL OR r.status NOT IN ('completed','pending','cancelled')
       THEN 'statut_inconnu'
  WHEN NOT EXISTS (SELECT 1 FROM metier.customers c WHERE c.customer_id = r.customer_id::integer)
       THEN 'client_inconnu'
  WHEN EXISTS (SELECT 1 FROM reception.orders_raw d WHERE d.order_id = r.order_id AND d.ligne_no < r.ligne_no AND d.customer_id IS NOT DISTINCT FROM r.customer_id AND d.ordered_on IS NOT DISTINCT FROM r.ordered_on AND d.status IS NOT DISTINCT FROM r.status)
       THEN 'doublon_exact'
  WHEN EXISTS (SELECT 1 FROM reception.orders_raw d WHERE d.order_id = r.order_id AND d.ligne_no < r.ligne_no)
       THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM reception.orders_raw r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'orders.csv', ligne_no, order_id, motif, (to_jsonb(v) - 'motif' - 'ligne_no')::text
FROM reception.v_orders v WHERE motif IS NOT NULL;
INSERT INTO metier.orders (order_id, customer_id, ordered_on, status)
SELECT order_id::integer, customer_id::integer, ordered_on::date, status
FROM reception.v_orders WHERE motif IS NULL;

-- ---- order_items ----
CREATE OR REPLACE VIEW reception.v_order_items AS
SELECT r.ligne_no, r.order_item_id, r.order_id, r.product_id, r.quantity, r.unit_price_cents,
 CASE
  WHEN r.order_item_id IS NULL OR NOT pg_input_is_valid(r.order_item_id, 'integer')
       THEN 'cle_invalide'
  WHEN r.order_id IS NULL OR NOT pg_input_is_valid(r.order_id, 'integer')
       THEN 'commande_invalide'
  WHEN r.product_id IS NULL OR NOT pg_input_is_valid(r.product_id, 'integer')
       THEN 'produit_invalide'
  WHEN r.quantity IS NULL OR NOT pg_input_is_valid(r.quantity, 'integer')
       THEN 'quantite_invalide'
  WHEN r.unit_price_cents IS NULL OR NOT pg_input_is_valid(r.unit_price_cents, 'integer')
       THEN 'prix_invalide'
  WHEN r.quantity::integer <= 0
       THEN 'quantite_non_positive'
  WHEN r.unit_price_cents::integer <= 0
       THEN 'prix_non_positif'
  WHEN NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = r.order_id::integer)
       THEN 'commande_orpheline'
  WHEN NOT EXISTS (SELECT 1 FROM metier.products p WHERE p.product_id = r.product_id::integer)
       THEN 'produit_inconnu'
  WHEN EXISTS (SELECT 1 FROM reception.order_items_raw d WHERE d.order_item_id = r.order_item_id AND d.ligne_no < r.ligne_no AND d.order_id IS NOT DISTINCT FROM r.order_id AND d.product_id IS NOT DISTINCT FROM r.product_id AND d.quantity IS NOT DISTINCT FROM r.quantity AND d.unit_price_cents IS NOT DISTINCT FROM r.unit_price_cents)
       THEN 'doublon_exact'
  WHEN EXISTS (SELECT 1 FROM reception.order_items_raw d WHERE d.order_item_id = r.order_item_id AND d.ligne_no < r.ligne_no)
       THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM reception.order_items_raw r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'order_items.csv', ligne_no, order_item_id, motif, (to_jsonb(v) - 'motif' - 'ligne_no')::text
FROM reception.v_order_items v WHERE motif IS NOT NULL;
INSERT INTO metier.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT order_item_id::integer, order_id::integer, product_id::integer, quantity::integer, unit_price_cents::integer
FROM reception.v_order_items WHERE motif IS NULL;

-- ---- payments (NDJSON : on déplie le JSON, puis mêmes contrôles) ----
CREATE OR REPLACE VIEW reception.v_payments AS
WITH d AS (
  SELECT ligne_no, ligne,
         CASE WHEN pg_input_is_valid(ligne, 'jsonb') THEN ligne::jsonb END AS doc
  FROM reception.payments_raw),
x AS (
  SELECT ligne_no, ligne,
         doc IS NULL OR jsonb_typeof(doc) <> 'object' AS json_invalide,
         doc->>'payment_id' AS payment_id, doc->>'order_id' AS order_id,
         doc->>'paid_on' AS paid_on, doc->>'amount_cents' AS amount_cents, doc->>'status' AS status
  FROM d),
r AS (
  SELECT x.*,
         row_number() OVER (PARTITION BY payment_id ORDER BY ligne_no) AS rang_cle,
         row_number() OVER (PARTITION BY payment_id, order_id, paid_on, amount_cents, status ORDER BY ligne_no) AS rang_contenu
  FROM x)
SELECT r.ligne_no, r.ligne, r.payment_id, r.order_id, r.paid_on, r.amount_cents, r.status,
 CASE
  WHEN r.json_invalide THEN 'json_invalide'
  WHEN r.payment_id IS NULL OR NOT pg_input_is_valid(r.payment_id, 'integer') THEN 'cle_invalide'
  WHEN r.order_id IS NULL OR NOT pg_input_is_valid(r.order_id, 'integer') THEN 'commande_invalide'
  WHEN r.paid_on IS NULL OR r.paid_on !~ '^\d{4}-\d{2}-\d{2}$' OR NOT pg_input_is_valid(r.paid_on, 'date') THEN 'date_invalide'
  WHEN r.amount_cents IS NULL OR NOT pg_input_is_valid(r.amount_cents, 'integer') THEN 'montant_invalide'
  WHEN r.amount_cents::integer <= 0 THEN 'montant_non_positif'
  WHEN r.status IS NULL OR r.status NOT IN ('captured','pending') THEN 'statut_inconnu'
  WHEN NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id = r.order_id::integer) THEN 'commande_orpheline'
  WHEN r.rang_contenu > 1 THEN 'doublon_exact'
  WHEN r.rang_cle > 1 THEN 'cle_dupliquee_contenu_different'
 END AS motif
FROM r;

INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 'payments.ndjson', ligne_no, payment_id, motif, ligne
FROM reception.v_payments WHERE motif IS NOT NULL;
INSERT INTO metier.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT payment_id::integer, order_id::integer, paid_on::date, amount_cents::integer, status
FROM reception.v_payments WHERE motif IS NULL;

COMMIT;
