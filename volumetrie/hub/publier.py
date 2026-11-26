"""S5 · M5 — Publie deux révisions de publication/ sur un dépôt dataset PRIVÉ et vérifie leur récupération.

Prérequis : `hf auth login` déjà fait (le token est saisi dans l'invite de la CLI, jamais ici).
Usage (depuis novamarket/, venv actif) :
    python volumetrie/hub/publier.py --repo VOTRE_COMPTE/novamarket-s5-exercice \
        --parquet volumetrie/sorties/g01-secours01-essai1

Déroulé : vérifie l'identité (whoami) -> crée le dépôt privé s'il n'existe pas -> prépare la
version 1 et l'envoie -> prépare la version 2 et l'envoie -> télécharge README.md et le Parquet à
chacune des deux révisions (SHA) et compare leurs empreintes avec les copies locales.
Résultat : volumetrie/preuves/hub_revisions.json (dépôt, deux SHA, vérifications). Aucun token
n'est lu, affiché ni écrit par ce script.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from huggingface_hub import HfApi, hf_hub_download
from huggingface_hub.errors import HfHubHTTPError

RACINE = Path(__file__).resolve().parents[2]
PREUVES = RACINE / "volumetrie" / "preuves"
FICHIERS = ("README.md", "trajets_par_zone.parquet")


def sha256(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def preparer(version: int, parquet: Path) -> None:
    subprocess.run([sys.executable, str(RACINE / "volumetrie/hub/preparer_publication.py"),
                    "--version", str(version), "--parquet", str(parquet)], check=True)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description="Publication de deux révisions sur le Hub (S5 · M5)")
    p.add_argument("--repo", required=True, help="compte/nom-du-depot")
    p.add_argument("--parquet", required=True, type=Path)
    a = p.parse_args(argv)
    api = HfApi()
    try:
        compte = api.whoami()["name"]
    except Exception as exc:                       # 401 : pas connecté
        print(f"Authentification absente ou refusée ({type(exc).__name__}) : lancer `hf auth login`.", file=sys.stderr)
        return 1
    if a.repo.split("/")[0] != compte:
        print(f"Le dépôt {a.repo} n'est pas dans votre espace ({compte}) : risque de 403.", file=sys.stderr)
        return 1
    try:
        api.create_repo(a.repo, repo_type="dataset", private=True, exist_ok=True)
        shas = {}
        for version, message in ((1, "v1 : premier jeu vérifié"),
                                 (2, "v2 : ajout de zone_service, distance_totale_miles et vitesse_moy_mph")):
            preparer(version, a.parquet)
            info = api.upload_folder(repo_id=a.repo, repo_type="dataset",
                                     folder_path=RACINE / "publication", commit_message=message)
            shas[version] = info.oid
            print(f"version {version} publiée : {info.oid}")
        verifs = {}
        with tempfile.TemporaryDirectory() as tmp:
            for version, sha in shas.items():
                for nom in FICHIERS:
                    distant = hf_hub_download(a.repo, nom, repo_type="dataset", revision=sha,
                                              local_dir=Path(tmp) / f"v{version}")
                    local = PREUVES / f"publication_v{version}" / nom
                    verifs[f"v{version}/{nom}"] = sha256(distant) == sha256(local)
    except HfHubHTTPError as exc:                  # 403 : permissions ou espace de noms
        print(f"Refus du Hub : {exc}", file=sys.stderr)
        return 2
    resultat = {"repo": a.repo, "prive": True, "sha_v1": shas[1], "sha_v2": shas[2],
                "verifications_identiques_aux_copies_locales": verifs, "tout_ok": all(verifs.values())}
    (PREUVES / "hub_revisions.json").write_text(json.dumps(resultat, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8")
    print(json.dumps(resultat, ensure_ascii=False, indent=2))
    return 0 if resultat["tout_ok"] else 2


if __name__ == "__main__":
    sys.exit(main())
