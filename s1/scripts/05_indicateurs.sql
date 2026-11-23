-- =====================================================================
-- S1 · M3 · 05_indicateurs.sql : indicateurs commerciaux (montants en centimes)
-- Règle d'or : on agrège chaque grain SEPAREMENT, on joint ensuite au grain commande.
-- =====================================================================

-- I1. Commandes par statut --------------------------------------------
SELECT status, count(*) AS nb_commandes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM metier.orders GROUP BY status ORDER BY nb_commandes DESC, status;

-- I2. Clients sans commande -------------------------------------------
SELECT count(*) AS clients_sans_commande,
       (SELECT count(*) FROM metier.customers) AS clients_total
FROM metier.customers c
WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id = c.customer_id);

-- I3. CA des commandes terminées + panier moyen ------------------------
-- CA = somme des (quantity * unit_price_cents) des lignes des commandes 'completed'.
-- Panier moyen = CA / nombre de COMMANDES terminées (dénominateur = commandes distinctes,
-- pas les lignes, pas les clients). Toute commande a au moins une ligne (cf. contrôle C3).
WITH montant_commande AS (
  SELECT o.order_id, sum(i.quantity * i.unit_price_cents) AS montant_cents
  FROM metier.orders o
  JOIN metier.order_items i ON i.order_id = o.order_id
  WHERE o.status = 'completed'
  GROUP BY o.order_id)
SELECT count(*)                                         AS commandes_terminees,
       sum(montant_cents)                               AS ca_cents,
       round(sum(montant_cents) / 100.0, 2)             AS ca_euros,
       round(sum(montant_cents)::numeric / count(*), 2) AS panier_moyen_cents,
       round(sum(montant_cents)::numeric / count(*) / 100, 2) AS panier_moyen_euros
FROM montant_commande;

-- Dénominateurs alternatifs (pour expliciter le choix) :
SELECT 'par commande terminée'  AS denominateur, count(DISTINCT o.order_id) AS n,
       round(sum(i.quantity*i.unit_price_cents)::numeric / count(DISTINCT o.order_id) / 100, 2) AS moyenne_euros
FROM metier.orders o JOIN metier.order_items i USING (order_id) WHERE o.status='completed'
UNION ALL
SELECT 'par ligne d''article', count(*),
       round(avg(i.quantity*i.unit_price_cents)::numeric / 100, 2)
FROM metier.orders o JOIN metier.order_items i USING (order_id) WHERE o.status='completed'
UNION ALL
SELECT 'par client ayant commandé (terminée)', count(DISTINCT o.customer_id),
       round(sum(i.quantity*i.unit_price_cents)::numeric / count(DISTINCT o.customer_id) / 100, 2)
FROM metier.orders o JOIN metier.order_items i USING (order_id) WHERE o.status='completed';

-- I4. Rapprochement lignes / paiements, au grain COMMANDE ---------------
-- Deux sous-requêtes agrégées séparément (1 ligne par commande chacune), puis jointure.
WITH lignes AS (
  SELECT order_id, sum(quantity * unit_price_cents) AS lignes_cents
  FROM metier.order_items GROUP BY order_id),
paiements AS (
  SELECT order_id,
         sum(amount_cents) FILTER (WHERE status = 'captured') AS encaisse_cents,
         sum(amount_cents) FILTER (WHERE status = 'pending')  AS en_attente_cents,
         count(*) AS nb_paiements
  FROM metier.payments GROUP BY order_id)
SELECT o.status AS statut_commande,
       count(*)                                  AS commandes,
       sum(l.lignes_cents)                       AS lignes_cents,
       COALESCE(sum(p.encaisse_cents), 0)        AS encaisse_cents,
       COALESCE(sum(p.en_attente_cents), 0)      AS en_attente_cents,
       sum(l.lignes_cents) - COALESCE(sum(p.encaisse_cents),0) - COALESCE(sum(p.en_attente_cents),0) AS ecart_cents
FROM metier.orders o
LEFT JOIN lignes    l ON l.order_id = o.order_id
LEFT JOIN paiements p ON p.order_id = o.order_id
GROUP BY o.status ORDER BY o.status;

-- Commandes dont lignes <> paiements (attendu : 0)
WITH lignes AS (SELECT order_id, sum(quantity*unit_price_cents) AS l FROM metier.order_items GROUP BY order_id),
     paie   AS (SELECT order_id, sum(amount_cents) AS p FROM metier.payments GROUP BY order_id)
SELECT count(*) AS commandes_en_ecart
FROM metier.orders o LEFT JOIN lignes USING (order_id) LEFT JOIN paie USING (order_id)
WHERE COALESCE(l,0) <> COALESCE(p,0);

-- =====================================================================
-- VERIFICATIONS DE COHERENCE
-- =====================================================================
-- C1. La somme des statuts = nombre total de commandes
SELECT (SELECT count(*) FROM metier.orders) AS total_commandes,
       (SELECT sum(n) FROM (SELECT count(*) n FROM metier.orders GROUP BY status) s) AS somme_par_statut;

-- C2. CA total par statut : la somme des parts = total des lignes
SELECT o.status, sum(i.quantity*i.unit_price_cents) AS lignes_cents
FROM metier.orders o JOIN metier.order_items i USING (order_id) GROUP BY ROLLUP (o.status) ORDER BY o.status NULLS LAST;

-- C3. Toute commande a au moins une ligne et au moins un paiement (attendu : 0 / 0)
SELECT (SELECT count(*) FROM metier.orders o WHERE NOT EXISTS (SELECT 1 FROM metier.order_items i WHERE i.order_id=o.order_id)) AS sans_ligne,
       (SELECT count(*) FROM metier.orders o WHERE NOT EXISTS (SELECT 1 FROM metier.payments p WHERE p.order_id=o.order_id)) AS sans_paiement;

-- C4. Contre-exemple : la jointure DIRECTE lignes x paiements gonfle les montants
SELECT sum(i.quantity*i.unit_price_cents) AS montant_gonfle_cents,
       (SELECT sum(quantity*unit_price_cents) FROM metier.order_items) AS montant_correct_cents
FROM metier.order_items i JOIN metier.payments p ON p.order_id = i.order_id;
