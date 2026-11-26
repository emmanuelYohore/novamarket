---
pretty_name: NovaMarket S5 — trajets synthétiques agrégés par zone
language:
  - fr
tags:
  - education
  - synthetic
size_categories:
  - n<1K
---

# NovaMarket S5 — trajets synthétiques agrégés par zone (version 2)

Jeu pédagogique produit pendant la séance 5 du projet NovaMarket. Il est **synthétique et agrégé** :
il provient du fichier fictif `volumetrie/secours/trajets_fictifs.jsonl` fourni avec le kit, joint à
la table officielle des zones de taxi de New York (TLC, `volumetrie/secours/zones.csv`).
Aucune ligne du miroir `DinoPonjevic/NYC_TaxiData` (révision `5941adbf8c0b9930e47002dc3103de3f9291360d`,
licence non renseignée) n'est republiée ici.

Conditions d'usage : exercice de formation uniquement. Les valeurs ne décrivent pas le trafic réel.
La table des zones provient de la TLC, publiée sur NYC Open Data.

## Colonnes et unités

Grain : **1 ligne = 1 zone de départ** ayant au moins un trajet apparié. 3 lignes.
Pas de plage temporelle (aucun horodatage n'est projeté). Aucune valeur manquante.

| Colonne | Type | Signification et unité |
| --- | --- | --- |
| `zone_id` | entier | code LocationID de la table de zones TLC (1 à 265) |
| `arrondissement` | texte | Borough de la table de zones |
| `zone` | texte | nom de la zone de départ |
| `zone_service` | texte | service_zone TLC (Yellow Zone, Boro Zone, EWR…) |
| `nb_trajets` | entier | nombre de trajets de la zone |
| `distance_totale_miles` | décimal | somme des distances, en miles |
| `distance_moy_miles` | décimal | distance moyenne, en miles |
| `duree_moy_min` | décimal | durée moyenne, en minutes |
| `vitesse_moy_mph` | décimal | moyenne des vitesses par trajet, en miles par heure |

## Extraction et qualité

| Étape | Résultat |
| --- | --- |
| Parcours (M2, mode secours_local) | 6 lignes parcourues, 6 retenues, 0 rejetées |
| Contrôle qualité (M3) | 6 avant, 5 après ; rejets : {"Q3_distance": 1} |
| Jointure aux zones (M4) | 5 avant, 4 après ; zones inconnues : [999] |
| Agrégat publié | 3 zones, 4 trajets au total |

Règles de qualité : distance entre 0 (exclu) et 100 miles, durée entre 60 s et 6 h, vitesse moyenne
au plus 80 mph ; un code de zone absent de la table TLC est écarté à la jointure.

Limites : 6 trajets fictifs seulement, sans représentativité statistique. Le streaming distant de la
source réelle n'a pas pu être exécuté depuis l'environnement de préparation (accès réseau refusé).

Reproduction, depuis `novamarket/` :

```bash
python volumetrie/streaming/extraire_trajets.py --secours --run <essai>
python volumetrie/streaming/controler_extraction.py --run <essai>
python volumetrie/spark/pipeline_trajets.py --run <essai> --sortie volumetrie/sorties/<essai>-essai1
python volumetrie/hub/preparer_publication.py --version 2 --parquet volumetrie/sorties/<essai>-essai1
```

## Révisions

- Révision initiale (v1) : agrégat par zone de départ, 6 colonnes (nombre de trajets, distance moyenne, durée moyenne).
- Deuxième révision (v2) : ajout de `zone_service`, `distance_totale_miles` et `vitesse_moy_mph`. Justification : la somme des distances permet de recalculer une moyenne pondérée entre zones, et la vitesse moyenne rend visibles les trajets incohérents. Les lignes et les valeurs déjà publiées sont inchangées.
