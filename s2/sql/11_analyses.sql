-- =====================================================================
-- S2 · M2-M5 · 11_analyses.sql : fenêtres analytiques et CTE
-- Périmètre de vente par défaut : lignes des commandes 'completed' (règle S1).
-- Montants en centimes. Lecture seule, rejouable.
-- =====================================================================
\set ON_ERROR_STOP on
\pset footer off

-- ---------------------------------------------------------------------
-- M2a. Classement des produits (grain de sortie : 1 ligne = 1 produit)
--  RANK global + RANK dans la catégorie (PARTITION BY category_id).
--  Ex aequo : RANK laisse un trou, DENSE_RANK non ; ROW_NUMBER départage par product_id.
-- ---------------------------------------------------------------------
\echo '== M2a. Classement des produits par CA completed =='
WITH ca_produit AS (               -- grain : 1 ligne = 1 produit
  SELECT p.product_id, p.category_id, c.category_name,
         sum(i.quantity * i.unit_price_cents) AS ca_cents,
         sum(i.quantity) AS unites
  FROM metier.order_items i
  JOIN metier.orders o     ON o.order_id = i.order_id AND o.status = 'completed'
  JOIN metier.products p   ON p.product_id = i.product_id
  JOIN metier.categories c ON c.category_id = p.category_id
  GROUP BY p.product_id, p.category_id, c.category_name)
SELECT product_id, category_name, ca_cents, unites,
       rank()       OVER (ORDER BY ca_cents DESC)                          AS rang_global,
       dense_rank() OVER (ORDER BY ca_cents DESC)                          AS rang_dense,
       rank()       OVER (PARTITION BY category_id ORDER BY ca_cents DESC) AS rang_categorie,
       row_number() OVER (ORDER BY ca_cents DESC, product_id)              AS rang_unique
FROM ca_produit
ORDER BY rang_global, product_id;

\echo '== M2a bis. Ex aequo détectés dans le classement produit =='
WITH ca_produit AS (
  SELECT i.product_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.order_items i JOIN metier.orders o ON o.order_id = i.order_id AND o.status = 'completed'
  GROUP BY i.product_id)
SELECT ca_cents, count(*) AS produits_ex_aequo, string_agg(product_id::text, ', ' ORDER BY product_id) AS produits
FROM ca_produit GROUP BY ca_cents HAVING count(*) > 1 ORDER BY ca_cents DESC;

-- ---------------------------------------------------------------------
-- M2b. Classement des clients (grain : 1 ligne = 1 client ayant au moins
--  une commande completed). Top 10 + statistiques d'ex aequo.
-- ---------------------------------------------------------------------
\echo '== M2b. Top 10 clients (RANK, ex aequo inclus) =='
WITH ca_client AS (
  SELECT o.customer_id, count(DISTINCT o.order_id) AS commandes,
         sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed'
  GROUP BY o.customer_id),
classe AS (
  SELECT *, rank() OVER (ORDER BY ca_cents DESC) AS rang,
            dense_rank() OVER (ORDER BY ca_cents DESC) AS rang_dense
  FROM ca_client)
SELECT customer_id, commandes, ca_cents, rang, rang_dense FROM classe WHERE rang <= 10 ORDER BY rang, customer_id;

