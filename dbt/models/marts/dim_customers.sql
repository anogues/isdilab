{{ config(materialized='table') }}

-- Lee desde SILVER.stg_customers
-- Escribe en GOLD.dim_customers (como tabla)
with customers as (
    select customer_id, first_name, last_name, join_date from {{ ref('stg_customers') }}
)
select customer_id, first_name, last_name, join_date, year(join_date) as join_year from customers
