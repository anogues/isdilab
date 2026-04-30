# Laboratorio Guiado: Snowflake + dbt Cloud (Versión Simplificada)

**Objetivo:** Cargar un CSV en Snowflake y transformarlo con dbt Cloud hasta obtener un modelo analítico validado con tests.

## Resumen del Proyecto

Este laboratorio implementa un pipeline completo de transformación de datos siguiendo la arquitectura medallion (BRONZE-SILVER-GOLD):

1. **Ingesta de datos (BRONZE):** Carga manual de un archivo CSV (`customers.csv`) con 5 registros de clientes directamente en Snowflake
2. **Transformación staging (SILVER):** Limpieza y tipado explícito de datos crudos, convirtiendo tipos de datos y parseando fechas de forma segura
3. **Modelado analítico (GOLD):** Creación de una dimensión de clientes (`dim_customers`) con atributos derivados para análisis

**Salida Esperada:**
- Base de datos `LAB_DB` con esquemas BRONZE, SILVER y GOLD
- Tabla `LAB_DB.SILVER.STG_CUSTOMERS` con datos limpios y tipados
- Tabla `LAB_DB.GOLD.DIM_CUSTOMERS` con dimensión analítica lista para reporting
- Tests de calidad de datos ejecutados exitosamente (validación de nulos, unicidad y valores aceptados)
- Pipeline reproducible mediante `dbt build` sin dependencias externas

## Tecnologías

- Snowflake
- dbt Cloud (Developer plan)

## Prerrequisitos

1. Tener cuenta activa de Snowflake.
2. Tener cuenta activa de dbt Cloud.
3. Tener este repositorio disponible en Git.
4. Usar el archivo `customers.csv` de este proyecto.

## Parte 1: Configuración en Snowflake

Ejecuta este script con rol `ACCOUNTADMIN` en Snowsight:

```sql
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS LAB_DB; -- Base de datos del laboratorio
CREATE SCHEMA IF NOT EXISTS LAB_DB.BRONZE; -- Capa fuente (bronze)

CREATE ROLE IF NOT EXISTS TRANSFORMER; -- Rol que usará dbt
GRANT ROLE TRANSFORMER TO ROLE SYSADMIN; -- Permite administración desde SYSADMIN

CREATE WAREHOUSE IF NOT EXISTS DBT_LAB_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE; -- Coste controlado en el lab

GRANT USAGE ON WAREHOUSE DBT_LAB_WH TO ROLE TRANSFORMER; -- Ejecutar queries
GRANT USAGE ON DATABASE LAB_DB TO ROLE TRANSFORMER; -- Acceso a la DB
GRANT USAGE ON SCHEMA LAB_DB.BRONZE TO ROLE TRANSFORMER; -- Leer fuente BRONZE
GRANT CREATE SCHEMA ON DATABASE LAB_DB TO ROLE TRANSFORMER; -- Crear SILVER y GOLD
GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER; -- Materialización table
GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER; -- Materialización view

CREATE USER IF NOT EXISTS DBT_USER
  PASSWORD = '<CAMBIA_ESTA_PASSWORD>' -- Sustituir por password real
  LOGIN_NAME = 'DBT_USER'
  DEFAULT_WAREHOUSE = 'DBT_LAB_WH'
  DEFAULT_ROLE = 'TRANSFORMER'
  MUST_CHANGE_PASSWORD = FALSE;

GRANT ROLE TRANSFORMER TO USER DBT_USER; -- Vincular usuario técnico de dbt
```

## Parte 2: Cargar datos en Snowflake

1. En Snowsight, entra en `LAB_DB` -> schema `BRONZE`.
2. Crea tabla `CUSTOMERS_RAW` con “Load Data” cargando el archivo `customers.csv`.
3. Verifica:

```sql
SELECT * FROM LAB_DB.BRONZE.CUSTOMERS_RAW LIMIT 5;
```

Debes ver 5 filas.

## Parte 3: Configurar dbt Cloud

