"""Point de départ du groupe. Implémenter les contrôles et motifs de rejet ici."""


"""Contrôles des offres fournisseur et motifs de rejet (S3 · M4).

Une offre est acceptée si elle respecte le contrat :
  - champs requis présents : offer_id, supplier_id, product_id, price_cents,
    currency, available_units, observed_on ;
  - offer_id, supplier_id : texte non vide ;
  - product_id, price_cents, available_units : entiers (pas de booléen, pas de texte) ;
  - price_cents >= 0, available_units >= 0 ; currency = "EUR" ;
  - observed_on : date ISO AAAA-MM-JJ valide ;
  - product_id présent dans le catalogue S2 (s2/donnees/products.csv) ;
  - offer_id non déjà accepté dans le lot (doublon : la 1re occurrence, par ordre
    de page puis de position, est conservée).
Un seul motif est attribué : le premier contrôle en échec, dans l'ordre ci-dessus.
"""
from __future__ import annotations

import csv
import re
from datetime import date
from pathlib import Path

CHAMPS = ("offer_id", "supplier_id", "product_id", "price_cents",
          "currency", "available_units", "observed_on")
DATE_ISO = re.compile(r"\d{4}-\d{2}-\d{2}")


def charger_catalogue(chemin: Path) -> set[int]:
    """Codes produit du catalogue S2 (doublons de fiches sans effet sur l'ensemble)."""
    with chemin.open(encoding="utf-8", newline="") as f:
        return {int(ligne["product_id"]) for ligne in csv.DictReader(f)}


def _entier(valeur) -> bool:
    return isinstance(valeur, int) and not isinstance(valeur, bool)


def motif_rejet(offre, produits: set[int]) -> str | None:
    """Retourne None si l'offre est conforme, sinon le motif (hors doublon)."""
    if not isinstance(offre, dict):
        return "offre_non_objet"
    manquants = [c for c in CHAMPS if c not in offre or offre[c] is None]
    if manquants:
        return "champ_manquant:" + ",".join(manquants)
    for champ in ("offer_id", "supplier_id"):
        if not isinstance(offre[champ], str) or not offre[champ].strip():
            return f"type_invalide:{champ}"
    for champ in ("product_id", "price_cents", "available_units"):
        if not _entier(offre[champ]):
            return f"type_invalide:{champ}"
    if offre["price_cents"] < 0:
        return "prix_negatif"
    if offre["available_units"] < 0:
        return "unites_negatives"
    if offre["currency"] != "EUR":
        return "devise_invalide"
    if not isinstance(offre["observed_on"], str) or not DATE_ISO.fullmatch(offre["observed_on"]):
        return "date_invalide"
    try:
        date.fromisoformat(offre["observed_on"])
    except ValueError:
        return "date_invalide"
    if offre["product_id"] not in produits:
        return "produit_inconnu"
    return None


def valider_lot(pages: dict[int, list], produits: set[int]):
    """Sépare les offres d'un lot complet en (valides, rejets), dans l'ordre page/position."""
    valides, rejets, vus = [], [], {}
    for page in sorted(pages):
        for position, offre in enumerate(pages[page], start=1):
            motif = motif_rejet(offre, produits)
            if motif is None and offre["offer_id"] in vus:
                motif = f"doublon_offer_id:premiere_occurrence_page_{vus[offre['offer_id']][0]}_position_{vus[offre['offer_id']][1]}"
            if motif is None:
                vus[offre["offer_id"]] = (page, position)
                valides.append({c: offre[c] for c in CHAMPS})
            else:
                rejets.append({"page": page, "position": position, "motif": motif, "brut": offre})
    return valides, rejets
