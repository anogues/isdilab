-- models/staging/stg_customers.sql

with source as (
    -- Selecciona desde la tabla externa (customers_external)
    -- Accede a la columna VARIANT (por defecto 'value') y extrae los campos
    select
        value:c1::NUMBER as customer_id,  -- Extrae el campo 'c1' y conviértelo a NUMBER
        value:c2::VARCHAR as first_name, -- Extrae 'c2' y conviértelo a VARCHAR
        value:c3::VARCHAR as last_name,  -- Extrae 'c3' y conviértelo a VARCHAR
        -- Extrae 'c4', conviértelo a VARCHAR (por seguridad), luego intenta convertirlo a DATE
        try_to_date(value:c4::VARCHAR, 'YYYY-MM-DD') as join_date
    from {{ source('raw_customer_data', 'customers_external') }} -- La tabla externa creada por dbt run-operation
)

select
    customer_id,
    first_name,
    last_name,
    join_date
from source
where customer_id is not null -- Mismo filtro de calidad