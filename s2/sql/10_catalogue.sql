-- =====================================================================
-- S2 · M1 · 10_catalogue.sql : intégrer le catalogue S2 sans altérer S1
-- Rejouable. Les fichiers bruts ne sont jamais modifiés.
-- Chemin des données : /s2/donnees (copiées dans le conteneur, cf. s2/README.md)
-- =====================================================================
\set ON_ERROR_STOP on

-- 1. Réception brute (tout en text, numéro de ligne conservé)
CREATE SCHEMA IF NOT EXISTS reception_s2;
DROP TABLE IF EXISTS reception_s2.categories_raw, reception_s2.products_raw;
CREATE TABLE reception_s2.categories_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  category_id text, category_name text, parent_category_id text,
  charge_le timestamptz NOT NULL DEFAULT now());
CREATE TABLE reception_s2.products_raw (
  ligne_no bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id text, sku text, product_name text, category_id text, first_listed_on text,
  charge_le timestamptz NOT NULL DEFAULT now());

\copy reception_s2.categories_raw (category_id, category_name, parent_category_id) FROM '/s2/donnees/categories.csv' WITH (FORMAT csv, HEADER true)
\copy reception_s2.products_raw (product_id, sku, product_name, category_id, first_listed_on) FROM '/s2/donnees/products.csv' WITH (FORMAT csv, HEADER true)

\echo '== R1. Volumes reçus =='
SELECT 'categories.csv' AS fichier, count(*) AS lignes FROM reception_s2.categories_raw
UNION ALL SELECT 'products.csv', count(*) FROM reception_s2.products_raw;

\echo '== R2. Champs vides (hors parent vide = racine) =='
SELECT 'categories' AS t, count(*) FILTER (WHERE category_id IS NULL OR category_name IS NULL) AS vides,
       count(*) FILTER (WHERE parent_category_id IS NULL) AS racines
FROM reception_s2.categories_raw
UNION ALL
SELECT 'products', count(*) FILTER (WHERE product_id IS NULL OR sku IS NULL OR product_name IS NULL
                                     OR category_id IS NULL OR first_listed_on IS NULL), NULL
FROM reception_s2.products_raw;

\echo '== R3. Multiplicités à la réception (grain attendu : 1 ligne par code) =='
SELECT 'category_id' AS cle, category_id AS valeur, count(*) AS n FROM reception_s2.categories_raw GROUP BY 2 HAVING count(*) > 1
UNION ALL SELECT 'product_id', product_id, count(*) FROM reception_s2.products_raw GROUP BY 2 HAVING count(*) > 1
UNION ALL SELECT 'sku', sku, count(*) FROM reception_s2.products_raw GROUP BY 2 HAVING count(*) > 1;

\echo '== R4. Doublon exact ou contenu divergent ? =='
SELECT product_id, count(*) AS n,
       count(DISTINCT (sku, product_name, category_id, first_listed_on)) AS contenus_distincts
FROM reception_s2.products_raw GROUP BY product_id HAVING count(*) > 1;

\echo '== R5. Références : catégorie inconnue, parent inconnu =='
SELECT 'produit -> categorie inconnue' AS controle, count(*) AS n
FROM reception_s2.products_raw p
WHERE NOT EXISTS (SELECT 1 FROM reception_s2.categories_raw c WHERE c.category_id = p.category_id)
UNION ALL
SELECT 'categorie -> parent inconnu', count(*)
FROM reception_s2.categories_raw c
WHERE c.parent_category_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM reception_s2.categories_raw p WHERE p.category_id = c.parent_category_id);

\echo '== R6. Couverture des codes produit des ventes S1 =='
SELECT count(DISTINCT i.product_id) AS produits_vendus,
       count(DISTINCT i.product_id) FILTER (WHERE p.product_id IS NULL) AS vendus_absents_catalogue,
       (SELECT count(DISTINCT product_id) FROM reception_s2.products_raw) AS produits_catalogue,
       (SELECT count(*) FROM (SELECT DISTINCT product_id FROM reception_s2.products_raw
          EXCEPT SELECT product_id::text FROM metier.order_items) x) AS catalogue_sans_vente
FROM metier.order_items i
LEFT JOIN (SELECT DISTINCT product_id FROM reception_s2.products_raw) p ON p.product_id = i.product_id::text;

