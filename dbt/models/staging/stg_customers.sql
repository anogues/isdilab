with source as (
    -- Lee directamente desde LAB_DB.BRONZE.CUSTOMERS_RAW
    select
        customer_id::number as customer_id, -- Tipado explícito
        first_name::varchar as first_name,
        last_name::varchar as last_name,
        try_to_date(join_date::varchar, 'YYYY-MM-DD') as join_date -- Parse seguro de fecha
    from {{ source('raw_customer_data', 'CUSTOMERS_RAW') }}
)

select
  customer_id,
  first_name,
  last_name,
  join_date
from source
