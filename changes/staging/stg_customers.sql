-- models/staging/stg_customers.sql
-- Este modelo SE MATERIALIZARÁ COMO TABLA (ej: en BRONZE_RAW_STAGING)
-- Leyendo directamente desde el stage interno.
-- No hay 'source' en sources.yml para esto, se consulta el stage directamente.

select
    $1::NUMBER as customer_id,
    $2::VARCHAR as first_name,
    $3::VARCHAR as last_name,
    try_to_date($4::VARCHAR, 'YYYY-MM-DD') as join_date
from @LAB_DB.bronze.INTERNAL_CUSTOMER_STAGE/customers.csv -- Asume que el archivo se llama así en el stage
  ( FILE_FORMAT => 'LAB_DB.bronze.my_csv_format' )
where $1 is not null -- Filtrar aquí si es necesario
