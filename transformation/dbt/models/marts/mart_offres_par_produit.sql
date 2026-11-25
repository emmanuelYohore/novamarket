{{ config(materialized='table') }}

with observations as (
    select * from {{ ref('int_offres_par_observation') }}
),

mart as (
    select
        observed_on,
        product_id,
        count(*) as nombre_offres,
        count(distinct supplier_id) as nombre_fournisseurs,
        sum(available_units) as unite_disponibles,
        round(avg(price_cents), 2) as prix_moyen_centimes
    from observations
    group by observed_on, product_id
)

select * from mart
