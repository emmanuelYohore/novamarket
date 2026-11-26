"""S5 · M3 — Contrôle qualité de l'extraction et préparation de l'entrée Spark.

Usage (depuis novamarket/) :
    python volumetrie/streaming/controler_extraction.py --run g01-distant01

Lit volumetrie/data/extraction_<run>.jsonl ligne à ligne (pas de chargement intégral) et
applique les règles de qualité ci-dessous, dans cet ordre (un seul motif par ligne) :
  Q1 type        : Start_Zone entier ; Trip_Distance, Trip_Duration nombres finis
  Q2 manquant    : aucun des 3 champs n'est nul
  Q3 distance    : 0 < Trip_Distance <= 100 miles  (0 = course annulée, > 100 = hors ville)
  Q4 durée       : 60 <= Trip_Duration <= 21 600 s (moins d'une minute = erreur de saisie,
                   plus de 6 h = compteur resté ouvert)
  Q5 vitesse     : vitesse moyenne <= 80 mph (au-delà, distance ou durée fausse)
Le code de zone n'est PAS filtré ici : les zones inconnues sont détectées par la jointure Spark (M4).

Sorties :
  volumetrie/data/entree_spark_<run>.jsonl : lignes conservées + provenance
      (rang dans le flux, dépôt, révision, partition ou fichier de secours, extraction d'origine)
  volumetrie/data/entree_spark_<run>.bilan.json : avant / après, rejets par règle, manquants par colonne
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from pathlib import Path

VOLUMETRIE = Path(__file__).resolve().parents[1]
DONNEES = VOLUMETRIE / "data"
COLONNES = ("Start_Zone", "Trip_Distance", "Trip_Duration")
REGLES = {
    "Q3_distance": "0 < Trip_Distance <= 100 miles",
    "Q4_duree": "60 <= Trip_Duration <= 21600 s",
    "Q5_vitesse": "vitesse moyenne <= 80 mph",
}


def _nombre(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def motif(l: dict) -> str | None:
    if any(l.get(c) is None for c in COLONNES):
        return "Q2_manquant"
    if not (isinstance(l["Start_Zone"], int) and not isinstance(l["Start_Zone"], bool)) \
            or not _nombre(l["Trip_Distance"]) or not _nombre(l["Trip_Duration"]):
        return "Q1_type"
    d, s = l["Trip_Distance"], l["Trip_Duration"]
    if not 0 < d <= 100:
        return "Q3_distance"
    if not 60 <= s <= 21_600:
        return "Q4_duree"
    if d / (s / 3600) > 80:
        return "Q5_vitesse"
    return None


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Contrôle qualité de l'extraction (S5 · M3)")
    p.add_argument("--run", required=True)
    a = p.parse_args(argv)
    entree = DONNEES / f"extraction_{a.run}.jsonl"
    bilan_m2 = DONNEES / f"extraction_{a.run}.bilan.json"
    sortie = DONNEES / f"entree_spark_{a.run}.jsonl"
    bilan_chemin = DONNEES / f"entree_spark_{a.run}.bilan.json"
    if not entree.is_file() or not bilan_m2.is_file():
        print(f"extraction absente : {entree}", file=sys.stderr)
        return 1
    if sortie.exists():
        print(f"{sortie} existe déjà : ne pas écraser un résultat antérieur.", file=sys.stderr)
        return 1
    m2 = json.loads(bilan_m2.read_text(encoding="utf-8"))
    provenance = {"source_repo": m2["source"].get("repo", "secours_local"),
                  "source_revision": m2["source"].get("revision", "aucune (fichier synthétique)"),
                  "source_partition": m2["source"].get("partition", m2["source"].get("fichier")),
                  "extraction": entree.name}

    avant = apres = 0
    rejets, manquants = Counter(), Counter()
    tmp = sortie.with_suffix(".jsonl.tmp")
    with entree.open(encoding="utf-8") as src, tmp.open("w", encoding="utf-8") as dst:
        for texte in src:
            ligne = json.loads(texte)
            avant += 1
            for c in COLONNES:
                if ligne.get(c) is None:
                    manquants[c] += 1
            m = motif(ligne)
            if m:
                rejets[m] += 1
                continue
            apres += 1
            dst.write(json.dumps({**ligne, **provenance}, ensure_ascii=False) + "\n")
    tmp.replace(sortie)
    bilan = {"run": a.run, "mode": m2["mode"], "provenance": provenance,
             "m2": {k: m2[k] for k in ("parcourues", "retenues", "rejetees", "motifs_rejet")},
             "regles": REGLES, "avant": avant, "apres": apres, "rejetees": sum(rejets.values()),
             "rejets_par_regle": dict(rejets), "valeurs_manquantes": {c: manquants[c] for c in COLONNES},
             "controle": avant == apres + sum(rejets.values()),
             "fichier_spark": str(sortie.relative_to(VOLUMETRIE.parent))}
    bilan_chemin.write_text(json.dumps(bilan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: bilan[k] for k in ("avant", "apres", "rejetees", "rejets_par_regle", "controle")},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
