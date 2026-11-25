{{ config(materialized='view') }}

with source as (
    select * from {{ source('fournisseur', 'offres') }}
),

normalized as (
    select
        btrim(offer_id) as offer_id,
        btrim(supplier_id) as supplier_id,
        product_id,
        price_cents,
        currency,
        available_units,
        observed_on,
        charge_le
    from source
)

select * from normalized