\echo '== M2b bis. Ex aequo sur l''ensemble des clients classés =='
WITH ca_client AS (
  SELECT o.customer_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed' GROUP BY o.customer_id)
SELECT count(*) AS clients_classes, count(DISTINCT ca_cents) AS valeurs_distinctes,
       count(*) - count(DISTINCT ca_cents) AS clients_en_ex_aequo_au_dela_du_1er
FROM ca_client;

-- ---------------------------------------------------------------------
-- M2c. Effet des duplications sur un classement :
--  version "naïve" = lignes de réception S1 (doublon order_item 7 inclus)
--  jointes au catalogue brut S2 (product_id 3 en double).
-- ---------------------------------------------------------------------
\echo '== M2c. Effet des doublons sur le classement produit =='
WITH propre AS (
  SELECT i.product_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.order_items i JOIN metier.orders o ON o.order_id = i.order_id AND o.status = 'completed'
  GROUP BY i.product_id),
naif AS (
  SELECT r.product_id::int AS product_id, sum(r.quantity::int * r.unit_price_cents::int) AS ca_cents
  FROM reception.order_items_raw r
  JOIN metier.orders o ON o.order_id = r.order_id::int AND o.status = 'completed'
  JOIN reception_s2.products_raw p ON p.product_id = r.product_id      -- 2 fiches pour le produit 3
  GROUP BY r.product_id::int),
cmp AS (
  SELECT p.product_id, p.ca_cents AS ca_propre, n.ca_cents AS ca_naif,
         rank() OVER (ORDER BY p.ca_cents DESC) AS rang_propre,
         rank() OVER (ORDER BY n.ca_cents DESC) AS rang_naif
  FROM propre p JOIN naif n USING (product_id))
SELECT product_id, ca_propre, ca_naif, ca_naif - ca_propre AS ecart_cents, rang_propre, rang_naif
FROM cmp WHERE ca_naif <> ca_propre OR rang_propre <> rang_naif OR rang_propre <= 3
ORDER BY rang_propre, product_id;

-- ---------------------------------------------------------------------
-- M3. Évolution par période avec LAG() / LEAD()
--  Grain : 1 ligne = 1 semaine ISO (lundi). Couverture = jours présents
--  dans les commandes (toutes statuts) / 7.
-- ---------------------------------------------------------------------
\echo '== M3a. CA completed hebdomadaire, LAG/LEAD et couverture =='
WITH bornes AS (SELECT min(ordered_on) AS d0, max(ordered_on) AS d1 FROM metier.orders),
semaines AS (                       -- calendrier complet : aucune semaine manquante ne peut être sautée
  SELECT generate_series(date_trunc('week', d0), date_trunc('week', d1), interval '1 week')::date AS semaine FROM bornes),
ventes AS (
  SELECT date_trunc('week', o.ordered_on)::date AS semaine,
         sum(i.quantity * i.unit_price_cents) AS ca_cents,
         count(DISTINCT o.order_id) AS commandes
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed' GROUP BY 1),
jours AS (
  SELECT date_trunc('week', ordered_on)::date AS semaine, count(DISTINCT ordered_on) AS jours_observes
  FROM metier.orders GROUP BY 1),
serie AS (
  SELECT s.semaine, COALESCE(j.jours_observes, 0) AS jours, COALESCE(v.commandes, 0) AS commandes,
         COALESCE(v.ca_cents, 0) AS ca_cents
  FROM semaines s LEFT JOIN ventes v USING (semaine) LEFT JOIN jours j USING (semaine))
SELECT semaine, jours,
       CASE WHEN jours < 7 THEN 'incomplète' ELSE 'complète' END AS couverture,
       commandes, ca_cents,
       lag(ca_cents)  OVER w AS ca_sem_prec,
       lead(ca_cents) OVER w AS ca_sem_suiv,
       ca_cents - lag(ca_cents) OVER w AS variation_cents,
       round(100.0 * (ca_cents - lag(ca_cents) OVER w) / NULLIF(lag(ca_cents) OVER w, 0), 1) AS variation_pct,
       round(ca_cents::numeric / NULLIF(jours, 0)) AS ca_par_jour_cents
FROM serie
WINDOW w AS (ORDER BY semaine)
ORDER BY semaine;

\echo '== M3b. CA completed mensuel et couverture =='
WITH m AS (
  SELECT date_trunc('month', o.ordered_on)::date AS mois,
         count(DISTINCT o.ordered_on) AS jours_observes,
         max(o.ordered_on) AS dernier_jour,
         sum(i.quantity * i.unit_price_cents) FILTER (WHERE o.status = 'completed') AS ca_cents
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  GROUP BY 1)
SELECT mois, jours_observes,
       extract(day FROM (mois + interval '1 month' - interval '1 day'))::int AS jours_du_mois,
       dernier_jour, ca_cents,
       lag(ca_cents) OVER (ORDER BY mois) AS ca_mois_prec,
       round(100.0 * (ca_cents - lag(ca_cents) OVER (ORDER BY mois)) / lag(ca_cents) OVER (ORDER BY mois), 1) AS variation_pct
FROM m ORDER BY mois;

\echo '== M3c. Cohérence ventes / catalogue : ventes avant la date de mise en vente =='
SELECT p.product_id, p.first_listed_on, min(o.ordered_on) AS premiere_vente,
       count(*) AS lignes_avant_listing,
       count(*) FILTER (WHERE o.status = 'completed') AS dont_completed,
       sum(i.quantity * i.unit_price_cents) FILTER (WHERE o.status = 'completed') AS ca_completed_concerne
FROM metier.order_items i
JOIN metier.orders o   ON o.order_id = i.order_id
JOIN metier.products p ON p.product_id = i.product_id
WHERE o.ordered_on < p.first_listed_on
GROUP BY p.product_id, p.first_listed_on;

-- ---------------------------------------------------------------------
-- M4. Segmentation NTILE(4)
--  Population : clients ayant au moins une commande completed (120).
--  Mesure : CA completed. Ordre : CA décroissant puis customer_id (déterministe).
-- ---------------------------------------------------------------------
\echo '== M4a. Quartiles de clients (NTILE 4) =='
WITH ca_client AS (
  SELECT o.customer_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed' GROUP BY o.customer_id),
seg AS (SELECT *, ntile(4) OVER (ORDER BY ca_cents DESC, customer_id) AS quartile FROM ca_client)
SELECT quartile, count(*) AS clients, min(ca_cents) AS ca_min, max(ca_cents) AS ca_max,
       sum(ca_cents) AS ca_total,
       round(100.0 * sum(ca_cents) / sum(sum(ca_cents)) OVER (), 1) AS part_ca_pct
FROM seg GROUP BY quartile ORDER BY quartile;

\echo '== M4b. Égalités coupées par une frontière de quartile =='
WITH ca_client AS (
  SELECT o.customer_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.orders o JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed' GROUP BY o.customer_id),
seg AS (SELECT *, ntile(4) OVER (ORDER BY ca_cents DESC, customer_id) AS quartile FROM ca_client)
SELECT ca_cents, count(*) AS clients, array_agg(DISTINCT quartile ORDER BY quartile) AS quartiles
FROM seg GROUP BY ca_cents HAVING count(DISTINCT quartile) > 1 ORDER BY ca_cents DESC;

\echo '== M4c. Population hors segmentation =='
SELECT count(*) AS clients_total,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id)) AS sans_commande,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id)
                          AND NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id AND o.status = 'completed')) AS sans_completed
