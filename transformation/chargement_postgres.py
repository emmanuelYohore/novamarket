"""Charge les offres validées S3 dans PostgreSQL de façon transactionnelle."""

from __future__ import annotations

import argparse
import json
import os
from datetime import date
from pathlib import Path
from typing import Any

import psycopg


DEFAULT_INPUT = Path("ingestion/data/valid/offres.jsonl")
FALLBACK_INPUT = Path("transformation/secours/offres.jsonl")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Charge un JSONL d'offres fournisseurs")
    parser.add_argument("input", nargs="?", type=Path)
    return parser.parse_args()


def require_string(row: dict[str, Any], key: str) -> str:
    value = row.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} doit être une chaîne non vide")
    return value.strip()


def require_int(row: dict[str, Any], key: str, minimum: int = 0) -> int:
    value = row.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(f"{key} doit être un entier >= {minimum}")
    return value


def normalize(row: dict[str, Any]) -> tuple[str, str, int, int, str, int, date]:
    offer_id = require_string(row, "offer_id")
    supplier_id = require_string(row, "supplier_id")
    if supplier_id not in {"F01", "F02", "F03"}:
        raise ValueError(f"fournisseur inconnu: {supplier_id}")
    product_id = require_int(row, "product_id", 1)
    price_cents = require_int(row, "price_cents")
    currency = require_string(row, "currency")
    if currency != "EUR":
        raise ValueError("currency doit être EUR")
    available_units = require_int(row, "available_units")
    observed_on = date.fromisoformat(require_string(row, "observed_on"))
    return (
        offer_id,
        supplier_id,
        product_id,
        price_cents,
        currency,
        available_units,
        observed_on,
    )


def main() -> int:
    args = parse_args()
    input_path = args.input
    if input_path is None:
        input_path = DEFAULT_INPUT if DEFAULT_INPUT.exists() else FALLBACK_INPUT
    if not input_path.exists():
        raise SystemExit(f"Entrée introuvable : {input_path}")

    dsn = os.environ.get("NOVAMARKET_DSN")
    if not dsn:
        raise SystemExit(
            "NOVAMARKET_DSN non défini. "
            "Exemple : export NOVAMARKET_DSN='host=127.0.0.1 port=15432 "
            "dbname=novamarket user=atelier'"
        )

    examined = inserted = unchanged = rejected = 0
    with psycopg.connect(dsn, connect_timeout=5) as db:
        with db.transaction():
            db.execute("CREATE SCHEMA IF NOT EXISTS fournisseur")
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS fournisseur.offres (
                    offer_id text NOT NULL,
                    supplier_id text NOT NULL,
                    product_id integer NOT NULL,
                    price_cents integer NOT NULL CHECK (price_cents >= 0),
                    currency text NOT NULL CHECK (currency = 'EUR'),
                    available_units integer NOT NULL CHECK (available_units >= 0),
                    observed_on date NOT NULL,
                    charge_le timestamptz NOT NULL DEFAULT now(),
                    PRIMARY KEY (offer_id, observed_on)
                )
                """
            )
            db.execute(
                """
                CREATE TABLE IF NOT EXISTS fournisseur.rejets (
                    ligne_no bigint NOT NULL,
                    motif text NOT NULL,
                    contenu_brut jsonb NOT NULL,
                    charge_le timestamptz NOT NULL DEFAULT now(),
                    PRIMARY KEY (ligne_no, charge_le)
                )
                """
            )

            has_catalog = db.execute(
                """
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.tables
                    WHERE table_schema = 'metier' AND table_name = 'products'
                )
                """
            ).fetchone()[0]

            with input_path.open("r", encoding="utf-8") as source:
                for line_no, line in enumerate(source, start=1):
                    if not line.strip():
                        continue
                    examined += 1
                    try:
                        row = json.loads(line)
                        if not isinstance(row, dict):
                            raise ValueError("l'objet JSON doit être un dictionnaire")
                        offer = normalize(row)
                        if has_catalog:
                            exists = db.execute(
                                "SELECT EXISTS (SELECT 1 FROM metier.products WHERE product_id = %s)",
                                (offer[2],),
                            ).fetchone()[0]
                            if not exists:
                                raise ValueError(f"référence produit inconnue: {offer[2]}")

                        result = db.execute(
                            """
                            INSERT INTO fournisseur.offres
                                (offer_id, supplier_id, product_id, price_cents,
                                 currency, available_units, observed_on)
                            VALUES (%s, %s, %s, %s, %s, %s, %s)
                            ON CONFLICT (offer_id, observed_on) DO UPDATE
                            SET supplier_id = EXCLUDED.supplier_id,
                                product_id = EXCLUDED.product_id,
                                price_cents = EXCLUDED.price_cents,
                                currency = EXCLUDED.currency,
                                available_units = EXCLUDED.available_units
                            WHERE fournisseur.offres.supplier_id IS DISTINCT FROM EXCLUDED.supplier_id
                               OR fournisseur.offres.product_id IS DISTINCT FROM EXCLUDED.product_id
                               OR fournisseur.offres.price_cents IS DISTINCT FROM EXCLUDED.price_cents
                               OR fournisseur.offres.currency IS DISTINCT FROM EXCLUDED.currency
                               OR fournisseur.offres.available_units IS DISTINCT FROM EXCLUDED.available_units
                            """,
                            offer,
                        )
                        if result.rowcount:
                            inserted += 1
                        else:
                            unchanged += 1
                    except (json.JSONDecodeError, ValueError, TypeError) as error:
                        rejected += 1
                        db.execute(
                            "INSERT INTO fournisseur.rejets (ligne_no, motif, contenu_brut) "
                            "VALUES (%s, %s, to_jsonb(%s::text))",
                            (line_no, str(error), line.strip()),
                        )

    print(
        json.dumps(
            {
                "input": str(input_path),
                "examined": examined,
                "inserted_or_updated": inserted,
                "unchanged": unchanged,
                "rejected": rejected,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
