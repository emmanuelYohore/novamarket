"""S5 · M5 — Prépare le dossier publication/ (Dataset Card + agrégat autorisé) pour la version 1 ou 2.

Usage (depuis novamarket/) :
    python volumetrie/hub/preparer_publication.py --version 1 --parquet volumetrie/sorties/g01-secours01-essai1
    python volumetrie/hub/preparer_publication.py --version 2 --parquet volumetrie/sorties/g01-secours01-essai1

Ce qui est publié : UNIQUEMENT un agrégat par zone calculé par le pipeline Spark (M4) à partir
du jeu synthétique du kit (volumetrie/secours/trajets_fictifs.jsonl) et de la table de zones TLC.
Aucune ligne du miroir NYC_TaxiData (licence « unknown ») n'est republiée.

  version 1 : trajets_par_zone.parquet = zone_id, arrondissement, zone, nb_trajets,
              distance_moy_miles, duree_moy_min ; Dataset Card initiale
  version 2 : ajoute vitesse_moy_mph, distance_totale_miles, zone_service ; la card documente
              le changement dans « Révisions »

Le dossier publication/ ne contient que README.md et trajets_par_zone.parquet (les autres fichiers
éventuels sont signalés et le script s'arrête). Une copie de chaque version et son empreinte
SHA-256 sont gardées dans volumetrie/preuves/publication_v<N>/.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

import pyarrow.parquet as pq

RACINE = Path(__file__).resolve().parents[2]
VOLUMETRIE = RACINE / "volumetrie"
FICHIER = "trajets_par_zone.parquet"
COLONNES = {
    1: ["zone_id", "arrondissement", "zone", "nb_trajets", "distance_moy_miles", "duree_moy_min"],
    2: ["zone_id", "arrondissement", "zone", "zone_service", "nb_trajets", "distance_totale_miles",
        "distance_moy_miles", "duree_moy_min", "vitesse_moy_mph"],
}
UNITES = {
    "zone_id": ("entier", "code LocationID de la table de zones TLC (1 à 265)"),
    "arrondissement": ("texte", "Borough de la table de zones"),
    "zone": ("texte", "nom de la zone de départ"),
    "zone_service": ("texte", "service_zone TLC (Yellow Zone, Boro Zone, EWR…)"),
    "nb_trajets": ("entier", "nombre de trajets de la zone"),
    "distance_totale_miles": ("décimal", "somme des distances, en miles"),
    "distance_moy_miles": ("décimal", "distance moyenne, en miles"),
    "duree_moy_min": ("décimal", "durée moyenne, en minutes"),
    "vitesse_moy_mph": ("décimal", "moyenne des vitesses par trajet, en miles par heure"),
}


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def card(version: int, table, bilans: dict) -> str:
    m2, m3, sp = bilans["m2"], bilans["m3"], bilans["spark"]
    lignes = "\n".join(f"| `{c}` | {UNITES[c][0]} | {UNITES[c][1]} |" for c in COLONNES[version])
    revisions = ("- Révision initiale (v1) : agrégat par zone de départ, 6 colonnes "
                 "(nombre de trajets, distance moyenne, durée moyenne).")
    if version == 2:
        revisions += ("\n- Deuxième révision (v2) : ajout de `zone_service`, `distance_totale_miles` et "
                      "`vitesse_moy_mph`. Justification : la somme des distances permet de recalculer "
                      "une moyenne pondérée entre zones, et la vitesse moyenne rend visibles les trajets "
                      "incohérents. Les lignes et les valeurs déjà publiées sont inchangées.")
    else:
        revisions += "\n- Deuxième révision : à venir."
    return f"""---
pretty_name: NovaMarket S5 — trajets synthétiques agrégés par zone
language:
  - fr
tags:
  - education
  - synthetic
size_categories:
  - n<1K
---

# NovaMarket S5 — trajets synthétiques agrégés par zone (version {version})

Jeu pédagogique produit pendant la séance 5 du projet NovaMarket. Il est **synthétique et agrégé** :
il provient du fichier fictif `volumetrie/secours/trajets_fictifs.jsonl` fourni avec le kit, joint à
la table officielle des zones de taxi de New York (TLC, `volumetrie/secours/zones.csv`).
Aucune ligne du miroir `DinoPonjevic/NYC_TaxiData` (révision `5941adbf8c0b9930e47002dc3103de3f9291360d`,
licence non renseignée) n'est republiée ici.

