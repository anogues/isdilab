## Laboratorio Guiado: Construyendo una Arquitectura de Datos Simple con Terraform, AWS, Snowflake y dbt Cloud

**Objetivo:** Construir un pipeline de datos que use Terraform para aprovisionar infraestructura en la nube (bucket S3, Stage de Snowflake), cargue datos de muestra y use dbt Cloud para transformar estos datos dentro de Snowflake.

**Presupuesto:** < $10 (Objetivo cercano a $0 con niveles gratuitos y limpieza rápida)

**Tecnologías Principales:**
*   AWS (S3) - Elegible para el Nivel Gratuito de almacenamiento
*   Snowflake - Prueba Gratuita (30 días, $400 en créditos)
*   Terraform Cloud - Nivel Gratuito
*   dbt Cloud - Plan Developer (Gratuito, 1 puesto)
*   Proveedor Git (GitHub, GitLab, etc.) - Nivel Gratuito

---

### Prerrequisitos

Antes de comenzar el laboratorio, los estudiantes **DEBEN**:

1.  **Crear una Cuenta de AWS:** [aws.amazon.com](https://aws.amazon.com/). Necesitarás la capacidad de crear usuarios/roles IAM y buckets S3.
2.  **Crear una Cuenta de Snowflake:** [signup.snowflake.com](https://signup.snowflake.com/). Elige la edición Standard en AWS en una región conveniente para ti (ej., `us-east-1`). Anota tu **URL de Cuenta** (ej., `tuorg-tucuenta.snowflakecomputing.com`).
3.  **Crear una Cuenta de Terraform Cloud:** [app.terraform.io/signup](https://app.terraform.io/signup). Crea una organización.
4.  **Crear una Cuenta de dbt Cloud:** [cloud.getdbt.com/signup](https://cloud.getdbt.com/signup/). Elige el plan Developer (Gratuito).
5.  **Crear un Repositorio Git:** En GitHub, GitLab, Bitbucket o Azure DevOps. Alojará tu código Terraform y dbt. Inicialízalo con un `README.md`. (Podéis usar https://github.com/anogues/isdilab)
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

**Objetivo:** Configurar Terraform Cloud con credenciales de AWS para gestionar recursos de AWS.

1.  **Crear Usuario IAM de AWS para Terraform:**
    *   Ve a la Consola IAM de AWS -> Usuarios -> Añadir usuarios.
    *   Nombre de usuario: `terraform-lab-user`.
    *   Selecciona **Clave de acceso - Acceso programático**.
    *   Adjuntar políticas directamente: Busca y selecciona `AmazonS3FullAccess` e `IAMReadOnlyAccess` (Necesario más tarde para el rol de integración de Snowflake). **Nota:** ¡En producción, usa políticas más restrictivas!
    *   Añade etiquetas (opcional).
    *   Revisa y crea el usuario.
    *   **CRÍTICO:** Descarga o copia el **ID de clave de acceso** y la **Clave de acceso secreta**. No volverás a ver la clave secreta.
2.  **Clonar Tu Repositorio Git:**
    ```bash
    git clone <tu-url-repo-git>
    cd <nombre-tu-repo>
    ```
3.  **Crear Workspace en Terraform Cloud:**
    *   Ve a tu organización de Terraform Cloud.
    *   Haz clic en "New workspace".
    *   Elige "Version control workflow".
    *   Conéctate a tu proveedor Git (ej., GitHub) y autoriza a Terraform Cloud.
    *   Selecciona el repositorio que acabas de clonar.
    *   Nombre del Workspace: `dbt-snowflake-lab`.
    *   Bajo "Advanced options", asegúrate de que "Terraform Working Directory" esté en blanco por ahora.
    *   Haz clic en "Create workspace".
4.  **Configurar Variables de Terraform Cloud:**
    *   En tu workspace `dbt-snowflake-lab`, ve a la pestaña "Variables".
    *   Añade las siguientes **Environment Variables** (Variables de Entorno), marcándolas como **Sensitive** (Sensibles):
        *   `AWS_ACCESS_KEY_ID`: Pega el ID de Clave de Acceso del Paso 1.
        *   `AWS_SECRET_ACCESS_KEY`: Pega la Clave de Acceso Secreta del Paso 1.
    *   Añade la siguiente **Terraform Variable**:
        *   `aws_region`: Introduce el código de región de AWS que planeas usar (ej., `us-east-1`). Asegúrate de que coincida con tu región de Snowflake si es posible.

---

### Parte 2: Configuración de Snowflake y Conexión con Terraform

**Objetivo:** Configurar Terraform Cloud con credenciales de Snowflake.

1.  **Crear Usuario y Rol de Snowflake para Terraform:**
    *   Inicia sesión en la interfaz de usuario (UI) de tu cuenta de Snowflake (Snowsight) usando un usuario con privilegios `ACCOUNTADMIN` (este es el usuario creado durante el registro).
    *   Abre una nueva Worksheet (Hoja de Trabajo).
    *   Ejecuta el siguiente SQL. **¡Elige una contraseña fuerte!**
        ```sql
        -- Usar el rol ACCOUNTADMIN para la configuración (o SYSADMIN + los grants necesarios)
        USE ROLE ACCOUNTADMIN;

        -- Crear un rol para Terraform
        CREATE ROLE IF NOT EXISTS TERRAFORM_ROLE;
        GRANT ROLE TERRAFORM_ROLE TO ROLE SYSADMIN; -- Permitir a SYSADMIN gestionar objetos creados

        -- Otorgar privilegios al rol de Terraform (ajustar según sea necesario para mínimo privilegio)
        -- Necesita capacidad para crear bases de datos, esquemas, warehouses, integraciones, stages
        GRANT CREATE DATABASE ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE TERRAFORM_ROLE;
        -- Otorgar el rol al usuario que ejecutará Terraform
        GRANT ROLE TERRAFORM_ROLE TO USER <tu_usuario_admin_snowflake>; -- Otórgalo a ti mismo inicialmente si es más fácil

        -- (Recomendado) Crear un usuario dedicado para Terraform
        CREATE USER IF NOT EXISTS TERRAFORM_USER
          PASSWORD='<tu-contraseña-fuerte-aqui>' -- !! CAMBIA ESTO !!
          LOGIN_NAME='TERRAFORM_USER'
          DISPLAY_NAME='TERRAFORM_USER'
          DEFAULT_WAREHOUSE='COMPUTE_WH' -- Usa el predeterminado o crea uno después
          DEFAULT_ROLE='TERRAFORM_ROLE'
          MUST_CHANGE_PASSWORD=FALSE;

        GRANT ROLE TERRAFORM_ROLE TO USER TERRAFORM_USER;

        -- Otorgar privilegios sobre la base de datos/esquema específicos si existen
        -- Los crearemos vía Terraform, así que otorgamos privilegios globales por simplicidad en el lab
        -- En producción: Otorgar privilegios específicos sobre objetos DESPUÉS de la creación.

        -- Mostrar detalles del usuario (opcional)
        -- DESC USER TERRAFORM_USER;
        ```
    *   **Nota Importante:** Usar `ACCOUNTADMIN` directamente en Terraform es posible pero desaconsejado. Lo anterior crea un `TERRAFORM_ROLE` y `TERRAFORM_USER` para una mejor práctica, aunque otorgamos permisos amplios para la simplicidad del laboratorio.
2.  **Configurar Más Variables de Terraform Cloud:**
    *   Vuelve a tu workspace `dbt-snowflake-lab` en Terraform Cloud -> Variables.
    *   Añade las siguientes **Environment Variables**, marcándolas como **Sensitive**:
        *   `SNOWFLAKE_USER`: `TERRAFORM_USER` (o el usuario que decidiste usar).
        *   `SNOWFLAKE_PASSWORD`: La contraseña que estableciste para `TERRAFORM_USER`.
        *   `SNOWFLAKE_ACCOUNT`: Tu identificador de cuenta de Snowflake (ej., `tuorg-tucuenta`). Encuéntralo abajo a la izquierda en la web de snowflake pinchando sobre tu usuario.
        *   `SNOWFLAKE_ROLE`: `TERRAFORM_ROLE` (o el rol que asignaste).
    *   Añade la siguiente **Terraform Variable**:
        *   `snowflake_region`: La región de tu cuenta de Snowflake (ej., `AWS_EU_WEST_1`). Encuéntralaejecutando SHOW ACCOUNTS en Snwoflake. Puede diferir ligeramente del nombre de la región de AWS (ej., guiones bajos vs guiones).

---

### Parte 3: Despliegue de Infraestructura (Terraform)

**Objetivo:** Definir y desplegar el bucket S3 de AWS, la Integración de Almacenamiento de Snowflake y el Stage Externo usando Terraform.

1.  **Crear Archivos de Código Terraform:**
    *   En tu repositorio Git local, crea los siguientes archivos:

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
              version = "~> 0.79" # Verifica la última versión
            }
          }
          cloud {
            organization = "<Tu-Nombre-Org-TFC>" # Reemplaza con el nombre de tu org de TFC

            workspaces {
              name = "dbt-snowflake-lab"
            }
          }
        }

        provider "aws" {
          region = var.aws_region
        }

        provider "snowflake" {
          # Credenciales obtenidas de variables de entorno (SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, etc.)
          # La región se especifica vía variable por claridad si se necesita en otro lugar
          # role = var.snowflake_role # A menudo también se establece vía variable de entorno
        }
        ```
        *   **Acción:** Reemplaza `<Tu-Nombre-Org-TFC>` con el nombre real de tu organización de Terraform Cloud.

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
          default     = ""
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

    *   `terraform/main.tf`:
        ```terraform
        # --- Recursos AWS ---

        resource "random_string" "bucket_suffix" {
          length  = 8
          special = false
          upper   = false
        }

        resource "aws_s3_bucket" "data_bucket" {
          bucket = "${var.bucket_prefix}-${random_string.bucket_suffix.result}"
          # ACL obsoleto, usar políticas de bucket si se necesita acceso específico más allá de la integración de Snowflake

          tags = {
            Name        = "dbt-lab-bucket"
            Environment = "Lab"
            ManagedBy   = "Terraform"
          }
        }

        # Rol IAM para la Integración de Snowflake
        data "aws_caller_identity" "current" {}

        resource "aws_iam_role" "snowflake_access_role" {
          name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"

          assume_role_policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Principal = {
                  # Este ARN será completado por Snowflake después de crear la integración.
                  # Usamos un valor temporal o el ARN de la cuenta para el plan inicial.
                  # El data source `snowflake_system_get_aws_s3_integration_iam_user_arn` lo obtendrá después.
                  AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" # Placeholder inicial
                }
                Action = "sts:AssumeRole"
                Condition = {
                   StringEquals = {
                      # Este External ID será completado por Snowflake después.
                      # Usamos un placeholder temporal. El data source `snowflake_storage_integration` lo proporcionará.
                      "sts:ExternalId" = "PLACEHOLDER_EXTERNAL_ID" # Placeholder inicial
                   }
                }
              }
            ]
          })

          tags = {
            Name        = "snowflake-lab-access-role"
            Environment = "Lab"
            ManagedBy   = "Terraform"
          }
          # Ignoramos cambios en assume_role_policy porque lo actualizaremos explícitamente
          lifecycle {
             ignore_changes = [assume_role_policy]
           }
        }

        resource "aws_iam_policy" "snowflake_access_policy" {
          name        = "snowflake-lab-s3-policy-${random_string.bucket_suffix.result}"
          description = "Política que otorga acceso a Snowflake al bucket S3 específico"

          policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect   = "Allow"
                Action   = [
                  "s3:GetObject",
                  "s3:GetObjectVersion"
                  ]
                Resource = "${aws_s3_bucket.data_bucket.arn}/*" # Acceso a archivos dentro del bucket
              },
              {
                Effect   = "Allow"
                Action   = "s3:ListBucket"
                Resource = aws_s3_bucket.data_bucket.arn # Acceso al listado del bucket
                Condition = {
                    StringLike = {
                        "s3:prefix": ["*"] # Permite listar cualquier prefijo si es necesario, se puede restringir más
                    }
                }
              }
            ]
          })
        }

        resource "aws_iam_role_policy_attachment" "snowflake_access_attach" {
          role       = aws_iam_role.snowflake_access_role.name
          policy_arn = aws_iam_policy.snowflake_access_policy.arn
        }

        # --- Recursos Snowflake ---

        resource "snowflake_database" "lab_db" {
          name = upper(var.snowflake_db_name)
          comment = "Base de datos para el lab dbt, gestionada por Terraform"
        }

        resource "snowflake_schema" "bronze_schema" {
          database = snowflake_database.lab_db.name
          name     = upper(var.snowflake_schema_name)
          comment  = "Esquema de datos crudos para el lab dbt, gestionado por Terraform"
        }

        resource "snowflake_storage_integration" "s3_integration" {
          name = upper(var.snowflake_integration_name)
          type = "EXTERNAL_STAGE" # Indica que es para stages S3
          storage_provider = "S3"
          enabled = true
          storage_aws_role_arn = aws_iam_role.snowflake_access_role.arn
          storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"] # Restringir a nuestro bucket
          comment = "Integración S3 para el lab dbt"
        }

        # Actualizar la política de confianza del rol IAM DESPUÉS de que la integración Snowflake se haya creado
        # Esto requiere que la integración exista primero para obtener los valores correctos.
        # Ejecutar `terraform apply` dos veces podría ser necesario.

        # Obtenemos el usuario IAM y el ID externo DESPUÉS de crear la integración
        data "snowflake_storage_integration" "s3_integration_data" {
          name = snowflake_storage_integration.s3_integration.name
          depends_on = [snowflake_storage_integration.s3_integration]
        }


        resource "aws_iam_role" "snowflake_access_role_update" {
          # Usa el *mismo* nombre para actualizar el rol existente
          name = aws_iam_role.snowflake_access_role.name

          # Define la política de confianza actualizada usando datos obtenidos de Snowflake
          assume_role_policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Principal = {
                  AWS = data.snowflake_storage_integration.s3_integration_data.storage_aws_iam_user_arn # Obtenido de Snowflake
                }
                Action = "sts:AssumeRole"
                Condition = {
                  StringEquals = {
                    # Usa el ID Externo proporcionado por Snowflake para esta integración
                    "sts:ExternalId" = data.snowflake_storage_integration.s3_integration_data.storage_aws_external_id # Obtenido de Snowflake
                  }
                }
              }
            ]
          })

          # Asegura que esta actualización ocurra solo después de que la integración sea creada
          depends_on = [snowflake_storage_integration.s3_integration]

          # Ignora cambios en otros atributos, solo actualiza la política
           lifecycle {
             ignore_changes = [tags, description, force_detach_policies, inline_policy, managed_policy_arns, max_session_duration, path, permissions_boundary, name]
           }
        }


        resource "snowflake_stage" "s3_stage" {
          name     = upper(var.snowflake_stage_name)
          database = snowflake_database.lab_db.name
          schema   = snowflake_schema.bronze_schema.name
          url      = "s3://${aws_s3_bucket.data_bucket.bucket}/" # Apunta a la raíz de la ruta del bucket
          storage_integration = snowflake_storage_integration.s3_integration.name
          comment  = "Stage externo apuntando al bucket S3 para datos de clientes"

          # Define el formato de archivo para CSV
          file_format = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE"
          # Para PARQUET: file_format = "TYPE = PARQUET"

          depends_on = [
             aws_iam_role.snowflake_access_role_update, # Asegura que la política del rol esté actualizada antes de que el stage use la integración
             snowflake_storage_integration.s3_integration
          ]
        }
        ```
        *   **Explicación:**
            *   Crea un bucket S3 con un sufijo aleatorio para unicidad.
            *   Crea un Rol IAM (`snowflake-lab-access-role`) que Snowflake asumirá. La política de confianza (`assume_role_policy`) inicialmente usa placeholders y se actualizará después.
            *   Crea una Política IAM que otorga acceso *solo* al bucket S3 creado.
            *   Adjunta la política al rol.
            *   Crea una Base de Datos Snowflake (`LAB_DB`) y un Esquema (`bronze`).
            *   Crea la Integración de Almacenamiento de Snowflake (`S3_INTEGRATION`), vinculándola al Rol IAM. **Crucialmente**, esto le dice a Snowflake *qué* ARN de rol de AWS debe poder asumir. Snowflake genera internamente un `STORAGE_AWS_IAM_USER_ARN` y un `STORAGE_AWS_EXTERNAL_ID` para esta integración.
            *   **Actualización Política IAM:** El recurso `aws_iam_role.snowflake_access_role_update` usa el data source `snowflake_storage_integration` para obtener el `STORAGE_AWS_IAM_USER_ARN` y `STORAGE_AWS_EXTERNAL_ID` *después* de que la integración es creada, y actualiza la política de confianza del rol IAM. Esto es un paso de seguridad requerido. **A menudo requiere ejecutar `terraform apply` dos veces.**
            *   Crea el Stage Externo de Snowflake (`S3_CUSTOMER_STAGE`) dentro del esquema `LAB_DB.bronze`, referenciando la Integración de Almacenamiento y definiendo el formato de archivo CSV (incluyendo omitir la fila de cabecera).

    *   `terraform/outputs.tf`:
        ```terraform
        output "aws_s3_bucket_name" {
          description = "Nombre del bucket S3 creado"
          value       = aws_s3_bucket.data_bucket.bucket
        }

        output "aws_s3_bucket_arn" {
          description = "ARN del bucket S3 creado"
          value       = aws_s3_bucket.data_bucket.arn
        }

        output "snowflake_database_name" {
          description = "Nombre de la base de datos Snowflake creada"
          value       = snowflake_database.lab_db.name
        }

        output "snowflake_schema_name" {
          description = "Nombre del esquema Snowflake creado"
          value       = snowflake_schema.bronze_schema.name
        }

        output "snowflake_stage_name" {
          description = "Nombre completamente calificado del stage externo Snowflake creado"
          value       = "${snowflake_database.lab_db.name}.${snowflake_schema.bronze_schema.name}.${snowflake_stage.s3_stage.name}"
        }

        output "snowflake_iam_role_arn" {
          description = "ARN del rol IAM creado para el acceso S3 de Snowflake"
          value       = aws_iam_role.snowflake_access_role.arn
        }

        output "snowflake_integration_name" {
          description = "Nombre de la integración de almacenamiento Snowflake"
          value       = snowflake_storage_integration.s3_integration.name
        }

        # Muestra los valores necesarios para actualizar la política de confianza del rol IAM (para verificación)
        output "snowflake_integration_aws_iam_user_arn_output" {
          description = "ARN de usuario IAM de AWS de Snowflake para la política de confianza de la integración"
          value       = data.snowflake_storage_integration.s3_integration_data.storage_aws_iam_user_arn
          sensitive   = true # Contiene info de la cuenta
        }

        output "snowflake_integration_aws_external_id_output" {
           description = "ID Externo de AWS de Snowflake para la política de confianza de la integración"
           value       = data.snowflake_storage_integration.s3_integration_data.storage_aws_external_id
           sensitive   = true
        }
        ```

2.  **Confirmar (Commit) y Subir (Push) Código Terraform:**
    *   Crea un archivo `.gitignore` en la raíz de tu repositorio:
        ```
        # Archivos de estado de Terraform (deben ser gestionados por TFC)
        *.tfstate
        *.tfstate.*
        .terraform/
        terraform.tfvars

        # archivos sensibles
        *.pem
        *.key
        ```
    *   Prepara (stage), confirma (commit) y sube (push) el directorio `terraform` y `.gitignore`:
        ```bash
        git add terraform/ .gitignore
        git commit -m "Añadir config Terraform para AWS S3 y Snowflake Stage"
        git push origin main # o el nombre de tu rama predeterminada
        ```

3.  **Ejecutar Plan y Apply de Terraform en Terraform Cloud:**
    *   Ve a tu workspace `dbt-snowflake-lab` en Terraform Cloud. Debería detectar el nuevo commit.
    *   Haz clic en "Queue plan". Revisa la salida del plan cuidadosamente. Debería mostrar la creación de recursos AWS y Snowflake.
    *   Haz clic en "Confirm & Apply". Añade un comentario (ej., "Despliegue inicial") y haz clic en "Confirm Plan".
    *   **IMPORTANTE - Posible Problema Primer Apply:** El *primer* apply podría fallar o tener éxito solo parcialmente al intentar actualizar `aws_iam_role.snowflake_access_role_update`, porque el data source `snowflake_storage_integration` necesita que el recurso `snowflake_storage_integration.s3_integration` se haya creado primero para poder consultar sus atributos (`storage_aws_iam_user_arn`, `storage_aws_external_id`).
    *   **Si el primer Apply falla o advierte sobre la actualización del rol:** Simplemente lanza una *segunda* ejecución. Haz clic en "Queue plan" de nuevo, revisa (debería mostrar la modificación de `aws_iam_role`), y luego "Confirm & Apply". La segunda ejecución usa los valores poblados por Snowflake después de que la integración fue creada en la primera ejecución para actualizar correctamente la política de confianza del rol IAM.
    *   Una vez aplicado con éxito, revisa la pestaña "Outputs" en Terraform Cloud. Anota el `aws_s3_bucket_name`.

4.  **Verificar Recursos:**
    *   **Consola AWS:** Revisa S3 por el nuevo bucket. Revisa IAM por el nuevo rol y política. Verifica que la relación de confianza (trust relationship) del rol usa el ARN y el ID Externo mostrados en los outputs de Terraform.
    *   **UI de Snowflake:**
        ```sql
        USE ROLE SYSADMIN; -- O ACCOUNTADMIN
        SHOW DATABASES LIKE 'LAB_DB';
        USE DATABASE LAB_DB;
        SHOW SCHEMAS LIKE 'bronze';
        USE SCHEMA bronze;
        SHOW STAGES LIKE 'S3_CUSTOMER_STAGE';
        DESC INTEGRATION S3_INTEGRATION; -- Revisa detalles, especialmente STORAGE_AWS_IAM_USER_ARN y STORAGE_AWS_EXTERNAL_ID
        ```

---

### Parte 4: Carga de Datos

**Objetivo:** Subir el archivo de muestra `customers.csv` al bucket S3.

1.  **Obtener Datos de Muestra:** Asegúrate de tener el archivo `customers.csv` creado anteriormente en tu máquina local.
2.  **Subir a S3:**
    *   **Opción A (AWS CLI):**
        *   Configura tu AWS CLI si aún no lo has hecho (`aws configure`). Usa las *mismas* credenciales que Terraform u otro usuario con permiso S3 PutObject para ese bucket.
        *   Ejecuta el comando, reemplazando `<tu-nombre-bucket>` con el nombre real del bucket de los outputs de Terraform:
            ```bash
            aws s3 cp customers.csv s3://<tu-nombre-bucket>/customers.csv
            ```
    *   **Opción B (Consola AWS):**
        *   Ve a la consola S3, navega a tu bucket (`dbt-lab-data-...`).
        *   Haz clic en "Upload" (Subir).
        *   Añade el archivo `customers.csv`.
        *   Haz clic en "Upload".
3.  **Verificar en Snowflake (Opcional pero Recomendado):**
    *   En la hoja de trabajo de la UI de Snowflake:
        ```sql
        USE DATABASE LAB_DB;
        USE SCHEMA bronze;

        -- Listar archivos en la ruta del stage
        LS @S3_CUSTOMER_STAGE;
        -- Deberías ver customers.csv listado

        -- Intentar seleccionar directamente desde el stage (confirma formato y acceso)
        SELECT $1, $2, $3, $4 FROM @S3_CUSTOMER_STAGE/customers.csv;
        -- Deberías ver los datos del archivo CSV (excluyendo la cabecera).
        ```

---

### Parte 5: Configuración de dbt Cloud

**Objetivo:** Conectar dbt Cloud a tu repositorio Git y cuenta de Snowflake.

1.  **Crear Proyecto dbt Cloud:**
    *   Inicia sesión en dbt Cloud.
    *   Haz clic en "Account Settings" (icono de engranaje) -> "Projects" -> "+ New Project".
    *   Nombre: `Snowflake Lab Project`.
    *   Selecciona "Snowflake" como el warehouse. Haz clic en "Next".
    *   Configura la Conexión Snowflake:
        *   Account: Tu identificador de cuenta Snowflake (ej., `tuorg-tucuenta`).
        *   Role: `TRANSFORMER` (Crearemos este rol para dbt).
        *   Database: `LAB_DB` (La creada por Terraform).
        *   Warehouse: `COMPUTE_WH` (O crea uno nuevo pequeño, ej., `DBT_LAB_WH`).
        *   Authentication Method: "Password".
        *   User: `DBT_USER` (Crearemos este usuario).
        *   Password: Establece una contraseña fuerte para `DBT_USER`.
    *   Haz clic en "Test Connection". Esto **fallará** porque el usuario/rol/warehouse aún no existen. Está bien por ahora. Haz clic en "Next".
2.  **Configurar Conexión del Repositorio:**
    *   Elige tu proveedor Git (ej., GitHub).
    *   Autoriza el acceso a dbt Cloud.
    *   Selecciona el *mismo* repositorio que usaste para Terraform.
    *   Elige "Configure Git Clone" o similar. Usualmente, seleccionas la rama principal.
3.  **Crear Usuario, Rol y Warehouse de dbt en Snowflake:**
    *   Vuelve a tu hoja de trabajo en la UI de Snowflake (usando `ACCOUNTADMIN` o `SYSADMIN`).
    *   Ejecuta el siguiente SQL:
        ```sql
        USE ROLE ACCOUNTADMIN; -- O SYSADMIN con privilegio manage grants

        -- Crear un rol específico para transformaciones dbt
        CREATE ROLE IF NOT EXISTS TRANSFORMER;
        GRANT ROLE TRANSFORMER TO ROLE SYSADMIN; -- Para que SYSADMIN pueda ver objetos

        -- Crear un warehouse dedicado para ejecuciones dbt (X-Small, auto-suspender rápido)
        CREATE WAREHOUSE IF NOT EXISTS DBT_LAB_WH
          WAREHOUSE_SIZE = 'XSMALL'
          AUTO_SUSPEND = 60 -- Suspender después de 60 segundos (1 minuto) de inactividad
          AUTO_RESUME = TRUE
          INITIALLY_SUSPENDED = TRUE -- Empezar suspendido para ahorrar créditos
          COMMENT = 'Warehouse para ejecuciones del lab dbt Cloud';

        -- Otorgar privilegios al rol dbt
        GRANT USAGE ON WAREHOUSE DBT_LAB_WH TO ROLE TRANSFORMER;
        GRANT USAGE ON DATABASE LAB_DB TO ROLE TRANSFORMER;
        GRANT USAGE ON SCHEMA LAB_DB.bronze TO ROLE TRANSFORMER;
        GRANT SELECT ON FUTURE TABLES IN SCHEMA LAB_DB.bronze TO ROLE TRANSFORMER; -- Leer de tablas bronze
        GRANT SELECT ON FUTURE VIEWS IN SCHEMA LAB_DB.bronze TO ROLE TRANSFORMER;
        GRANT SELECT ON STAGE LAB_DB.bronze.S3_CUSTOMER_STAGE TO ROLE TRANSFORMER; -- Necesario para leer del stage

        -- Permitir a dbt crear sus propios esquemas (ej., para modelos de destino)
        GRANT CREATE SCHEMA ON DATABASE LAB_DB TO ROLE TRANSFORMER;

        -- Crear el usuario dedicado para dbt Cloud
        CREATE USER IF NOT EXISTS DBT_USER
          PASSWORD = '<contraseña-usuario-dbt-aqui>' -- !! USA LA MISMA CONTRASEÑA QUE EN LA CONFIGURACIÓN DE dbt Cloud !!
          LOGIN_NAME = 'DBT_USER'
          DISPLAY_NAME = 'DBT_USER'
          DEFAULT_WAREHOUSE = 'DBT_LAB_WH'
          DEFAULT_ROLE = 'TRANSFORMER'
          MUST_CHANGE_PASSWORD = FALSE;

        -- Asignar el rol al usuario
        GRANT ROLE TRANSFORMER TO USER DBT_USER;

        -- Otorgar permisos sobre esquemas que dbt creará
        -- Nota: dbt típicamente crea esquemas como 'dbt_nombreusuario' o basado en config de target
        -- Necesitamos otorgar privilegios sobre la base de datos para que el rol pueda crear esquemas,
        -- y luego otorgar privilegios dentro de esos esquemas DESPUÉS de que dbt los cree, o usar future grants.

        -- Otorguemos permisos sobre la base de datos LAB_DB permitiendo al rol gestionar objetos dentro de esquemas que cree
        GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER;
        GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE LAB_DB TO ROLE TRANSFORMER;
        -- Opcionalmente, otorgar propiedad sobre objetos futuros para permitir drop/alter
        -- GRANT OWNERSHIP ON FUTURE TABLES IN SCHEMA <esquema_destino> TO ROLE TRANSFORMER; -- Necesita nombre de esquema primero

        -- Otorgar propiedad del esquema que dbt usará (asumiendo predeterminado 'dbt_<usuario>')
        -- Para encontrar el nombre de esquema que usa dbt: ejecuta dbt una vez, ve el error o revisa dir target.
        -- O, especifica el esquema de destino en dbt_project.yml. Asumamos predeterminado por ahora.
        -- Otorgamos CREATE SCHEMA arriba, dbt debería manejarlo.

        -- Verificar que el usuario existe
        -- DESC USER DBT_USER;
        ```
    *   **Acción:** Reemplaza `<contraseña-usuario-dbt-aqui>` con la **misma contraseña exacta** que introdujiste en la configuración de conexión de dbt Cloud.
4.  **Volver a Probar Conexión dbt Cloud:**
    *   Vuelve a dbt Cloud -> Account Settings -> Project -> Snowflake Lab Project.
    *   Haz clic en "Edit" en los detalles de la conexión.
    *   Introduce la contraseña del usuario dbt de nuevo.
    *   Haz clic en "Test Connection". ¡Ahora debería tener éxito!
    *   Haz clic en "Save".
5.  **Credenciales de Desarrollo (Develop Credentials):**
    *   En dbt Cloud, navega a "Develop" (arriba a la izquierda). Podría tardar un minuto en clonar tu repositorio.
    *   Podría pedirte configurar tus credenciales de nuevo para el entorno de desarrollo. Haz clic en "Credentials" o el icono de engranaje cerca de tu nombre.
    *   Rellena tus credenciales de desarrollo de Snowflake. **Crucialmente, para tu entorno de Desarrollo, usualmente querrás que dbt escriba en un esquema específico para ti,** como `DBT_TUSINICIALES`.
        *   Role: `TRANSFORMER`
        *   Warehouse: `DBT_LAB_WH`
        *   Database: `LAB_DB`
        *   Schema: `DBT_<tus_iniciales_o_usuario>` (ej., `DBT_JD`). dbt creará este esquema si no existe (gracias al grant `CREATE SCHEMA`).
    *   Haz clic en "Save".

---

### Parte 6: Transformación de Datos (dbt Cloud)

**Objetivo:** Crear modelos dbt para leer desde el stage de Snowflake, crear una tabla, una vista y añadir tests.

1.  **Inicializar Estructura de Proyecto dbt (si es necesario):**
    *   Si tu repositorio no tiene un archivo `dbt_project.yml`, dbt Cloud podría pedirte crear uno o empezar con archivos de ejemplo.
    *   En el IDE de dbt Cloud (pestaña Develop), asegúrate de tener un `dbt_project.yml` básico:
        ```yaml
        name: 'snowflake_lab_project'
        version: '1.0.0'
        config-version: 2

        profile: 'default' # Esto es gestionado por la configuración de conexión de dbt Cloud

        model-paths: ["models"]
        analysis-paths: ["analyses"]
        test-paths: ["tests"]
        seed-paths: ["seeds"]
        macro-paths: ["macros"]
        snapshot-paths: ["snapshots"]

        target-path: "target"  # directorio que almacenará archivos SQL compilados
        clean-targets:         # directorios a ser eliminados por `dbt clean`
          - "target"
          - "dbt_packages"

        # Definir config de modelos - especificar materialización y esquema destino
        models:
          snowflake_lab_project: # Nombre de tu proyecto
            +materialized: view # Materialización predeterminada a vista
            staging: # Nombre de carpeta
              +materialized: table # Modelos de stage serán tablas
              +schema: bronze_STAGING # Esquema destino para modelos staging
            marts: # Nombre de carpeta
              +schema: ANALYTICS # Esquema destino para modelos mart (usualmente vistas)

        # Definir configuración de source (Opcional pero buena práctica)
        # sources: ... # Añadiremos esto abajo
        ```
    *   **Acción:** Crea las carpetas `models/staging` y `models/marts` en el explorador de archivos del IDE.

2.  **Definir el Source (Fuente):**
    *   Crea un archivo `models/staging/sources.yml`:
        ```yaml
        version: 2

        sources:
          - name: bronze_customer_data # Un nombre arbitrario para el grupo de fuentes
            database: LAB_DB   # Nombre de la base de datos bronze
            schema: bronze      # Nombre del esquema bronze donde reside el stage
            loader: external # Indica que esto se carga externamente (vía Stage)

            # Definir las propiedades de la fuente externa
            # Ref: https://docs.getdbt.com/docs/building-a-dbt-project/using-sources#defining-an-external-table
            external:
              location: "@S3_CUSTOMER_STAGE" # Nombre del stage creado por Terraform
              file_format: "(TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE)"
              # Si usas Parquet: file_format: "(TYPE = PARQUET)"
              # auto_refresh: false # Predeterminado es false, poner true si es necesario

            tables:
              - name: customers_external # Nombre arbitrario para la 'tabla' que representa los archivos del stage
                description: "Tabla externa apuntando a archivos CSV de clientes en el stage S3."
                # Definir las columnas basadas en la estructura CSV ($1, $2, etc.)
                columns:
                  - name: customer_id
                    description: "Identificador único para el cliente"
                    data_type: NUMBER # Usa VARIANT inicialmente si no estás seguro, luego haz cast
                    quote: false # Importante para números desde CSV
                  - name: first_name
                    description: "Nombre del cliente"
                    data_type: VARCHAR
                  - name: last_name
                    description: "Apellido del cliente"
                    data_type: VARCHAR
                  - name: join_date
                    description: "Fecha en que el cliente se unió"
                    data_type: DATE # Usa VARCHAR inicialmente si hay problemas de formato fecha, luego haz cast
        ```

3.  **Crear Modelo Staging:**
    *   Crea un archivo `models/staging/stg_customers.sql`:
        ```sql
        -- models/staging/stg_customers.sql

        with source as (
            -- Referencia la tabla externa definida en sources.yml
            -- Seleccionando columnas específicas ($1, $2, etc.) representando posición en CSV
            select
                $1::number as customer_id, -- Casting explícito
                $2::varchar as first_name,
                $3::varchar as last_name,
                try_to_date($4::varchar, 'YYYY-MM-DD') as join_date -- Usa try_to_date por seguridad
            from {{ source('bronze_customer_data', 'customers_external') }}
        )

        select
            customer_id,
            first_name,
            last_name,
            join_date
        from source
        where customer_id is not null -- Filtro básico de calidad de datos
        ```
        *   **Explicación:** Este modelo lee directamente desde el stage externo definido como source. Selecciona las columnas posicionales (`$1`, `$2`, etc.) y las convierte explícitamente (cast) a los tipos de datos deseados. Usar `try_to_date` previene errores si el formato de fecha es inesperado. Este modelo se materializará como una *tabla* en el esquema `bronze_STAGING` (según se definió en `dbt_project.yml`).

4.  **Crear Vista Mart:**
    *   Crea un archivo `models/marts/dim_customers.sql`:
        ```sql
        -- models/marts/dim_customers.sql

        with customers as (
            select
                customer_id,
                first_name,
                last_name,
                join_date
            from {{ ref('stg_customers') }}
        )

        select
            customer_id,
            first_name,
            last_name,
            join_date,
            year(join_date) as join_year -- Ejemplo de transformación simple
        from customers
        ```
        *   **Explicación:** Este modelo selecciona desde la tabla `stg_customers` (usando `ref`). Añade una transformación simple (`join_year`). Este modelo se materializará como una *vista* en el esquema `ANALYTICS` (el predeterminado para `marts` en `dbt_project.yml`).

5.  **Añadir Tests de Datos:**
    *   Crea un archivo `models/staging/schema.yml` (o edítalo si existe):
        ```yaml
        version: 2

        models:
          - name: stg_customers
            description: "Tabla staging para datos de clientes cargados desde S3. Contiene una fila por cliente."
            columns:
              - name: customer_id
                description: "Identificador único para el cliente."
                tests:
                  - unique
                  - not_null
              - name: first_name
                description: "Nombre del cliente."
                tests:
                  - not_null
              - name: last_name
                description: "Apellido del cliente."
              - name: join_date
                description: "Fecha en que el cliente se unió."
                tests:
                  - not_null
        ```
    *   Crea un archivo `models/marts/schema.yml` (o edítalo si existe):
        ```yaml
        version: 2

        models:
          - name: dim_customers
            description: "Vista de dimensión de cliente, proveyendo atributos de cliente limpios."
            columns:
              - name: customer_id
                description: "Identificador único para el cliente."
                tests:
                  - unique # Testear unicidad de nuevo en la vista final
                  - not_null
                  - relationships: # Ejemplo chequeo integridad referencial (si tuvieras pedidos)
                      to: ref('stg_customers') # Chequea si customer_id existe en staging
                      field: customer_id
        ```
        *   **Explicación:** Estos archivos definen tests (como `unique`, `not_null`, `relationships`) que dbt puede ejecutar contra tus modelos para asegurar la calidad de los datos.

6.  **Confirmar (Commit) y Subir (Push) Código dbt:**
    *   En la terminal del IDE de dbt Cloud o usando la UI de integración Git:
        *   Prepara (stage) todos los cambios (`git add .` o usa UI).
        *   Confirma (commit) los cambios (`git commit -m "Añadir modelos y tests dbt para clientes"` o usa UI).
        *   Sube (push) los cambios (`git push` o usa UI).

---

### Parte 7: Ejecutar y Verificar

**Objetivo:** Ejecutar el pipeline dbt y revisar los resultados en Snowflake.

1.  **Ejecutar Comandos dbt (IDE dbt Cloud):**
    *   En la barra de comandos del IDE de dbt Cloud en la parte inferior:
    *   Ejecuta los modelos:
        ```bash
        dbt run
        ```
    *   Revisa la salida. Debería mostrar:
        *   Creando el esquema `bronze_STAGING` (si no existe).
        *   Creando la tabla `stg_customers` en `LAB_DB.bronze_STAGING`.
        *   Creando el esquema `ANALYTICS` (si no existe).
        *   Creando la vista `dim_customers` en `LAB_DB.ANALYTICS`.
    *   Ejecuta los tests:
        ```bash
        dbt test
        ```
    *   Revisa la salida. Todos los tests deberían pasar (`PASS`). Si alguno falla (`FAIL`), investiga la razón (ej., `customer_id` duplicado, valores nulos).

2.  **Verificar en Snowflake:**
    *   Vuelve a tu hoja de trabajo en la UI de Snowflake.
    *   **Importante:** Asegúrate de estar usando un rol que tenga permisos sobre los nuevos esquemas y objetos (ej., `TRANSFORMER`, `SYSADMIN`, o `ACCOUNTADMIN`). El `DBT_USER` con el rol `TRANSFORMER` debería funcionar. Podrías necesitar otorgar usage sobre los esquemas recién creados a otros roles como `SYSADMIN` si quieres consultarlos con ellos:
        ```sql
        -- Ejecutar como ACCOUNTADMIN o rol propietario de los esquemas (TRANSFORMER)
        GRANT USAGE ON SCHEMA LAB_DB.bronze_STAGING TO ROLE SYSADMIN;
        GRANT SELECT ON ALL TABLES IN SCHEMA LAB_DB.bronze_STAGING TO ROLE SYSADMIN;
        GRANT USAGE ON SCHEMA LAB_DB.ANALYTICS TO ROLE SYSADMIN;
        GRANT SELECT ON ALL VIEWS IN SCHEMA LAB_DB.ANALYTICS TO ROLE SYSADMIN;
        ```
    *   Ahora, consulta los objetos creados (usando `SYSADMIN` o `TRANSFORMER`):
        ```sql
        USE ROLE SYSADMIN; -- o TRANSFORMER
        USE WAREHOUSE DBT_LAB_WH; -- Usa el warehouse de dbt

        -- Revisa la tabla staging
        SELECT * FROM LAB_DB.bronze_STAGING.STG_CUSTOMERS;

        -- Revisa la vista de dimensión final
        SELECT * FROM LAB_DB.ANALYTICS.DIM_CUSTOMERS;
        ```
    *   Deberías ver los datos de cliente transformados tanto en la tabla como en la vista.

3.  **(Opcional) Explorar Características dbt Cloud:**
    *   Haz clic en "Docs" -> "Generate project documentation" en dbt Cloud. Explora la documentación generada y el gráfico de linaje.
    *   Mira la pestaña "Run History" para ver ejecuciones pasadas.

---

### Parte 8: Limpieza

**Objetivo:** Destruir todos los recursos cloud creados por Terraform para evitar costes. **ESTE ES EL PASO MÁS IMPORTANTE PARA EL CONTROL DE COSTES.**

1.  **Destruir Recursos vía Terraform Cloud:**
    *   Ve a tu workspace `dbt-snowflake-lab` en Terraform Cloud.
    *   Ve a "Settings" -> "Destruction and Deletion".
    *   Haz clic en "Queue destroy plan".
    *   Revisa el plan. Debería mostrar la destrucción del bucket S3, rol/política IAM, y el stage, esquema y base de datos de Snowflake.
    *   **Escribe el nombre del workspace** para confirmar.
    *   Haz clic en "Queue destroy plan".
    *   Una vez revisado el plan, haz clic en "Confirm & Apply" para ejecutar la destrucción.
2.  **Verificar Limpieza:**
    *   **Consola AWS:** Revisa que el bucket S3, rol IAM y política hayan desaparecido.
    *   **UI de Snowflake:** Revisa que la base de datos `LAB_DB`, el esquema `bronze`, el stage `S3_CUSTOMER_STAGE`, y la integración `S3_INTEGRATION` hayan desaparecido. El warehouse `DBT_LAB_WH`, el usuario `DBT_USER`, y el rol `TRANSFORMER` *permanecerán* ya que fueron creados manualmente, no por Terraform.
3.  **Limpieza Manual Snowflake (Opcional):**
    *   Si quieres limpiar Snowflake completamente, elimina los objetos creados manualmente:
        ```sql
        USE ROLE ACCOUNTADMIN;
        DROP WAREHOUSE IF EXISTS DBT_LAB_WH;
        DROP USER IF EXISTS DBT_USER;
        DROP ROLE IF EXISTS TRANSFORMER;
        DROP ROLE IF EXISTS TERRAFORM_ROLE; -- Si creaste este rol
        DROP USER IF EXISTS TERRAFORM_USER; -- Si creaste este usuario
        ```
4.  **Eliminar Proyecto dbt Cloud (Opcional):**
    *   Account Settings -> Projects -> Encuentra "Snowflake Lab Project" -> Settings -> Delete Project.
5.  **Eliminar Workspace Terraform Cloud (Opcional):**
    *   Workspace -> Settings -> Destruction and Deletion -> Delete Workspace.
6.  **Eliminar Repositorio Git (Opcional):**
    *   Elimina el repositorio desde tu proveedor Git.

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
