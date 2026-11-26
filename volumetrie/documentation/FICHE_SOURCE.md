# Fiche source S5 (M1)

| Élément | Valeur |
| --- | --- |
| Dépôt Hugging Face | `DinoPonjevic/NYC_TaxiData` (miroir de données publiques TLC) |
| Révision épinglée | `5941adbf8c0b9930e47002dc3103de3f9291360d` (`volumetrie/hf_datasets/source.json`) |
| Taille du dépôt | 371 fichiers Parquet, 39 350 805 895 octets (≈ 39,35 Go décimaux) |
| Partition utilisée | `2024/yellow/yellow_tripdata_2024-01.parquet` (taxis jaunes, janvier 2024) |
| Taille de la partition | donnée par `python volumetrie/hf_datasets/acces.py --infos` (champ `taille_partition`) — non relevée ici, accès réseau refusé |
| Colonnes projetées | `Start_Zone` (code zone TLC, entier) · `Trip_Distance` (miles) · `Trip_Duration` (secondes) |
| Licence du miroir | `unknown` (non renseignée) |
| Données d'origine | TLC, publiées sur NYC Open Data ; la TLC ne collecte pas d'information sur les passagers |
| Réutilisation | lecture et analyse autorisées ; **pas de republication des lignes brutes** du miroir ; publication limitée au jeu synthétique ou à un agrégat validé |

## Quatre volumes à ne pas confondre

1. Taille du dépôt : 39,35 Go (tous les fichiers, toutes les années).
2. Taille de la partition lue : un seul fichier mensuel.
3. Trafic réseau : seulement les colonnes et lots réellement lus (lots de 128 lignes, pas de préchargement).
4. Lignes traitées : bornées par `--max` (50 000 par défaut), comptées avant filtrage.

## Pourquoi ne pas tout charger en RAM

Le dépôt fait environ 39 Go, et une seule partition mensuelle représente déjà des millions de trajets.
Un chargement intégral dépasserait la mémoire d'un poste de TP (et la limite de 1 Go donnée au driver
Spark) pour n'utiliser que 3 colonnes. Le streaming lit ligne à ligne, projette les 3 colonnes et
s'arrête à la borne choisie : la mémoire reste constante quelle que soit la taille de la source.

## Pandas, Hugging Face Datasets ou Spark

| Outil | Quand le choisir | Limite |
| --- | --- | --- |
| Pandas | Données qui tiennent en mémoire (quelques centaines de Mo), exploration rapide | Tout est chargé en RAM sur une seule machine |
| Hugging Face Datasets (`streaming=True`) | Parcourir une source distante sans la télécharger, à révision fixée, et en extraire un sous-ensemble | Traitement ligne à ligne en Python ; pas fait pour les jointures ni les gros agrégats |
| PySpark | Jointures, agrégations et écritures Parquet sur des volumes qui dépassent la mémoire, réparties en partitions | Démarrage plus lourd (JVM), inutile pour de petits fichiers |

Dans ce projet : Datasets parcourt et extrait (M2), un script Python contrôle la qualité (M3), Spark
type, joint, agrège et écrit le Parquet (M4).
