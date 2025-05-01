## Laboratorio Guiado: Construyendo una Arquitectura de Datos Simple con Terraform, AWS, Snowflake y dbt Cloud (Versión Final v2)

**Objetivo:** Construir un pipeline de datos que use Terraform para aprovisionar infraestructura fuente (bucket S3, Stage Snowflake en schema `bronze`), cargue datos de muestra, y use dbt Cloud para crear una tabla externa, transformar los datos y materializarlos en esquemas específicos (`BRONZE_RAW_STAGING`, `BRONZE_ANALYTICS`). Esta versión incluye un paso manual necesario para la configuración IAM.

**Tecnologías Principales:**
*   AWS (S3) - Elegible para el Nivel Gratuito de almacenamiento
*   Snowflake - Prueba Gratuita (30 días, $400 en créditos)
*   Terraform Cloud - Nivel Gratuito
*   dbt Cloud - Plan Developer (Gratuito, 1 puesto)
*   Paquete dbt: `dbt-external-tables`
*   Proveedor Git (GitHub, GitLab, etc.) - Nivel Gratuito

---

### Prerrequisitos

Antes de comenzar el laboratorio, los estudiantes **DEBEN**:

1.  **Crear una Cuenta de AWS:** [aws.amazon.com](https://aws.amazon.com/). Necesitarás la capacidad de crear usuarios/roles IAM y buckets S3. **Importante:** Anota tu **ID de Cuenta de AWS** (número de 12 dígitos). Lo necesitarás para la política IAM personalizada.
2.  **Crear una Cuenta de Snowflake:** [signup.snowflake.com](https://signup.snowflake.com/). Elige la edición Standard en AWS en una región conveniente para ti (ej., `eu-west-1`). Anota tu **Nombre de Organización** y **Nombre de Cuenta** (los encontrarás en la URL de activación o de login, ej: `nombreorg-nombrecuenta.snowflakecomputing.com`).
3.  **Crear una Cuenta de Terraform Cloud:** [app.terraform.io/signup](https://app.terraform.io/signup). Crea una organización.
4.  **Crear una Cuenta de dbt Cloud:** [cloud.getdbt.com/signup](https://cloud.getdbt.com/signup/). Elige el plan Developer (Gratuito).
5.  **Crear un Repositorio Git:** En GitHub, GitLab, Bitbucket o Azure DevOps. Alojará tu código Terraform y dbt. Inicialízalo con un `README.md`.
6.  **Instalar Git:** [git-scm.com/downloads](https://git-scm.com/downloads).
7.  **(Opcional pero Recomendado):** Instalar AWS CLI ([docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)) para facilitar la carga a S3 más tarde.

---

### Datos de Muestra

Usemos un archivo CSV simple. Crea un archivo llamado `customers.csv` con el siguiente contenido:

```csv
customer_id,first_name,last_name,join_date
1,Alice,Smith,2023-01-15
2,Bob,Johnson,2023-02-20
3,Charlie,Williams,2023-01-15
4,David,Brown,2023-03-10
5,Eve,Davis,2023-02-20
```

---

### Parte 1: Configuración de AWS y Terraform Cloud

**Objetivo:** Configurar Terraform Cloud con credenciales de AWS para gestionar recursos de AWS, usando una política IAM personalizada de mínimos privilegios.

1.  **Crear Política IAM Personalizada (Recomendado: Política Gestionada):**
    *   Ve a la Consola IAM de AWS -> Políticas -> Crear política.
    *   Ve a la pestaña **JSON**.
    *   **Borra** el contenido existente y **pega** el siguiente JSON, **REEMPLAZANDO `YOUR_AWS_ACCOUNT_ID` con tu ID de cuenta de AWS real (número de 12 dígitos)**:
        ```json
        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowManageSnowflakeLabIAMRole",
                    "Effect": "Allow",
                    "Action": [
                        "iam:CreateRole",
                        "iam:DeleteRole",
                        "iam:GetRole",
                        "iam:TagRole",
                        "iam:UpdateAssumeRolePolicy",
                        "iam:AttachRolePolicy",
                        "iam:DetachRolePolicy",
                        "iam:ListRolePolicies",
                        "iam:ListInstanceProfilesForRole"
                    ],
                    "Resource": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/snowflake-lab-access-role-*"
                },
                {
                    "Sid": "AllowManageSnowflakeLabIAMPolicy",
                    "Effect": "Allow",
                    "Action": [
                        "iam:CreatePolicy",
                        "iam:DeletePolicy",
                        "iam:GetPolicy",
                        "iam:GetPolicyVersion",
                        "iam:TagPolicy"
                    ],
                    "Resource": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:policy/snowflake-lab-s3-policy-*"
                },
                {
                    "Sid": "AllowListRolePoliciesForAttachmentCheck",
                    "Effect": "Allow",
                    "Action": [
                        "iam:ListAttachedRolePolicies"
                    ],
                    "Resource": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/snowflake-lab-access-role-*"
                }
            ]
        }
        ```
    *   Haz clic en "Siguiente: Etiquetas", "Siguiente: Revisar".
    *   Dale un **Nombre** (ej., `TerraformSnowflakeLabIAMPermissions`) y una Descripción.
    *   Haz clic en **"Crear política"**.

2.  **Crear Usuario IAM de AWS para Terraform:**
    *   Ve a la Consola IAM de AWS -> Usuarios -> Añadir usuarios.
    *   Nombre de usuario: `terraform-lab-user`.
    *   Selecciona **Clave de acceso - Acceso programático**.
    *   Haz clic en "Siguiente: Permisos".
    *   Selecciona "Adjuntar políticas existentes directamente".
    *   Busca y selecciona **dos** políticas:
        *   `AmazonS3FullAccess` (Para gestionar el bucket S3).
        *   La política personalizada que acabas de crear (ej., `TerraformSnowflakeLabIAMPermissions`). (Haz clic en "Actualizar" si no aparece inmediatamente).
    *   Haz clic en "Siguiente: Etiquetas" -> "Siguiente: Revisar" -> **"Crear usuario"**.
    *   **CRÍTICO:** Descarga o copia el **ID de clave de acceso** y la **Clave de acceso secreta**.

3.  **Clonar Tu Repositorio Git:**
    ```bash
    git clone <tu-url-repo-git>
    cd <nombre-tu-repo>
    ```

4.  **Crear Workspace en Terraform Cloud:**
    *   Ve a tu organización de Terraform Cloud -> "New workspace".
    *   Elige "Version control workflow", conecta tu proveedor Git, selecciona tu repositorio.
    *   Nombre del Workspace: `dbt-snowflake-lab`.
    *   Working Directory: (déjalo en blanco).
    *   Haz clic en "Create workspace".

5.  **Configurar Variables de Terraform Cloud (AWS):**
    *   En tu workspace `dbt-snowflake-lab` -> "Variables".
    *   Añade las siguientes **Environment Variables** (marcándolas como **Sensitive**):
        *   `AWS_ACCESS_KEY_ID`: Pega el ID de Clave de Acceso del usuario IAM.
        *   `AWS_SECRET_ACCESS_KEY`: Pega la Clave de Acceso Secreta del usuario IAM.
    *   Añade la siguiente **Terraform Variable**:
        *   `aws_region`: Introduce tu código de región AWS (ej., `AWS_EU_WEST_1`).

---

### Parte 2: Configuración de Snowflake y Conexión con Terraform

**Objetivo:** Configurar Terraform Cloud con credenciales de Snowflake usando las variables de entorno correctas para cuentas con formato Org/Account Name.

1.  **Crear Usuario y Rol de Snowflake para Terraform:**
    *   Inicia sesión en Snowsight usando un rol `ACCOUNTADMIN`.
    *   Abre una Worksheet y ejecuta (elige una contraseña fuerte):
        ```sql
        USE ROLE ACCOUNTADMIN;
        CREATE ROLE IF NOT EXISTS TERRAFORM_ROLE;
        GRANT ROLE TERRAFORM_ROLE TO ROLE SYSADMIN;
        GRANT CREATE DATABASE ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        GRANT ROLE TERRAFORM_ROLE TO USER <tu_usuario_admin_snowflake>; -- Opcional

        CREATE USER IF NOT EXISTS TERRAFORM_USER
          PASSWORD='<tu-contraseña-fuerte-aqui>' -- !! CAMBIA ESTO !!
          LOGIN_NAME='TERRAFORM_USER'
          DISPLAY_NAME='TERRAFORM_USER'
          DEFAULT_WAREHOUSE='COMPUTE_WH'
          DEFAULT_ROLE='TERRAFORM_ROLE'
          MUST_CHANGE_PASSWORD=FALSE;
        GRANT ROLE TERRAFORM_ROLE TO USER TERRAFORM_USER;
        ```

2.  **Configurar Variables de Terraform Cloud (Snowflake):**
    *   En tu workspace `dbt-snowflake-lab` -> "Variables".
    *   Añade las siguientes **Environment Variables** (marcándolas como **Sensitive**):
        *   `SNOWFLAKE_ORGANIZATION_NAME`: Pega el nombre de tu organización Snowflake.
        *   `SNOWFLAKE_ACCOUNT_NAME`: Pega el nombre de tu cuenta Snowflake.
        *   `SNOWFLAKE_PASSWORD`: Pega la contraseña que estableciste para `TERRAFORM_USER`.
    *   Añade las siguientes **Environment Variables** (No sensibles):
        *   `SNOWFLAKE_USER`: `TERRAFORM_USER`.
        *   `SNOWFLAKE_ROLE`: `TERRAFORM_ROLE`.
    *   Añade (o verifica) la siguiente **Terraform Variable**:
        *   `snowflake_region`: El identificador de tu región Snowflake (ej., `eu-west-1`).

---

### Parte 3: Despliegue de Infraestructura (Terraform)

**Objetivo:** Definir y desplegar el bucket S3, Rol IAM temporal, Integración Snowflake, Schema `bronze` y Stage. La política de confianza del Rol IAM se actualizará manualmente después.

1.  **Crear Archivos de Código Terraform:**
    *   En tu repositorio Git local, crea/modifica los siguientes archivos:

    *   `terraform/providers.tf`:
        ```terraform
        terraform {
          required_providers {
            aws = {
              source  = "hashicorp/aws"
              version = "~> 5.0"
            }
            snowflake = {
              source  = "Snowflake-Labs/snowflake"
              version = "~> 1.0.5"
            }
          }
          cloud {
            organization = "<Tu-Nombre-Org-TFC>" # Reemplaza
            workspaces {
              name = "dbt-snowflake-lab"
            }
          }
        }

        provider "aws" {
          region = var.aws_region
        }

        provider "snowflake" {
          # Autenticación vía Variables de Entorno configuradas en TFC
          # Habilitar características preview requeridas
          preview_features_enabled = [
              "snowflake_storage_integration_resource",
              "snowflake_stage_resource"
          ]
        }
        ```
        *   **Acción:** Reemplaza `<Tu-Nombre-Org-TFC>` con tu organización. Verifica la versión del proveedor Snowflake.

    *   `terraform/variables.tf`:
        ```terraform
        variable "aws_region" {
          description = "Región de AWS para los recursos"
          type        = string
        }
    
        variable "snowflake_region" {
          description = "Identificador de región de Snowflake (ej., aws_us_east_1)"
          type        = string
        }
    
        variable "bucket_prefix" {
          description = "Prefijo para el nombre del bucket S3 para asegurar unicidad"
          type        = string
          default     = "dbt-lab-data"
        }
    
        variable "snowflake_db_name" {
          description = "Nombre para la base de datos Snowflake"
          type        = string
          default     = "LAB_DB"
        }
    
        variable "snowflake_schema_name" {
          description = "Nombre para el esquema Snowflake"
          type        = string
          default     = "bronze"
        }
    
        variable "snowflake_stage_name" {
          description = "Nombre para el stage externo de Snowflake"
          type        = string
          default     = "S3_CUSTOMER_STAGE"
        }
    
        variable "snowflake_integration_name" {
            description = "Nombre para la Integración de Almacenamiento de Snowflake"
            type = string
            default = "S3_INTEGRATION"
        }
        ```

    *   `terraform/main.tf`: (Versión Final con Rol Único y Paso Manual)
        ```terraform
        # --- Recursos AWS ---
        resource "random_string" "bucket_suffix" { length = 8; special = false; upper = false }
        resource "aws_s3_bucket" "data_bucket" {
          bucket = "${var.bucket_prefix}-${random_string.bucket_suffix.result}"
          tags = { Name = "dbt-lab-bucket", Environment = "Lab", ManagedBy = "Terraform" }
        }
        data "aws_caller_identity" "current" {}

        # Rol IAM para Integración Snowflake - SOLO CREACIÓN INICIAL
        resource "aws_iam_role" "snowflake_access_role_initial" {
          name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"
          assume_role_policy = jsonencode({
            Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = {AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"}, Action = "sts:AssumeRole"}]
          }) # Política TEMPORAL
          tags = { Name = "snowflake-lab-access-role", Environment = "Lab", ManagedBy = "Terraform" }
        }

        # Política IAM que otorga acceso S3
        resource "aws_iam_policy" "snowflake_access_policy" {
          name = "snowflake-lab-s3-policy-${random_string.bucket_suffix.result}"
          description = "Política que otorga acceso de Snowflake al bucket S3 específico"
          policy = jsonencode({
            Version = "2012-10-17", Statement = [
              { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.data_bucket.arn}/*" },
              { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.data_bucket.arn, Condition = { StringLike = { "s3:prefix": ["*"] } } }
            ]
          })
        }

        # Adjuntar la política de acceso S3 al rol
        resource "aws_iam_role_policy_attachment" "snowflake_access_attach" {
          role       = aws_iam_role.snowflake_access_role_initial.name
          policy_arn = aws_iam_policy.snowflake_access_policy.arn
        }

        # --- Recursos Snowflake ---
        resource "snowflake_database" "lab_db" {
          name = upper(var.snowflake_db_name); comment = "Base de datos para el lab dbt"
        }
        resource "snowflake_schema" "bronze_schema" {
          database = snowflake_database.lab_db.name; name = upper(var.snowflake_schema_name); comment = "Esquema bronze fuente"
        }

        # Crear la Integración de Almacenamiento
        resource "snowflake_storage_integration" "s3_integration" {
          name                 = upper(var.snowflake_integration_name); type = "EXTERNAL_STAGE"; storage_provider = "S3"; enabled = true
          storage_aws_role_arn = aws_iam_role.snowflake_access_role_initial.arn # ARN del rol temporal
          storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"]
          comment              = "Integración S3 para lab dbt"
          depends_on           = [aws_iam_role.snowflake_access_role_initial]
        }

        # Crear el Stage Externo
        resource "snowflake_stage" "s3_stage" {
          name                = upper(var.snowflake_stage_name); database = snowflake_database.lab_db.name; schema = snowflake_schema.bronze_schema.name
          url                 = "s3://${aws_s3_bucket.data_bucket.bucket}/"
          storage_integration = snowflake_storage_integration.s3_integration.name
          comment             = "Stage externo para datos de clientes"
          file_format         = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE"
          depends_on          = [snowflake_storage_integration.s3_integration]
        }
        ```

    *   `terraform/outputs.tf`:
        ```terraform
        # terraform/outputs.tf
        output "aws_s3_bucket_name" {
          description = "Nombre del bucket S3"
          value = aws_s3_bucket.data_bucket.bucket
        }
    
        output "aws_s3_bucket_arn" {
          description = "ARN del bucket S3"
          value = aws_s3_bucket.data_bucket.arn
        }
    
        output "snowflake_database_name" {
          description = "Nombre DB Snowflake"
          value = snowflake_database.lab_db.name
        }
    
        output "snowflake_schema_name" {
          description = "Nombre Schema Snowflake ('bronze')"
          value = snowflake_schema.bronze_schema.name
        }
    
        output "snowflake_stage_name" {
          description = "Nombre completo Stage Externo"
          value = "${snowflake_database.lab_db.name}.${snowflake_schema.bronze_schema.name}.${snowflake_stage.s3_stage.name}"
        }
    
        output "snowflake_iam_role_arn" {
          description = "ARN Rol IAM"
          value = aws_iam_role.snowflake_access_role_initial.arn
        }
    
        output "snowflake_integration_name" {
          description = "Nombre Integración Snowflake"
          value = snowflake_storage_integration.s3_integration.name
        }
    
        # Outputs informativos que se necesitarán para el paso manual
        output "manual_step_info_integration_name" {
          description = "Nombre de la integración a describir en Snowflake para obtener datos para la política IAM"
          value       = upper(var.snowflake_integration_name)
        }
        output "manual_step_info_iam_role_name" {
          description = "Nombre del Rol IAM a editar en la consola de AWS"
          value       = aws_iam_role.snowflake_access_role_initial.name
        }
        ```

2.  **Confirmar (Commit) y Subir (Push) Código Terraform.**
3.  **Ejecutar Plan y Apply de Terraform en Terraform Cloud:**
    *   Debería completarse en **una sola pasada**.
    *   Anota los valores de `manual_step_info_integration_name`, `manual_step_info_iam_role_name` y `aws_s3_bucket_name` de los Outputs.

4.  **PASO MANUAL CRÍTICO: Actualizar Política de Confianza IAM:**
    *   **Obtener Datos de Snowflake:** Ejecuta `DESC INTEGRATION <Nombre_Integracion_del_Output>;` en Snowsight (con `ACCOUNTADMIN`). Copia `STORAGE_AWS_IAM_USER_ARN` y `STORAGE_AWS_EXTERNAL_ID`.
    *   **Actualizar Política en AWS:** Ve a IAM -> Roles -> Busca el rol (`manual_step_info_iam_role_name`) -> "Trust relationships" -> "Edit trust policy". **Reemplaza TODO** el JSON por el correcto, pegando los valores copiados de Snowflake:
        ```json
        { "Version": "2012-10-17", "Statement": [{ "Effect": "Allow", "Principal": {"AWS": "PEGAR_ARN_USUARIO_IAM_SNOWFLAKE"}, "Action": "sts:AssumeRole", "Condition": {"StringEquals": {"sts:ExternalId": "PEGAR_ID_EXTERNO_SNOWFLAKE"}}}] }
        ```
    *   Haz clic en "Update policy".

5.  **Verificar Recursos:** Comprueba que todo existe en AWS y Snowflake.

---

### Parte 4: Carga de Datos

**Objetivo:** Subir `customers.csv` a S3.

1.  **Subir a S3:** Usa AWS CLI o la consola para subir `customers.csv` al bucket (`aws_s3_bucket_name`).
    ```bash
    aws s3 cp customers.csv s3://<tu-nombre-bucket>/customers.csv
    ```
2.  **Verificar en Snowflake:**
    ```sql
    USE DATABASE LAB_DB; USE SCHEMA bronze;
    LS @S3_CUSTOMER_STAGE;
    SELECT $1, $2, $3, $4 FROM @S3_CUSTOMER_STAGE/customers.csv;
    ```

---

### Parte 5: Configuración de dbt Cloud

**Objetivo:** Conectar dbt Cloud a Git y Snowflake.

1.  **Crear Proyecto dbt Cloud:** Configura la conexión a Snowflake (nombre proyecto `Snowflake Lab Project`, warehouse `Snowflake`, cuenta `nombreorg-nombrecuenta` o con región, rol `TRANSFORMER`, db `LAB_DB`, warehouse `DBT_LAB_WH`, user `DBT_USER`, password). El test inicial fallará. Conecta el repositorio Git.
2.  **Crear Objetos dbt en Snowflake:** En Snowsight (con `ACCOUNTADMIN`):
    ```sql
    USE ROLE ACCOUNTADMIN;
    CREATE ROLE IF NOT EXISTS TRANSFORMER;
    GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;
    CREATE WAREHOUSE IF NOT EXISTS DBT_LAB_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
    GRANT USAGE ON WAREHOUSE DBT_LAB_WH TO ROLE TRANSFORMER;
    GRANT USAGE ON DATABASE LAB_DB TO ROLE TRANSFORMER;
    GRANT USAGE ON SCHEMA LAB_DB.bronze TO ROLE TRANSFORMER;
    GRANT USAGE ON STAGE LAB_DB.bronze.S3_CUSTOMER_STAGE TO ROLE TRANSFORMER; -- USAGE en Stage
    GRANT CREATE SCHEMA ON DATABASE LAB_DB TO ROLE TRANSFORMER; -- Para crear BRONZE_RAW_STAGING, BRONZE_ANALYTICS
    GRANT CREATE EXTERNAL TABLE ON SCHEMA LAB_DB.bronze TO ROLE TRANSFORMER; -- Para dbt run-operation

    CREATE USER IF NOT EXISTS DBT_USER PASSWORD = '<contraseña-dbt-cloud>' LOGIN_NAME = 'DBT_USER' DEFAULT_WAREHOUSE = 'DBT_LAB_WH' DEFAULT_ROLE = 'TRANSFORMER' MUST_CHANGE_PASSWORD = FALSE;
    GRANT ROLE TRANSFORMER TO USER DBT_USER;
    GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER; -- Para tablas en nuevos schemas
    GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER;  -- Para vistas en nuevos schemas
    ```
    *   **Acción:** Reemplaza `<contraseña-dbt-cloud>`.
3.  **Volver a Probar Conexión:** En dbt Cloud, edita la conexión, reintroduce la contraseña y prueba. Guarda.
4.  **Credenciales de Desarrollo:** En dbt Cloud -> "Develop" -> "Credentials". Configura: Role: `TRANSFORMER`, Warehouse: `DBT_LAB_WH`, Database: `LAB_DB`, Schema: `DBT_<tus_iniciales>`. Guarda.

---

### Parte 6: Transformación de Datos (dbt Cloud)

**Objetivo:** Definir fuentes, modelos y tests. Crear tabla externa con `run-operation`. Materializar modelos en `BRONZE_RAW_STAGING` y `BRONZE_ANALYTICS`.

1.  **Crear `packages.yml`:** En la raíz del proyecto, crea `packages.yml` (o edítalo):
    ```yaml
    packages:
      - package: dbt-labs/dbt_external_tables
        version: 0.11.1
    ```

2.  **Crear/Verificar `dbt_project.yml`:** Asegúrate de que los esquemas de destino están definidos:
    ```yaml
    name: 'snowflake_lab_project'
    version: '1.0.0'
    config-version: 2
    profile: 'default'
    model-paths: ["models"]
    # ... otros paths ...
    target-path: "target"
    clean-targets: ["target", "dbt_packages"]
    models:
      snowflake_lab_project: # Nombre del proyecto
        staging: # Carpeta staging/
          +schema: BRONZE_RAW_STAGING # Esquema destino para staging
          +materialized: table
        marts: # Carpeta marts/
          +schema: BRONZE_ANALYTICS   # Esquema destino para marts
          +materialized: view # Default para marts
    ```
    *   Crea carpetas `models/staging`, `models/marts`.

3.  **Definir Source (`models/staging/sources.yml`):** (Define la tabla externa que `run-operation` creará)
    ```yaml
    version: 2

    sources:
      - name: raw_customer_data # Nombre arbitrario para el grupo de fuentes
        database: LAB_DB        # DB donde reside el schema/stage
        schema: bronze           # Schema donde reside el stage
        loader: S3               # Indicador del cargador (más descriptivo que 'external')
                                 # O puedes omitir 'loader' si defines 'external' abajo

        tables:
          - name: customers_external # Nombre arbitrario para esta fuente externa específica
            description: "Representa archivos CSV de clientes en el stage S3 (schema bronze)"

            # Propiedades externas AHORA anidadas bajo la tabla
            external:
              location: "@S3_CUSTOMER_STAGE" # Stage object en Snowflake (relativo a LAB_DB.bronze)
              file_format: "(TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE)"
              # auto_refresh: false # (Opcional)
              # pattern: ".*[.]csv" # (Opcional, si quieres filtrar archivos en el stage)

            # Definición de columnas (igual que antes)
            # ¡Importante! Al usar stage_external_sources para crear la tabla,
            # esta sección 'columns' puede ser menos relevante aquí, ya que la operación
            # a menudo infiere el schema o usa una plantilla. Es útil para documentación.
            columns:
              - name: customer_id
                description: "ID Cliente (desde $1)"
                data_type: NUMBER
              - name: first_name
                description: "Nombre (desde $2)"
                data_type: VARCHAR
              - name: last_name
                description: "Apellido (desde $3)"
                data_type: VARCHAR
              - name: join_date
                description: "Fecha unión (desde $4)"
                data_type: DATE
    ```

4.  **Modelo Staging (`models/staging/stg_customers.sql`):** (Lee la tabla externa y escribe en `BRONZE_RAW_STAGING`)
    ```sql
    with source as (
        -- Lee desde la tabla externa LAB_DB.bronze.customers_external
        select
            value:c1::NUMBER as customer_id,  -- Extrae campos del VARIANT
            value:c2::VARCHAR as first_name,
            value:c3::VARCHAR as last_name,
            try_to_date(value:c4::VARCHAR, 'YYYY-MM-DD') as join_date
        from {{ source('raw_customer_data', 'customers_external') }}
    )
    select customer_id, first_name, last_name, join_date
    from source where customer_id is not null
    ```

5.  **Modelo Mart (`models/marts/dim_customers.sql`):** (Lee de staging y escribe en `BRONZE_ANALYTICS`)
    ```sql
    with customers as (
        select customer_id, first_name, last_name, join_date
        -- Refiere al modelo staging (estará en BRONZE_RAW_STAGING.stg_customers)
        from {{ ref('stg_customers') }}
    )
    select customer_id, first_name, last_name, join_date, year(join_date) as join_year
    from customers
    ```

6.  **Tests (`models/staging/schema.yml`, `models/marts/schema.yml`):** (Define tests para `stg_customers` y `dim_customers`).
    ```yaml
    # models/staging/schema.yml
    version: 2; models: [{ name: stg_customers, description: "Tabla staging clientes en BRONZE_RAW_STAGING.", columns: [{name: customer_id, tests: [unique, not_null]}, {name: first_name, tests: [not_null]}, {name: last_name}, {name: join_date, tests: [not_null]}]}]
    ```
    ```yaml
    # models/marts/schema.yml
    version: 2; models: [{ name: dim_customers, description: "Vista dimensión clientes en BRONZE_ANALYTICS.", columns: [{name: customer_id, tests: [unique, not_null, relationships: {to: ref('stg_customers'), field: customer_id}]}, {name: first_name}, {name: last_name}, {name: join_date}, {name: join_year}]}]
    ```

7.  **Commit y Push del código dbt.**

---

### Parte 7: Ejecutar y Verificar

**Objetivo:** Instalar paquetes dbt, crear tabla externa, ejecutar pipeline y revisar resultados.

1.  **Ejecutar Secuencia dbt:**
    *   En la IDE de dbt Cloud (terminal):
        ```bash
        # 1. Instalar/Actualizar Paquetes
        dbt deps

        # 2. Crear/Actualizar Tabla Externa desde sources.yml
        dbt run-operation stage_external_sources --vars '{ext_schema: bronze, ext_database: LAB_DB}'
        # Verifica la salida, debe crear LAB_DB.bronze.customers_external

        # 3. Ejecutar Modelos (staging y marts)
        dbt run

        # 4. Ejecutar Tests
        dbt test
        ```
    *   Verificar que todo se complete con éxito.

2.  **Verificar en Snowflake:**
    *   Con un rol adecuado (`TRANSFORMER`, `SYSADMIN`...):
        ```sql
        USE ROLE TRANSFORMER; USE WAREHOUSE DBT_LAB_WH;

        -- Verifica la tabla externa creada por dbt run-operation
        SELECT * FROM LAB_DB.bronze.customers_external LIMIT 5;

        -- Verifica la tabla staging creada por dbt run
        SELECT * FROM LAB_DB.BRONZE_RAW_STAGING.STG_CUSTOMERS LIMIT 5; -- Esquema actualizado

        -- Verifica la vista mart creada por dbt run
        SELECT * FROM LAB_DB.BRONZE_ANALYTICS.DIM_CUSTOMERS LIMIT 5; -- Esquema actualizado
        ```

---

### Parte 8: Limpieza

**Objetivo:** Destruir recursos Terraform y limpiar Snowflake/dbt Cloud. **¡MUY IMPORTANTE!**

1.  **Destruir Recursos Terraform:**
    *   En Terraform Cloud -> Workspace `dbt-snowflake-lab` -> Settings -> Destruction and Deletion.
    *   "Queue destroy plan" -> Revisa (debe eliminar bucket, rol/política IAM, integración, stage, schema `bronze`, DB `LAB_DB`).
    *   Confirma con el nombre del workspace -> "Confirm & Apply".
2.  **Verificar Limpieza:**
    *   Consola AWS: Bucket, Rol, Política eliminados.
    *   Snowflake UI: DB `LAB_DB`, Schema `bronze`, Stage `S3_CUSTOMER_STAGE`, Integración `S3_INTEGRATION` eliminados. **OJO:** Los esquemas `BRONZE_RAW_STAGING`, `BRONZE_ANALYTICS` y la tabla externa `customers_external` (creados por dbt) *no* serán eliminados por Terraform.
3.  **Limpieza Manual Snowflake (Completa):**
    ```sql
    USE ROLE ACCOUNTADMIN;
    DROP DATABASE IF EXISTS LAB_DB; -- Esto elimina LAB_DB y TODOS sus schemas/tablas/vistas
    DROP WAREHOUSE IF EXISTS DBT_LAB_WH;
    DROP USER IF EXISTS DBT_USER;
    DROP ROLE IF EXISTS TRANSFORMER;
    DROP ROLE IF EXISTS TERRAFORM_ROLE;
    DROP USER IF EXISTS TERRAFORM_USER;
    DROP INTEGRATION IF EXISTS S3_INTEGRATION; -- Por si acaso no se eliminó
    ```
4.  **Eliminar Proyecto dbt Cloud / Workspace TFC / Repo Git (Opcional).**

---

### (Opcional) Parte 9: Esquema Alternativo con Databricks

**Objetivo:** Adaptar el laboratorio para usar Databricks en lugar de Snowflake.

1.  **Prerrequisitos:**
    *   Cuenta Databricks (Prueba Gratuita disponible). Crea un workspace en AWS.
    *   Configuración de Databricks CLI y/o el Provider Terraform de Databricks.
2.  **Cambios Terraform:**
    *   Añade el provider `databricks/databricks`.
    *   Configura el provider Databricks (host, token - almacena de forma segura en variables TFC).
    *   Elimina los recursos Snowflake (`snowflake_*`).
    *   En lugar de Integración/Stage Snowflake, crea:
        *   `databricks_storage_credential` usando el mismo ARN de Rol IAM de AWS (`aws_iam_role.snowflake_access_role.arn` - quizás renombra el rol).
        *   `databricks_external_location` usando la credencial de almacenamiento y la URL del bucket S3.
    *   Crea un `databricks_schema` (equivalente al esquema Snowflake) dentro de un catálogo (ej., `main` o un nuevo `lab_catalog`).
    *   Crea un `databricks_sql_endpoint` (Serverless recomendado por coste/simplicidad, elige el tamaño más pequeño, auto-stop corto).
3.  **Carga de Datos (S3):** Permanece igual.
4.  **Cambios dbt Cloud:**
    *   Crea un *nuevo* proyecto dbt Cloud (o modifica existente, pero proyecto separado es más limpio).
    *   Selecciona "Databricks" como el tipo de warehouse.
    *   Configura conexión Databricks: Server Hostname, HTTP Path (del SQL Endpoint), Token (usa un Token de Acceso Personal de Databricks o secreto de Service Principal - almacena de forma segura).
    *   Target Database/Catalog: `main` o `lab_catalog`.
    *   Target Schema: `dbt_<tunombre>` o similar.
5.  **Cambios Código dbt:**
    *   **`sources.yml`:** Define el source apuntando a la external location de Databricks. Típicamente definirías una *tabla externa* en Databricks primero (usando Terraform o Databricks SQL) y luego referenciarías esa tabla en los sources de dbt, en lugar de referenciar directamente la location como con los stages de Snowflake.
        ```sql
        -- Ejemplo SQL Databricks para crear tabla externa (ejecutar vía Terraform o manualmente)
        CREATE TABLE IF NOT EXISTS main.bronze.customers_external (
          customer_id INT,
          first_name STRING,
          last_name STRING,
          join_date DATE
        )
        USING CSV -- o PARQUET, DELTA etc.
        OPTIONS (
          path = "s3://<tu-nombre-bucket>/", -- Necesita external location configurada
          header = "true",
          inferSchema = "true" -- O define esquema explícitamente
        );
        ```
        ```yaml
        # models/staging/sources.yml (dbt)
        sources:
          - name: bronze_customer_data_dbx
            database: main # O tu catálogo lab
            schema: bronze   # Esquema que contiene la tabla externa
            tables:
              - name: customers_external # La tabla externa creada arriba
        ```
    *   **`stg_customers.sql`:** Cambia la cláusula `from` a `{{ source('bronze_customer_data_dbx', 'customers_external') }}`. La sintaxis de casting podría ser ligeramente diferente si es necesaria (ej., `cast(col as int)`).
    *   **`dbt_project.yml`:** Actualiza nombre del proyecto. Asegura que las materializaciones sean apropiadas (tablas Delta son predeterminadas/recomendadas en Databricks, así que `+materialized: table` podría significar implícitamente tabla Delta).
    *   Tests (`schema.yml`) deberían permanecer mayormente iguales.
6.  **Ejecutar y Verificar:** Usa `dbt run`, `dbt test`. Verifica resultados usando el Editor SQL de Databricks.
7.  **Limpieza:** `terraform destroy`. Elimina manualmente SQL Endpoint de Databricks, clusters, usuarios/tokens si es necesario.

---
