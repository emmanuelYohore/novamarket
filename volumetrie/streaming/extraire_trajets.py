"""S5 · M2 — Parcours borné en streaming de la partition yellow 2024-01 et export JSONL.

Usage (depuis novamarket/, venv actif) :
    HF_HUB_DISABLE_XET=1 python volumetrie/streaming/extraire_trajets.py --max 50000 --run g01-distant01
    python volumetrie/streaming/extraire_trajets.py --secours --run g01-secours01   # hors ligne

Principe :
  - la source distante est ouverte par volumetrie/hf_datasets/acces.py (révision épinglée,
    3 colonnes projetées, lots de 128 lignes, pas de préchargement) : rien n'est chargé en RAM
    d'un bloc, les lignes sont lues une à une ;
  - le parcours s'arrête à --max lignes PARCOURUES (comptées avant tout filtrage) ;
  - règle de validité M2 (forme) : les 3 champs sont présents et non nuls, Start_Zone est un
    entier, Trip_Distance et Trip_Duration sont des nombres finis. La cohérence des valeurs
    (distances, durées, vitesses) est contrôlée ensuite en M3 (controler_extraction.py) ;
  - l'itérateur est fermé dans un bloc finally, même en cas d'erreur ou d'interruption ;
  - sortie : volumetrie/data/extraction_<run>.jsonl (écrite d'abord en .tmp, renommée à la fin)
    et volumetrie/data/extraction_<run>.bilan.json (parcourues / retenues / rejetées).
Codes retour : 0 extraction complète, 2 parcours interrompu par une erreur, 1 erreur d'usage.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

VOLUMETRIE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(VOLUMETRIE / "hf_datasets"))
import acces  # noqa: E402  (fournit SOURCE et ouvrir())

COLONNES = acces.SOURCE["columns"]          # Start_Zone, Trip_Distance, Trip_Duration
SECOURS = VOLUMETRIE / "secours" / "trajets_fictifs.jsonl"
DONNEES = VOLUMETRIE / "data"


def _nombre(valeur) -> bool:
    return isinstance(valeur, (int, float)) and not isinstance(valeur, bool) and math.isfinite(valeur)


def motif_rejet(ligne) -> str | None:
    """Règle de validité M2 : forme de l'enregistrement seulement."""
    if not isinstance(ligne, dict):
        return "enregistrement_non_objet"
    manquants = [c for c in COLONNES if ligne.get(c) is None]
    if manquants:
        return "champ_manquant:" + ",".join(manquants)
    if not (isinstance(ligne["Start_Zone"], int) and not isinstance(ligne["Start_Zone"], bool)):
        return "type_invalide:Start_Zone"
    for colonne in ("Trip_Distance", "Trip_Duration"):
        if not _nombre(ligne[colonne]):
            return f"type_invalide:{colonne}"
    return None


def ouvrir_flux(secours: bool):
    if secours:
        from datasets import load_dataset
        return load_dataset("json", data_files={"train": str(SECOURS)}, split="train", streaming=True)
    return acces.ouvrir()


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Extraction bornée en streaming (S5 · M2)")
    p.add_argument("--run", required=True, help="identifiant d'essai (lettres, chiffres, - et _)")
    p.add_argument("--max", type=int, default=50_000, help="nombre maximal de lignes parcourues")
    p.add_argument("--secours", action="store_true",
                   help="lire volumetrie/secours/trajets_fictifs.jsonl (n'atteste pas le streaming distant)")
    a = p.parse_args(argv)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", a.run) or a.max < 1:
        p.error("--run invalide ou --max < 1")

    DONNEES.mkdir(parents=True, exist_ok=True)
    sortie = DONNEES / f"extraction_{a.run}.jsonl"
    bilan_chemin = DONNEES / f"extraction_{a.run}.bilan.json"
    if sortie.exists() or bilan_chemin.exists():
        print(f"L'essai {a.run} existe déjà : choisir un autre --run.", file=sys.stderr)
        return 1

    bilan = {
        "run": a.run,
        "mode": "secours_local" if a.secours else "streaming_distant",
        "source": {"repo": acces.SOURCE["repo"], "revision": acces.SOURCE["revision"],
                   "partition": acces.SOURCE["shard"]} if not a.secours
                  else {"fichier": "volumetrie/secours/trajets_fictifs.jsonl", "nature": "synthétique"},
        "colonnes": COLONNES,
        "borne_max": a.max,
        "regle_validite": "3 champs présents et non nuls ; Start_Zone entier ; distance et durée numériques finies",
        "debut": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "parcourues": 0, "retenues": 0, "rejetees": 0, "motifs_rejet": Counter(),
        "arret": None, "statut": "en_cours",
    }
    tmp = sortie.with_suffix(".jsonl.tmp")
    t0 = time.perf_counter()
    flux = None
    code = 0
    try:
        flux = iter(ouvrir_flux(a.secours))
        with tmp.open("w", encoding="utf-8") as f:
            for rang, ligne in enumerate(flux, start=1):
                bilan["parcourues"] += 1                     # compté AVANT tout filtrage
                motif = motif_rejet(ligne)
                if motif:
                    bilan["rejetees"] += 1
                    bilan["motifs_rejet"][motif] += 1
                else:
                    bilan["retenues"] += 1
                    f.write(json.dumps({"rang": rang, **{c: ligne[c] for c in COLONNES}}) + "\n")
                if bilan["parcourues"] >= a.max:
                    bilan["arret"] = "borne_atteinte"
                    break
            else:
                bilan["arret"] = "fin_du_flux"
        tmp.replace(sortie)
        bilan["statut"] = "succes"
    except (Exception, KeyboardInterrupt) as exc:      # incident documenté, pas de sortie partielle
        bilan["statut"] = "erreur"
        bilan["arret"] = f"{type(exc).__name__}: {str(exc)[:300]}"
        tmp.unlink(missing_ok=True)
        code = 2
    finally:
        if flux is not None and hasattr(flux, "close"):
            flux.close()                                 # libère connexions et fichiers ouverts
        bilan["fin"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        bilan["duree_s"] = round(time.perf_counter() - t0, 3)
        bilan["motifs_rejet"] = dict(bilan["motifs_rejet"])
        bilan["controle"] = bilan["parcourues"] == bilan["retenues"] + bilan["rejetees"]
        if code == 0:
            bilan["fichier"] = str(sortie.relative_to(VOLUMETRIE.parent))
        bilan_chemin.write_text(json.dumps(bilan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: bilan[k] for k in ("mode", "statut", "arret", "parcourues", "retenues",
                                             "rejetees", "motifs_rejet", "duree_s")}, ensure_ascii=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
