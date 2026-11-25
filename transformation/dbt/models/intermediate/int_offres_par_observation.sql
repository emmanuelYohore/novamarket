{{ config(materialized='ephemeral') }}

with offres as (
    select * from {{ ref('stg_offres') }}
),

dedoublonnees as (
    select distinct
        offer_id,
        observed_on,
        supplier_id,
        product_id,
        price_cents,
        currency,
        available_units
    from offres
)

select * from dedoublonnees
