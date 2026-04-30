with source as (
    select
        customer_id::integer as customer_id,
        first_name::varchar as first_name,
        last_name::varchar as last_name,
        try_strptime(join_date::varchar, '%Y-%m-%d') as join_date
    from {{ ref('customers') }}
)

select
  customer_id,
  first_name,
  last_name,
  join_date
from source
