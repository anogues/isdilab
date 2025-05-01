-- Lee desde source (LAB_DB.bronze.S3_CUSTOMER_STAGE)
-- Escribe en RAW_STAGING.stg_customers
with source as (
    select $1::number as customer_id, $2::varchar as first_name, $3::varchar as last_name, try_to_date($4::varchar, 'YYYY-MM-DD') as join_date
    from {{ source('raw_customer_data', 'customers_external') }}
)
select customer_id, first_name, last_name, join_date from source where customer_id is not null