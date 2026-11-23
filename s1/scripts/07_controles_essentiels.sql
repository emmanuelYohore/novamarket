-- 07_controles_essentiels.sql : M5 - rejoue les contrôles clés, une ligne OK/KO chacun.
-- Valeurs attendues relevées en M2/M3. Adapter si la source change.
WITH c(controle, obtenu, attendu) AS (
  SELECT 'customers intégrés',            (SELECT COUNT(*) FROM metier.customers),   180
  UNION ALL SELECT 'orders intégrées',    (SELECT COUNT(*) FROM metier.orders),      400
  UNION ALL SELECT 'order_items intégrées',(SELECT COUNT(*) FROM metier.order_items),800
  UNION ALL SELECT 'payments intégrés',   (SELECT COUNT(*) FROM metier.payments),    480
  UNION ALL SELECT 'products intégrés',   (SELECT COUNT(*) FROM metier.products),     24
  UNION ALL SELECT 'categories intégrées',(SELECT COUNT(*) FROM metier.categories),   10
  UNION ALL SELECT 'commandes completed', (SELECT COUNT(*) FROM metier.orders WHERE status='completed'), 320
  UNION ALL SELECT 'clients sans commande',
         (SELECT COUNT(*) FROM metier.customers c WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.customer_id=c.customer_id)), 30
  UNION ALL SELECT 'CA completed (cents)',
         (SELECT SUM(i.quantity*i.unit_price_cents) FROM metier.order_items i JOIN metier.orders o USING(order_id) WHERE o.status='completed'), 2621000
  UNION ALL SELECT 'paiements captured (cents)', (SELECT SUM(amount_cents) FROM metier.payments WHERE status='captured'), 2949375
  UNION ALL SELECT 'paiements pending (cents)',  (SELECT SUM(amount_cents) FROM metier.payments WHERE status='pending'),  322375
  UNION ALL SELECT 'lignes orphelines en métier',
         (SELECT COUNT(*) FROM metier.order_items i WHERE NOT EXISTS (SELECT 1 FROM metier.orders o WHERE o.order_id=i.order_id)), 0
  UNION ALL SELECT 'écarts lignes/paiements par commande',
         (SELECT COUNT(*) FROM (SELECT order_id, SUM(quantity*unit_price_cents) s FROM metier.order_items GROUP BY 1) l
                          JOIN (SELECT order_id, SUM(amount_cents) s FROM metier.payments GROUP BY 1) p USING(order_id)
          WHERE l.s IS DISTINCT FROM p.s), 0
)
SELECT controle, obtenu, attendu, CASE WHEN obtenu = attendu THEN 'OK' ELSE 'KO' END AS verdict
FROM c;
