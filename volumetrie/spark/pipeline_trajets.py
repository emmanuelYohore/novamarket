"""S5 · M4 — Pipeline PySpark : trajets x zones -> indicateurs par zone de départ, en Parquet.

Usage (depuis novamarket/, venv actif, JAVA_HOME / SPARK_LOCAL_IP / PYSPARK_PYTHON exportés) :
    python volumetrie/spark/pipeline_trajets.py --run g01-distant01 --sortie volumetrie/sorties/g01-distant01-essai1

Étapes : SparkSession locale -> lecture JSONL et zones.csv -> schémas -> typage -> filtre ->
colonnes calculées -> contrôle de la clé des zones -> non-appariements -> jointure (volumes avant /
après) -> agrégation -> partitions et explain() -> écriture Parquet (dossier neuf) -> relecture.

Grain de sortie : 1 ligne = 1 zone de départ (Start_Zone) ayant au moins un trajet apparié.
Pourquoi ce grain : la zone est la seule dimension du jeu (pas d'horodatage projeté) ; sommes et
moyennes par zone permettent de comparer les quartiers sans exposer de trajet individuel.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from pyspark.sql import SparkSession, functions as F, types as T

VOLUMETRIE = Path(__file__).resolve().parents[1]
ZONES = VOLUMETRIE / "secours" / "zones.csv"


def titre(texte: str) -> None:
    print(f"\n== {texte} ==", flush=True)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Pipeline PySpark trajets x zones (S5 · M4)")
    p.add_argument("--run", required=True, help="essai dont on lit volumetrie/data/entree_spark_<run>.jsonl")
    p.add_argument("--sortie", required=True, type=Path, help="dossier Parquet NEUF")
    a = p.parse_args(argv)
    entree = VOLUMETRIE / "data" / f"entree_spark_{a.run}.jsonl"
    if not entree.is_file():
        print(f"entrée absente : {entree} (lancer M2 puis M3)", file=sys.stderr)
        return 1
    if a.sortie.exists():
        print(f"{a.sortie} existe déjà : choisir un nouveau dossier de sortie.", file=sys.stderr)
        return 1

    spark = (SparkSession.builder.master("local[2]").appName(f"s5-trajets-{a.run}")
             .config("spark.sql.shuffle.partitions", "2")
             .config("spark.sql.session.timeZone", "UTC").getOrCreate())
    spark.sparkContext.setLogLevel("ERROR")
    bilan = {"run": a.run, "entree": str(entree.relative_to(VOLUMETRIE.parent)), "sortie": str(a.sortie)}
    try:
        # 1. Lecture brute et schémas inférés
        brut = spark.read.json(str(entree))
        zones_brut = spark.read.option("header", True).csv(str(ZONES))
        titre("Schéma inféré des trajets"); brut.printSchema()
        titre("Schéma inféré des zones (tout en texte)"); zones_brut.printSchema()

        # 2. Typage explicite et projection
        trajets = brut.select(
            F.col("rang").cast(T.LongType()).alias("rang"),
            F.col("Start_Zone").cast(T.IntegerType()).alias("zone_id"),
            F.col("Trip_Distance").cast(T.DoubleType()).alias("distance_miles"),
            F.col("Trip_Duration").cast(T.DoubleType()).alias("duree_s"),
            "source_revision")
        zones = zones_brut.select(
            F.col("LocationID").cast(T.IntegerType()).alias("zone_id"),
            F.col("Borough").alias("arrondissement"), F.col("Zone").alias("zone"),
            F.col("service_zone").alias("zone_service"))
        titre("Schéma typé des trajets"); trajets.printSchema()
        bilan["lignes_lues"] = trajets.count()

        # 3. Filtre défensif (déjà appliqué en M3 ; recontrôlé ici après typage)
        trajets = trajets.where(F.col("zone_id").isNotNull() & (F.col("distance_miles") > 0)
                                & (F.col("duree_s") > 0))
        bilan["apres_filtre"] = trajets.count()

        # 4. Colonnes calculées
        trajets = (trajets.withColumn("duree_min", F.col("duree_s") / 60)
                          .withColumn("vitesse_mph", F.col("distance_miles") / (F.col("duree_s") / 3600)))

        # 5. Contrôle de la clé de jointure côté zones : non nulle et unique
        cle = zones.agg(F.count("*").alias("lignes"), F.countDistinct("zone_id").alias("distinctes"),
                        F.sum(F.col("zone_id").isNull().cast("int")).alias("nulles")).first()
        bilan["zones"] = {"lignes": cle["lignes"], "cles_distinctes": cle["distinctes"], "cles_nulles": cle["nulles"]}
        titre("Clé zones"); print(bilan["zones"])
        if cle["lignes"] != cle["distinctes"] or cle["nulles"]:
            raise RuntimeError("clé zone_id non unique ou nulle : la jointure multiplierait les lignes")

        # 6. Non-appariements (trajets dont la zone n'existe pas dans la table)
        orphelins = trajets.join(zones, "zone_id", "left_anti")
        bilan["non_apparies"] = orphelins.count()
        bilan["zones_inconnues"] = sorted(r["zone_id"] for r in orphelins.select("zone_id").distinct().collect())
        titre("Trajets non appariés"); orphelins.show(truncate=False)

        # 7. Jointure : volumes avant / après (clé unique => aucune multiplication possible)
        joint = trajets.join(zones, "zone_id", "inner")
        bilan["avant_jointure"] = bilan["apres_filtre"]
        bilan["apres_jointure"] = joint.count()
        assert bilan["apres_jointure"] == bilan["avant_jointure"] - bilan["non_apparies"], "volumes incohérents"
        assert bilan["apres_jointure"] <= bilan["avant_jointure"], "la jointure a multiplié les lignes"

        # 8. Agrégation au grain zone de départ
        resultat = (joint.groupBy("zone_id", "arrondissement", "zone", "zone_service")
                    .agg(F.count("*").alias("nb_trajets"),
                         F.round(F.sum("distance_miles"), 2).alias("distance_totale_miles"),
                         F.round(F.avg("distance_miles"), 3).alias("distance_moy_miles"),
                         F.round(F.avg("duree_min"), 2).alias("duree_moy_min"),
                         F.round(F.avg("vitesse_mph"), 2).alias("vitesse_moy_mph"))
                    .orderBy("zone_id"))

        # 9. Partitionnement et plan d'exécution
        bilan["partitions"] = {"trajets_lus": brut.rdd.getNumPartitions(),
                               "resultat": resultat.rdd.getNumPartitions()}
        titre("Partitions"); print(bilan["partitions"])
        titre("Plan d'exécution (explain formatted)"); resultat.explain(mode="formatted")

        # 10. Écriture Parquet (refus si le dossier existe) puis relecture et vérification
        resultat.write.mode("errorifexists").parquet(str(a.sortie))
        relu = spark.read.parquet(str(a.sortie))
        titre("Schéma du Parquet relu"); relu.printSchema()
        titre("Parquet relu"); relu.orderBy("zone_id").show(truncate=False)
        tot = relu.agg(F.sum("nb_trajets").alias("t")).first()["t"]
        bilan["parquet"] = {"lignes": relu.count(), "somme_nb_trajets": tot}
        assert tot == bilan["apres_jointure"], "le Parquet relu ne retrouve pas tous les trajets joints"
        bilan["controle"] = "ok"
    finally:
        spark.stop()
    titre("Bilan"); print(json.dumps(bilan, ensure_ascii=False, indent=2))
    (VOLUMETRIE / "preuves").mkdir(exist_ok=True)
    (VOLUMETRIE / "preuves" / f"spark_{a.run}.bilan.json").write_text(
        json.dumps(bilan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