1. Crea un proyecto en dbt Cloud y conecta tu repositorio Git.
2. En la configuración del proyecto, define **Project Subdirectory = `dbt`** (porque `dbt_project.yml` está en `isdilab/dbt/dbt_project.yml`).
3. Configura la conexión a Snowflake con:
- Account: `<tu_org>-<tu_account>`
- User: `DBT_USER`
- Password: la del paso anterior
- Role: `TRANSFORMER`
- Warehouse: `DBT_LAB_WH`
- Database: `LAB_DB`
- Schema (dev): `DBT_<TUS_INICIALES>`
4. Guarda y valida el “Test Connection”.

## Parte 4: Ajustar el proyecto dbt (sin paquetes externos)

### `dbt_project.yml`

Mantén esta configuración de modelos:

```yaml
models:
  snowflake_lab_project: # Debe coincidir con el name de tu proyecto dbt
    +materialized: view
    staging:
      +materialized: table # Staging como tabla física
      +schema: SILVER # LAB_DB.SILVER
    marts:
      +schema: GOLD # LAB_DB.GOLD
```

### `models/staging/sources.yml`

Usa la tabla cargada en Snowflake como source:

```yaml
version: 2

sources:
  - name: raw_customer_data
    database: LAB_DB # Base de datos origen en Snowflake
    schema: BRONZE # Schema origen
    tables:
      - name: CUSTOMERS_RAW # Tabla cargada manualmente desde customers.csv
        columns:
          - name: customer_id
            description: "Identificador del cliente en BRONZE."
            tests:
              - not_null
              - unique
```

Función de estos checks en BRONZE:

- `not_null`: evita filas sin clave de cliente en la capa de origen.
- `unique`: detecta duplicados de `customer_id` en la ingesta inicial.

### `models/staging/stg_customers.sql`

```sql
with source as (
  select
    customer_id::number as customer_id, -- Tipado explícito
    first_name::varchar as first_name,
    last_name::varchar as last_name,
    try_to_date(join_date::varchar, 'YYYY-MM-DD') as join_date -- Parse seguro de fecha
  from {{ source('raw_customer_data', 'CUSTOMERS_RAW') }} -- LAB_DB.BRONZE.CUSTOMERS_RAW
)

select
  customer_id,
  first_name,
  last_name,
  join_date
from source
```

### `models/marts/dim_customers.sql`

```sql
{{ config(materialized='table') }}

with customers as (
  select
    customer_id,
    first_name,
    last_name,
    join_date
  from {{ ref('stg_customers') }} -- Referencia al modelo staging
)

select
  customer_id,
  first_name,
  last_name,
  join_date,
  year(join_date) as join_year -- Atributo derivado para analítica
from customers
```

### `models/marts/schema.yml` (tests adicionales)

```yaml
version: 2

models:
  - name: dim_customers
    columns:
      - name: customer_id
        tests:
          - unique
          - not_null
      - name: join_date
        tests:
          - not_null
      - name: join_year
        tests:
          - not_null
          - accepted_values:
              values: [2023]
```

Función de estos checks en GOLD:

- `not_null` en `customer_id`: asegura que la dimensión tiene claves válidas.
- `not_null` en `join_date`: valida que el parseo de fecha no falló en staging.
- `not_null` en `join_year`: asegura que el cálculo del año es correcto.
- `accepted_values` en `join_year`: limita valores al año real de los datos (2023) y detecta fechas corruptas/anómalas.

## Parte 5: Ejecutar y validar

En la terminal de dbt Cloud:

```bash
dbt build
```

Verifica en Snowflake:

```sql
SELECT * FROM LAB_DB.SILVER.STG_CUSTOMERS LIMIT 5;
SELECT * FROM LAB_DB.GOLD.DIM_CUSTOMERS LIMIT 5;
```

Si ambos `SELECT` devuelven 5 filas y `dbt build` termina sin errores, el laboratorio está correcto.

## Limpieza (opcional)

```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS LAB_DB;
DROP WAREHOUSE IF EXISTS DBT_LAB_WH;
DROP USER IF EXISTS DBT_USER;
DROP ROLE IF EXISTS TRANSFORMER;
```