\echo '== R6bis. Lignes rejetées en S1 : code produit présent au catalogue ? =='
SELECT j.ligne_no, j.motif, j.contenu_brut::jsonb->>'product_id' AS product_id,
       EXISTS (SELECT 1 FROM reception_s2.products_raw p WHERE p.product_id = j.contenu_brut::jsonb->>'product_id') AS au_catalogue
FROM rejets.journal j WHERE j.source_file = 'order_items.csv' ORDER BY j.ligne_no;

\echo '== R7. Effet du doublon produit sur une jointure ventes x catalogue brut =='
SELECT (SELECT count(*) FROM metier.order_items) AS lignes_ventes,
       count(*) AS lignes_apres_jointure_brute,
       count(*) - (SELECT count(*) FROM metier.order_items) AS lignes_en_trop
FROM metier.order_items i JOIN reception_s2.products_raw p ON p.product_id = i.product_id::text;

\echo '== R8. Écart entre le catalogue S2 dédoublonné et le catalogue déjà en base (S1) =='
WITH s2c AS (SELECT DISTINCT category_id::int, btrim(category_name) AS category_name, parent_category_id::int FROM reception_s2.categories_raw),
     s2p AS (SELECT DISTINCT product_id::int, btrim(sku) AS sku, btrim(product_name) AS product_name, category_id::int, first_listed_on::date FROM reception_s2.products_raw)
SELECT 'categories S2 absentes ou différentes en base' AS ecart, count(*) FROM (SELECT * FROM s2c EXCEPT SELECT category_id, category_name, parent_category_id FROM metier.categories) a
UNION ALL SELECT 'categories en base absentes de S2', count(*) FROM (SELECT category_id, category_name, parent_category_id FROM metier.categories EXCEPT SELECT * FROM s2c) b
UNION ALL SELECT 'produits S2 absents ou différents en base', count(*) FROM (SELECT * FROM s2p EXCEPT SELECT product_id, sku, product_name, category_id, first_listed_on FROM metier.products) c
UNION ALL SELECT 'produits en base absents de S2', count(*) FROM (SELECT product_id, sku, product_name, category_id, first_listed_on FROM metier.products EXCEPT SELECT * FROM s2p) d;

-- 2. Intégration idempotente : catégories avant produits, 1re occurrence retenue,
--    ON CONFLICT DO NOTHING => aucune ligne S1 n'est modifiée.
BEGIN;
INSERT INTO metier.categories (category_id, category_name, parent_category_id)
SELECT DISTINCT ON (category_id::int) category_id::int, btrim(category_name), parent_category_id::int
FROM reception_s2.categories_raw
ORDER BY category_id::int, ligne_no
ON CONFLICT (category_id) DO NOTHING;

INSERT INTO metier.products (product_id, sku, product_name, category_id, first_listed_on)
SELECT DISTINCT ON (product_id::int) product_id::int, btrim(sku), btrim(product_name), category_id::int, first_listed_on::date
FROM reception_s2.products_raw
ORDER BY product_id::int, ligne_no
ON CONFLICT (product_id) DO NOTHING;

-- Doublon produit journalisé (traçabilité, pas de suppression de la source)
INSERT INTO rejets.journal (source_file, ligne_no, cle_source, motif, contenu_brut)
SELECT 's2/products.csv', r.ligne_no, r.product_id, 'doublon_exact', (to_jsonb(r) - 'ligne_no' - 'charge_le')::text
FROM reception_s2.products_raw r
WHERE EXISTS (SELECT 1 FROM reception_s2.products_raw d WHERE d.product_id = r.product_id AND d.ligne_no < r.ligne_no)
  AND NOT EXISTS (SELECT 1 FROM rejets.journal j WHERE j.source_file = 's2/products.csv' AND j.ligne_no = r.ligne_no);

-- Contrainte supplémentaire : une catégorie ne peut pas être son propre parent
ALTER TABLE metier.categories DROP CONSTRAINT IF EXISTS categories_parent_diff_ck;
ALTER TABLE metier.categories ADD CONSTRAINT categories_parent_diff_ck CHECK (parent_category_id <> category_id);

\echo '== R9. Comptages avant validation (attendu : 10 catégories, 24 produits) =='
SELECT (SELECT count(*) FROM metier.categories) AS categories,
       (SELECT count(*) FROM metier.products) AS produits,
       (SELECT count(*) FROM metier.order_items) AS lignes_ventes_inchangees;
COMMIT;
