# --- Recursos AWS ---

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "${var.bucket_prefix}-${random_string.bucket_suffix.result}"
  tags = {
    Name        = "dbt-lab-bucket"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# --- Recursos Snowflake (Primero la Integración y la DB/Schema) ---
# Definimos estos PRIMERO para que el Rol IAM pueda referenciar los outputs de la integración.

resource "snowflake_database" "lab_db" {
  name = upper(var.snowflake_db_name)
  comment = "Base de datos para el lab dbt, gestionada por Terraform"
}

resource "snowflake_schema" "bronze_schema" {
  database = snowflake_database.lab_db.name
  name     = upper(var.snowflake_schema_name) # Usa el valor 'bronze' de variables.tf
  comment  = "Esquema de datos crudos (bronze) para el lab dbt, gestionado por Terraform"
}

# Crear la Integración de Almacenamiento ANTES del rol que la usa en su policy
# Nota: Todavía depende implícitamente de un ARN de rol al crearse, pero definiremos el rol después.
# ¡ESTO CREA UN CICLO DIRECTO! Snowflake necesita el ARN del rol al crear la integración.
# El rol necesita el ARN/ID externo de la integración para su política final.

# --- ABORDAJE DEL CICLO ---
# La única forma robusta en Terraform puro sin pasos manuales es usar el patrón de dos bloques que falló,
# o aceptar que uno de los recursos se crea con un valor temporal y se actualiza después.
# Volvamos al patrón de dos bloques, pero asegurémonos que el lifecycle ignore todo lo posible.

# Requerido para obtener el ID de Cuenta AWS para la política temporal
data "aws_caller_identity" "current" {}

# Rol IAM para Integración Snowflake - Paso 1: Creación Inicial (Como antes)
resource "aws_iam_role" "snowflake_access_role_initial" {
  name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
  tags = {
    Name        = "snowflake-lab-access-role"
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Política IAM (Como antes)
resource "aws_iam_policy" "snowflake_access_policy" {
  name        = "snowflake-lab-s3-policy-${random_string.bucket_suffix.result}"
  description = "Política que otorga acceso de Snowflake al bucket S3 específico"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject*", "s3:ListBucket"], Resource = ["${aws_s3_bucket.data_bucket.arn}/*", aws_s3_bucket.data_bucket.arn] }
      # Simplificado para brevedad, usa la versión completa si es necesario
    ]
  })
}

# Adjuntar Política (Como antes)
resource "aws_iam_role_policy_attachment" "snowflake_access_attach" {
  role       = aws_iam_role.snowflake_access_role_initial.name
  policy_arn = aws_iam_policy.snowflake_access_policy.arn
}

# Crear la Integración de Almacenamiento - Paso 2 (Como antes)
resource "snowflake_storage_integration" "s3_integration" {
  name = upper(var.snowflake_integration_name)
  type = "EXTERNAL_STAGE"
  storage_provider = "S3"
  enabled = true
  storage_aws_role_arn = aws_iam_role.snowflake_access_role_initial.arn # Depende del rol inicial
  storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"]
  comment = "Integración S3 para el lab dbt"
  depends_on = [aws_iam_role.snowflake_access_role_initial]
}

# ---- MODIFICACIÓN CLAVE: USAR `aws_iam_role_assume_role_policy` (si existe) o `aws_iam_role` con `ignore_changes` más agresivo ----

# Revisando la documentación de nuevo, NO existe un recurso separado `aws_iam_role_assume_role_policy`.
# La única opción sigue siendo el segundo bloque `aws_iam_role` para actualizar.
# Intentemos ser *extremadamente* explícitos con `ignore_changes`.

resource "aws_iam_role" "snowflake_access_role_policy_update" {
  # Mismo nombre que el inicial
  name = aws_iam_role.snowflake_access_role_initial.name

  # La política de confianza final y correcta
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { AWS = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn }
        Action    = "sts:AssumeRole"
        Condition = { StringEquals = { "sts:ExternalId" = snowflake_storage_integration.s3_integration.storage_aws_external_id } }
      }
    ]
  })

  # Dependencia explícita
  depends_on = [snowflake_storage_integration.s3_integration]

  # Ignorar TODO excepto la política de confianza.
  lifecycle {
    ignore_changes = [
      name, # Ignorar explícitamente el nombre
      tags,
      description,
      force_detach_policies,
      inline_policy,
      managed_policy_arns,
      max_session_duration,
      path,
      permissions_boundary,
      # role_last_used, <--- LÍNEA ELIMINADA
    ]
  }
}

# Crear el Stage Externo - Paso 4 (Como antes)
resource "snowflake_stage" "s3_stage" {
  name                = upper(var.snowflake_stage_name)
  database            = snowflake_database.lab_db.name
  schema              = snowflake_schema.bronze_schema.name
  url                 = "s3://${aws_s3_bucket.data_bucket.bucket}/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  comment             = "Stage externo apuntando al bucket S3 para datos de clientes"
  file_format         = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE"
  depends_on          = [ aws_iam_role.snowflake_access_role_policy_update ] # Depende de la actualización final
}
