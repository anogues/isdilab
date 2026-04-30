{{ config(materialized='table') }}

with customers as (
    select customer_id, first_name, last_name, join_date from {{ ref('stg_customers') }}
)
select customer_id, first_name, last_name, join_date, year(join_date) as join_year from customers