FROM metier.customers c;

-- ---------------------------------------------------------------------
-- M5. Hiérarchie des catégories : WITH RECURSIVE + contrôle des cycles
-- ---------------------------------------------------------------------
\echo '== M5a. Arbre des catégories (chemin, profondeur, cycle) =='
WITH RECURSIVE arbre AS (
  SELECT category_id, category_name, parent_category_id, category_id AS racine_id,
         0 AS profondeur, category_name::text AS chemin
  FROM metier.categories WHERE parent_category_id IS NULL
  UNION ALL
  SELECT c.category_id, c.category_name, c.parent_category_id, a.racine_id,
         a.profondeur + 1, a.chemin || ' > ' || c.category_name
  FROM metier.categories c JOIN arbre a ON c.parent_category_id = a.category_id
  WHERE a.profondeur < 10                         -- garde-fou
) CYCLE category_id SET est_cycle USING parcours
SELECT category_id, profondeur, chemin, est_cycle FROM arbre ORDER BY chemin;

\echo '== M5b. Contrôle des rattachements =='
WITH RECURSIVE arbre AS (
  SELECT category_id FROM metier.categories WHERE parent_category_id IS NULL
  UNION ALL
  SELECT c.category_id FROM metier.categories c JOIN arbre a ON c.parent_category_id = a.category_id)
SELECT (SELECT count(*) FROM metier.categories) AS categories,
       count(*) AS atteintes_depuis_racines,
       count(DISTINCT category_id) AS distinctes,
       (SELECT count(*) FROM metier.categories) - count(DISTINCT category_id) AS non_rattachees_ou_cycle
FROM arbre;

\echo '== M5c. CA completed consolidé par branche (chaque nœud cumule ses descendants) =='
WITH RECURSIVE fermeture AS (        -- couple (ancêtre, descendant), y compris soi-même
  SELECT category_id AS ancetre, category_id AS descendant, 0 AS distance FROM metier.categories
  UNION ALL
  SELECT f.ancetre, c.category_id, f.distance + 1
  FROM fermeture f JOIN metier.categories c ON c.parent_category_id = f.descendant),
ca_feuille AS (                       -- grain : 1 ligne = 1 catégorie de rattachement direct
  SELECT p.category_id, sum(i.quantity * i.unit_price_cents) AS ca_cents
  FROM metier.order_items i
  JOIN metier.orders o   ON o.order_id = i.order_id AND o.status = 'completed'
  JOIN metier.products p ON p.product_id = i.product_id
  GROUP BY p.category_id),
profondeur AS (
  SELECT descendant AS category_id, max(distance) AS niveau
  FROM fermeture f JOIN metier.categories r ON r.category_id = f.ancetre AND r.parent_category_id IS NULL
  GROUP BY descendant)
SELECT c.category_id, repeat('   ', pr.niveau) || c.category_name AS categorie, pr.niveau,
       COALESCE(sum(cf.ca_cents), 0) AS ca_branche_cents,
       round(100.0 * COALESCE(sum(cf.ca_cents), 0) / (SELECT sum(ca_cents) FROM ca_feuille), 1) AS part_pct
FROM metier.categories c
JOIN profondeur pr ON pr.category_id = c.category_id
LEFT JOIN fermeture f  ON f.ancetre = c.category_id
LEFT JOIN ca_feuille cf ON cf.category_id = f.descendant
GROUP BY c.category_id, c.category_name, pr.niveau
ORDER BY pr.niveau, ca_branche_cents DESC;

\echo '== M5d. Contrôle de double comptage : somme des racines = CA total =='
WITH RECURSIVE fermeture AS (
  SELECT category_id AS ancetre, category_id AS descendant FROM metier.categories WHERE parent_category_id IS NULL
  UNION ALL
  SELECT f.ancetre, c.category_id FROM fermeture f JOIN metier.categories c ON c.parent_category_id = f.descendant)
SELECT (SELECT sum(i.quantity * i.unit_price_cents) FROM metier.order_items i
          JOIN metier.orders o ON o.order_id = i.order_id AND o.status = 'completed') AS ca_total_cents,
       sum(i.quantity * i.unit_price_cents) AS somme_des_racines_cents,
       (SELECT count(*) FROM (SELECT descendant FROM fermeture GROUP BY descendant HAVING count(*) > 1) x) AS categories_sous_plusieurs_racines
FROM fermeture f
JOIN metier.products p ON p.category_id = f.descendant
JOIN metier.order_items i ON i.product_id = p.product_id
JOIN metier.orders o ON o.order_id = i.order_id AND o.status = 'completed';
