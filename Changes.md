Cambios para eliminar el uso del bucket de S3 y usar un stage interno en snowflake

1.  **Eliminación de Recursos AWS en Terraform:**
    *   Quitar completamente la definición del bucket S3 (`aws_s3_bucket`).
    *   Quitar todos los recursos relacionados con IAM (`aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`). Ya no necesitas un rol IAM para que Snowflake acceda a S3 porque los datos estarán *dentro* de Snowflake.
    *   Quitar la definición del proveedor AWS si no se usan otros recursos de AWS en el mismo estado de Terraform (aunque en tu lab original solo usábamos S3).
2.  **Eliminación de Credenciales AWS:**
    *   Quitar las variables de entorno de AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) de Terraform Cloud.
    *   Quitar la variable Terraform `aws_region`.
3.  **Modificación del Stage en Terraform:**
    *   El recurso `snowflake_stage` se modifica para definir un stage *interno*. Esto significa:
        *   Ya **no** necesita el argumento `url`.
        *   Ya **no** necesita el argumento `storage_integration`.
        *   Solo requiere `name`, `database`, y `schema`.
        *   Ejemplo (simplificado):
            ```terraform
            resource "snowflake_stage" "internal_customer_stage" {
              name     = upper(var.snowflake_stage_name) # Usarás el mismo nombre de variable, ej: S3_CUSTOMER_STAGE (quizás renombrarla?)
              database = snowflake_database.lab_db.name
              schema   = snowflake_schema.bronze_schema.name # O el schema donde quieras el stage interno
              comment  = "Internal stage for customer data"
              # Sin url, sin storage_integration
            }
            ```
4.  **Carga de Datos Manual (Reemplazo de AWS CLI):**
    *   Ya no usarás `aws s3 cp`.
    *   La carga se realizará usando el comando `PUT` de Snowflake (desde SnowSQL o la CLI de Snowflake) o a través de la interfaz de usuario de Snowsight (opción "Cargar datos" en tablas o stages).
    *   Ejemplo con SnowSQL/CLI:
        ```bash
        PUT file:///ruta/a/tu/customers.csv @LAB_DB.bronze.S3_CUSTOMER_STAGE AUTO_COMPRESS=FALSE;
        ```
        (Asegúrate de usar el nombre de stage y la ruta correctos).
5.  **Permisos en Snowflake para el Stage Interno:**
    *   El rol `TRANSFORMER` (usado por dbt) necesitará permisos específicos sobre el stage *interno*.
    *   En lugar de `GRANT USAGE ON STAGE...`, necesitará `GRANT READ ON STAGE LAB_DB.bronze.S3_CUSTOMER_STAGE TO ROLE TRANSFORMER;` para poder leer archivos de él.
    *   Si quisieras que dbt o algún otro proceso cargara datos al stage, necesitaría `GRANT WRITE ON STAGE...`.
6.  **Configuración del Source en dbt (`sources.yml`):**
    *   La definición de la fuente cambiará. Ya **no** necesitarás el bloque `external:`.
    *   Simplemente referenciarás el stage interno por su nombre (a menudo usando `type: snowpipe` como convención, aunque no uses Snowpipe real).
    *   Ejemplo:
        ```yaml
        version: 2
        sources:
          - name: raw_customer_data
            database: LAB_DB
            schema: bronze # Schema donde resides el stage interno
            # Ya NO hay bloque 'external:'

            tables:
              - name: S3_CUSTOMER_STAGE # Nombre del stage interno
                description: "Internal stage for customer CSV files"
                # No necesitas 'external:' ni 'location:' aquí
                # Puedes usar 'pattern:' si quieres leer solo ciertos archivos
                # pattern: '.*customers.csv'
                # Puedes definir 'file_format' si no está definido en el stage
                # file_format: "(TYPE = CSV ...)"
                # Puedes definir columnas (para documentación/linaje)
                # columns: [...]
        ```
    *   **Nota:** Al consultar un stage interno con `SELECT FROM @stage/...`, Snowflake a menudo presenta cada fila como un `VARIANT` en una columna por defecto. Por lo tanto, la lógica en `stg_customers.sql` para extraer datos del `VARIANT` (`value:c1::NUMBER`, etc.) es probable que **siga siendo necesaria**.
7.  **Eliminación del Paquete `dbt-external-tables`:**
    *   Este paquete está diseñado principalmente para interactuar con stages externos y crear/gestionar tablas externas. Para stages *internos*, es probable que ya no sea necesario.
    *   Elimina la entrada del paquete de `packages.yml`.
    *   Ejecuta `dbt deps` para eliminarlo del proyecto.
    *   Quita la ejecución de `dbt run-operation stage_external_sources` de la secuencia de ejecución.
8.  **Secuencia de Ejecución dbt:**
    *   La secuencia se simplifica a: `dbt deps` (si tienes otros paquetes) -> Carga Manual de Datos (Paso 4) -> `dbt run` -> `dbt test`.

En resumen, eliminas toda la complejidad relacionada con AWS IAM y Storage Integration en Terraform, cambias la definición del stage a interno, cambias la forma de cargar datos a manual con herramientas Snowflake, ajustas los permisos de Snowflake sobre el stage interno y simplificas la definición del source en dbt, eliminando la necesidad de `dbt-external-tables` y la operación `run-operation`.