Conditions d'usage : exercice de formation uniquement. Les valeurs ne décrivent pas le trafic réel.
La table des zones provient de la TLC, publiée sur NYC Open Data.

## Colonnes et unités

Grain : **1 ligne = 1 zone de départ** ayant au moins un trajet apparié. {table.num_rows} lignes.
Pas de plage temporelle (aucun horodatage n'est projeté). Aucune valeur manquante.

| Colonne | Type | Signification et unité |
| --- | --- | --- |
{lignes}

## Extraction et qualité

| Étape | Résultat |
| --- | --- |
| Parcours (M2, mode {m2['mode']}) | {m2['parcourues']} lignes parcourues, {m2['retenues']} retenues, {m2['rejetees']} rejetées |
| Contrôle qualité (M3) | {m3['avant']} avant, {m3['apres']} après ; rejets : {json.dumps(m3['rejets_par_regle'], ensure_ascii=False)} |
| Jointure aux zones (M4) | {sp['avant_jointure']} avant, {sp['apres_jointure']} après ; zones inconnues : {sp['zones_inconnues']} |
| Agrégat publié | {sp['parquet']['lignes']} zones, {sp['parquet']['somme_nb_trajets']} trajets au total |

Règles de qualité : distance entre 0 (exclu) et 100 miles, durée entre 60 s et 6 h, vitesse moyenne
au plus 80 mph ; un code de zone absent de la table TLC est écarté à la jointure.

Limites : 6 trajets fictifs seulement, sans représentativité statistique. Le streaming distant de la
source réelle n'a pas pu être exécuté depuis l'environnement de préparation (accès réseau refusé).

Reproduction, depuis `novamarket/` :

```bash
python volumetrie/streaming/extraire_trajets.py --secours --run <essai>
python volumetrie/streaming/controler_extraction.py --run <essai>
python volumetrie/spark/pipeline_trajets.py --run <essai> --sortie volumetrie/sorties/<essai>-essai1
python volumetrie/hub/preparer_publication.py --version {version} --parquet volumetrie/sorties/<essai>-essai1
```

## Révisions

{revisions}
"""


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Prépare publication/ pour le Hub (S5 · M5)")
    p.add_argument("--version", type=int, choices=(1, 2), required=True)
    p.add_argument("--parquet", type=Path, required=True, help="dossier Parquet écrit par pipeline_trajets.py")
    p.add_argument("--dossier", type=Path, default=RACINE / "publication")
    a = p.parse_args(argv)

    if not a.parquet.is_dir():
        print(f"dossier Parquet absent : {a.parquet}", file=sys.stderr)
        return 1
    spark_bilans = [b for b in (json.loads(f.read_text(encoding="utf-8"))
                                for f in (VOLUMETRIE / "preuves").glob("spark_*.bilan.json"))
                    if Path(b["sortie"]).resolve() == a.parquet.resolve()
                    or Path(RACINE / b["sortie"]).resolve() == a.parquet.resolve()]
    if not spark_bilans:
        print("bilan Spark introuvable pour ce dossier (volumetrie/preuves/spark_<run>.bilan.json)", file=sys.stderr)
        return 1
    sp = spark_bilans[0]
    bilans = {"spark": sp,
              "m2": json.loads((VOLUMETRIE / "data" / f"extraction_{sp['run']}.bilan.json").read_text(encoding="utf-8")),
              "m3": json.loads((VOLUMETRIE / "data" / f"entree_spark_{sp['run']}.bilan.json").read_text(encoding="utf-8"))}

    table = pq.read_table(a.parquet).select(COLONNES[a.version]).sort_by("zone_id")
    a.dossier.mkdir(exist_ok=True)
    etrangers = [f.name for f in a.dossier.iterdir() if f.name not in (FICHIER, "README.md")]
    if etrangers:
        print(f"{a.dossier} contient d'autres fichiers ({etrangers}) : rien n'a été modifié.", file=sys.stderr)
        return 1
    pq.write_table(table, a.dossier / FICHIER)
    (a.dossier / "README.md").write_text(card(a.version, table, bilans), encoding="utf-8")

    copie = VOLUMETRIE / "preuves" / f"publication_v{a.version}"
    shutil.rmtree(copie, ignore_errors=True)
    shutil.copytree(a.dossier, copie)
    manifeste = {"version": a.version, "colonnes": COLONNES[a.version], "lignes": table.num_rows,
                 "fichiers": {f.name: sha256(f) for f in sorted(a.dossier.iterdir())}}
    (copie / "MANIFESTE.json").write_text(json.dumps(manifeste, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifeste, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
