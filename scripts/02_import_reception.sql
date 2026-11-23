-- =====================================================================
-- S1 · M2 · 02_import_reception.sql : chargement BRUT des fichiers
-- Aucun nettoyage ici : on veut voir exactement ce que la source contient.
-- Chemins du conteneur : /s1/donnees (monté en lecture seule).
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;

TRUNCATE reception.categories_raw, reception.products_raw, reception.customers_raw,
         reception.orders_raw, reception.order_items_raw, reception.payments_raw
         RESTART IDENTITY;

\copy reception.categories_raw  (category_id, category_name, parent_category_id) FROM '/s1/donnees/categories.csv'  WITH (FORMAT csv, HEADER true)
\copy reception.products_raw    (product_id, sku, product_name, category_id, first_listed_on) FROM '/s1/donnees/products.csv' WITH (FORMAT csv, HEADER true)
\copy reception.customers_raw   (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER true)
\copy reception.orders_raw      (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER true)
\copy reception.order_items_raw (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER true)

-- NDJSON : séparateur et guillemet de contrôle absents du JSON -> la ligne entière arrive dans une seule colonne
\copy reception.payments_raw (ligne) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

COMMIT;

SELECT 'categories' AS source, count(*) AS lignes_recues FROM reception.categories_raw
UNION ALL SELECT 'products',    count(*) FROM reception.products_raw
UNION ALL SELECT 'customers',   count(*) FROM reception.customers_raw
UNION ALL SELECT 'orders',      count(*) FROM reception.orders_raw
UNION ALL SELECT 'order_items', count(*) FROM reception.order_items_raw
UNION ALL SELECT 'payments',    count(*) FROM reception.payments_raw;
