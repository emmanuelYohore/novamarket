-- Mesures de niveau de cuves en atelier.
WITH mesures(cuve, date_releve, volume) AS (

    VALUES ('A', DATE '2026-09-01', 30), ('A', DATE '2026-09-02', 37),
           ('A', DATE '2026-09-03', 37), ('A', DATE '2026-09-04', 18),
           ('B', DATE '2026-09-01', 20), ('B', DATE '2026-09-02', 22)
)
SELECT cuve, date_releve, volume,
       rank() OVER (PARTITION BY cuve ORDER BY volume DESC) AS rang,
       lag(volume) OVER (PARTITION BY cuve ORDER BY date_releve) AS precedent,
       lead(volume) OVER (PARTITION BY cuve ORDER BY date_releve) AS suivant,
       ntile(2) OVER (PARTITION BY cuve ORDER BY volume DESC, date_releve) AS groupe
FROM mesures
ORDER BY cuve, date_releve;

-- Progression par paliers jusqu'à une température cible.
WITH RECURSIVE paliers(essai, temperature) AS (
    VALUES (0, 20)
    UNION ALL
    SELECT essai + 1, temperature + 5
    FROM paliers
    WHERE temperature < 35
)
SELECT essai, temperature FROM paliers ORDER BY essai;


WITH RECURSIVE arbre AS (
  SELECT category_id, parent_category_id, 0 AS profondeur, category_name::text AS chemin
  FROM metier.categories WHERE parent_category_id IS NULL
  UNION ALL
  SELECT c.category_id, c.parent_category_id, a.profondeur + 1, a.chemin || ' > ' || c.category_name
  FROM metier.categories c JOIN arbre a ON c.parent_category_id = a.category_id
  WHERE a.profondeur < 10
) CYCLE category_id SET est_cycle USING parcours
SELECT * FROM arbre;

