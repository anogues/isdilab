# Laboratorio Guiado: Snowflake + dbt Cloud (Versión Simplificada)

**Objetivo:** Cargar un CSV en Snowflake y transformarlo con dbt Cloud hasta obtener un modelo analítico validado con tests.

> ¿No tienes Snowflake? Usa la versión **100% gratuita** con DuckDB: consulta la sección [Opcional: Ejecutar localmente con dbt Core](#opcional-ejecutar-localmente-con-dbt-core).

## Resumen del Proyecto

Este laboratorio implementa un pipeline completo de transformación de datos siguiendo la arquitectura medallion (BRONZE-SILVER-GOLD):

1. **Ingesta de datos (BRONZE):** Carga manual de un archivo CSV (`customers.csv`) con 7 registros de clientes (2 con errores intencionados) directamente en Snowflake
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
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER; -- Acceso automático a nuevos schemas
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
SELECT * FROM LAB_DB.BRONZE.CUSTOMERS_RAW LIMIT 7;
```

Debes ver 7 filas.

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

El proyecto ya incluye todos los archivos necesarios en `dbt/`. Revísalos para entender el diseño:

| Archivo | Función |
|---|---|
| `dbt/dbt_project.yml` | Configura staging como `table` en SILVER y marts en GOLD |
| `dbt/models/staging/sources.yml` | Fuente BRONZE (`LAB_DB.BRONZE.CUSTOMERS_RAW`) con tests de calidad |
| `dbt/models/staging/schema.yml` | Tests en capa SILVER |
| `dbt/models/staging/stg_customers.sql` | Tipado explícito y parseo seguro de fechas → SILVER |
| `dbt/models/marts/schema.yml` | Tests en capa GOLD |
| `dbt/models/marts/dim_customers.sql` | Dimensión analítica con `join_year` → GOLD |

**Tests de calidad incluidos en el proyecto:**

Capa BRONZE (`sources.yml`):
- `not_null` en `customer_id`: evita filas sin clave de cliente en el origen.
- `unique` en `customer_id`: detecta duplicados en la ingesta inicial.

Capa SILVER (`staging/schema.yml`):
- `not_null` en `first_name` y `last_name`: asegura nombres y apellidos completos.
- `not_null` en `join_date`: valida que el parseo de fecha no falló.

Capa GOLD (`marts/schema.yml`):
- `relationships` en `customer_id` → `stg_customers`: asegura integridad referencial entre capas.
- `not_null` en `last_name`: asegura que la dimensión mantiene apellidos completos.
- `not_null` en `join_date`: confirma que la fecha llegó íntegra desde staging.
- `not_null` en `join_year`: valida que el cálculo del año derivado es correcto.
- `accepted_values` en `join_year`: limita valores a `[2023]` y detecta fechas anómalas.

> **Nota:** El `name` en `dbt_project.yml` debe coincidir con el nombre del proyecto en dbt Cloud (`snowflake_lab_project` por defecto).

## Parte 5: Ejecutar, depurar y validar

### 5.1 Ejecuta `dbt build`

En la terminal de dbt Cloud:

```bash
dbt build
```

El build **fallará intencionadamente**. Esto es parte del laboratorio — verás errores como:

```
FAIL: 1   unique source_raw_customer_data_CUSTOMERS_RAW_customer_id
FAIL: 1   not_null stg_customers_last_name
FAIL: 1   not_null dim_customers_last_name
```

### 5.2 Diagnostica y corrige los datos

Los tests te están diciendo qué está mal:

| Error | Causa | Solución (`LAB_DB.BRONZE.CUSTOMERS_RAW`) |
|---|---|---|
| `unique` en `customer_id` | Hay dos filas con `customer_id = 3` | `DELETE FROM LAB_DB.BRONZE.CUSTOMERS_RAW WHERE customer_id = 3 AND last_name = 'Dupont';` |
| `not_null` en `last_name` | Frank no tiene apellido | `UPDATE LAB_DB.BRONZE.CUSTOMERS_RAW SET last_name = 'Miller' WHERE customer_id = 6;` |

Ejecuta esos comandos en Snowsight (rol `ACCOUNTADMIN`) y luego verifica:

```sql
SELECT * FROM LAB_DB.BRONZE.CUSTOMERS_RAW;
```

Debes ver 7 filas, cada una con `customer_id` único y `last_name` no vacío.

### 5.3 Re-ejecuta y valida

```bash
dbt build
```

Ahora todo debe salir en verde. Verifica los resultados en Snowflake:

```sql
SELECT * FROM LAB_DB.SILVER.STG_CUSTOMERS LIMIT 7;
SELECT * FROM LAB_DB.GOLD.DIM_CUSTOMERS LIMIT 7;
```

### 5.4 Genera la documentación

```bash
dbt docs generate
dbt docs serve
```

Explora el grafo de linaje y la documentación generada de los modelos.

## Opcional: Ejecutar localmente con dbt Core

Si prefieres dbt Core a dbt Cloud, tienes dos caminos:

### Opción A: dbt Core + Snowflake (requiere cuenta Snowflake)

1. Instala dbt Core y el adaptador de Snowflake:
   ```bash
   pip install dbt-core dbt-snowflake
   ```

2. Clona el repositorio y ve al directorio del proyecto:
   ```bash
   cd isdilab/dbt
   ```

3. Copia la plantilla de conexión al directorio `.dbt` y configura las variables de entorno:

   ```bash
   # macOS / Linux
   mkdir -p ~/.dbt
   cp profiles.yml.example ~/.dbt/profiles.yml
   export SNOWFLAKE_ACCOUNT="mi_org-mi_cuenta"
   export SNOWFLAKE_PASSWORD="mi_password"
   ```

   ```powershell
   # Windows (PowerShell)
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.dbt"
   Copy-Item profiles.yml.example "$env:USERPROFILE\.dbt\profiles.yml"
   $env:SNOWFLAKE_ACCOUNT = "mi_org-mi_cuenta"
   $env:SNOWFLAKE_PASSWORD = "mi_password"
   ```

4. Verifica y ejecuta:
   ```bash
   dbt debug
   dbt deps
   dbt build
   dbt docs generate && dbt docs serve
   ```

> **Nota:** Debes ejecutar igualmente el script SQL de la Parte 1 en Snowflake y cargar el CSV siguiendo la Parte 2.

### Opción B: dbt Core + DuckDB (100% gratuito, sin cuenta)

DuckDB es una base de datos OLAP local que reemplaza a Snowflake sin coste alguno.

**Cambios respecto a la versión Snowflake:**

| Aspecto | Snowflake (`dbt/`) | DuckDB (`dbt-duckdb/`) |
|---|---|---|
| Base de datos | Cloud (cuenta paga) | Archivo local `lab.duckdb` (gratis) |
| Ingesta | Carga manual CSV en Snowsight | `dbt seed` carga el CSV automáticamente |
| Capa BRONZE | Tabla `CUSTOMERS_RAW` en Snowflake | Tabla `customers` generada desde seed |
| Staging | `source()` apunta a tabla Snowflake | `ref()` apunta al seed |
| SQL | `::number`, `try_to_date()` | `::integer`, `try_strptime()` |

**Pasos:**

1. Instala dbt Core y el adaptador de DuckDB:
   ```bash
   pip install dbt-core dbt-duckdb
   ```

2. Ve al directorio del proyecto DuckDB:
   ```bash
   cd isdilab/dbt-duckdb
   ```

3. Copia la plantilla de conexión al directorio `.dbt`:

   ```bash
   # macOS / Linux
   mkdir -p ~/.dbt
   cp profiles.yml.example ~/.dbt/profiles.yml
   ```

   ```powershell
   # Windows (PowerShell)
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.dbt"
   Copy-Item profiles.yml.example "$env:USERPROFILE\.dbt\profiles.yml"
   ```

   El perfil no necesita credenciales — DuckDB es una base de datos embebida en un archivo local (`lab.duckdb`).

4. Ejecuta el pipeline:
   ```bash
   dbt seed     # Carga customers.csv en BRONZE (equivalente a Partes 1 y 2)
   dbt build    # Construye SILVER y GOLD + ejecuta tests
   ```

   `dbt seed` lee los archivos CSV de la carpeta `seeds/` y los materializa como tablas en la base de datos. Es la forma más simple de ingestar datos estáticos en dbt — ideal para archivos de referencia, tablas de lookup o, como en este caso, datasets pequeños de laboratorio. Sustituye por completo los pasos manuales de carga de las Partes 1 y 2.

   El build **fallará intencionadamente** — el CSV tiene dos errores para que aprendas a depurar:

   | Error | Causa | Solución |
   |---|---|---|
   | `unique` en `customer_id` | Dos filas comparten `customer_id = 3` | Elimina la fila de Charlie Dupont en `seeds/customers.csv` |
   | `not_null` en `last_name` | Frank no tiene apellido | Cambia `6,Frank,,2023-04-01` por `6,Frank,Miller,2023-04-01` |

   Corrige el CSV, re-ejecuta `dbt seed` y luego `dbt build` — ahora todo debe salir en verde.

5. Genera la documentación:
   ```bash
   dbt docs generate && dbt docs serve
   ```

El flujo es idéntico al de Snowflake (misma arquitectura medallion, mismos tests, misma salida). Solo cambia cómo se ingieren los datos y dos detalles de sintaxis SQL.

## Opcional: Agregar `fact_orders` (star schema)

Extiende el modelo analítico agregando una tabla de hechos de órdenes, formando un star schema con `dim_customers`.

### 1. Crear el CSV de órdenes

Guardar como `orders.csv`:

```csv
order_id,customer_id,order_date,total_amount,status
101,1,2023-03-01,150.50,completed
102,1,2023-04-15,200.00,completed
103,2,2023-03-10,89.99,completed
104,3,2023-05-01,320.00,cancelled
105,3,2023-06-15,110.25,completed
106,4,2023-04-01,450.00,completed
107,5,2023-05-20,75.00,pending
108,5,2023-07-01,199.99,completed
109,6,2023-06-01,0.00,refunded
110,1,2023-08-10,299.99,completed
```

### 2. Cargar a Snowflake (BRONZE)

En Snowsight, dentro de `LAB_DB.BRONZE`, crear tabla `ORDERS_RAW` desde el CSV (mismo proceso que con `CUSTOMERS_RAW`).

### 3. Registrar la fuente en `dbt/models/staging/sources.yml`

Agregar dentro de `raw_customer_data`, después de `CUSTOMERS_RAW`:

```yaml
      - name: ORDERS_RAW
        description: "Tabla bronza de órdenes cargada desde orders.csv."
        columns:
          - name: order_id
            description: "Identificador único de la orden."
            tests:
              - not_null
              - unique
          - name: customer_id
            description: "FK hacia CUSTOMERS_RAW."
            tests:
              - not_null
```

### 4. Crear `dbt/models/staging/stg_orders.sql`

```sql
with source as (
    select
        order_id::number as order_id,
        customer_id::number as customer_id,
        try_to_date(order_date::varchar, 'YYYY-MM-DD') as order_date,
        try_cast(total_amount as decimal(10,2)) as total_amount,
        lower(status) as status
    from {{ source('raw_customer_data', 'ORDERS_RAW') }}
)

select
    order_id,
    customer_id,
    order_date,
    total_amount,
    status
from source
where total_amount > 0
```

### 5. Crear `dbt/models/marts/fact_orders.sql`

```sql
{{ config(materialized='table', schema='GOLD') }}

with orders as (
    select order_id, customer_id, order_date, total_amount, status
    from {{ ref('stg_orders') }}
)

select
    order_id,
    customer_id,
    order_date,
    total_amount,
    status
from orders
```

### 6. Agregar tests en `dbt/models/marts/schema.yml`

Dentro del modelo `dim_customers`, agregar una nueva entrada para `fact_orders`:

```yaml
  - name: fact_orders
    description: "Tabla de hechos de órdenes. Grain = una línea por orden."
    columns:
      - name: order_id
        tests:
          - unique
          - not_null
      - name: customer_id
        tests:
          - not_null
          - relationships:
              arguments:
                to: ref('dim_customers')
                field: customer_id
      - name: order_date
        tests:
          - not_null
      - name: total_amount
        tests:
          - not_null
      - name: status
        tests:
          - accepted_values:
              arguments:
                values: ["completed", "cancelled", "pending", "refunded"]
```

### 7. Ejecutar

```bash
dbt run
dbt test
```

El pipeline final queda:

```
LAB_DB.BRONZE.CUSTOMERS_RAW ──► stg_customers ──► dim_customers
LAB_DB.BRONZE.ORDERS_RAW    ──► stg_orders    ──► fact_orders
                                                    │
                                                    └── dim_customers (FK join)
```

## Limpieza (opcional)

### Snowflake

```sql
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS LAB_DB;
DROP WAREHOUSE IF EXISTS DBT_LAB_WH;
DROP USER IF EXISTS DBT_USER;
DROP ROLE IF EXISTS TRANSFORMER;
```

### DuckDB

```bash
rm lab.duckdb
```
