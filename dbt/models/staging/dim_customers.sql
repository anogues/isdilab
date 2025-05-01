-- Lee desde RAW_STAGING.stg_customers
-- Escribe en ANALYTICS.dim_customers (como vista)
with customers as (
    select customer_id, first_name, last_name, join_date from {{ ref('stg_customers') }}
)
select customer_id, first_name, last_name, join_date, year(join_date) as join_year from customers