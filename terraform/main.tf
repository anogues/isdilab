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

# Requerido para obtener el ID de Cuenta AWS para la política temporal
data "aws_caller_identity" "current" {}

# Rol IAM para Integración Snowflake - SOLO CREACIÓN INICIAL
# Se crea con una política temporal. Será actualizada manualmente después.
resource "aws_iam_role" "snowflake_access_role_initial" {
  name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" } # Política TEMPORAL
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

# Política IAM que otorga acceso S3
resource "aws_iam_policy" "snowflake_access_policy" {
  name        = "snowflake-lab-s3-policy-${random_string.bucket_suffix.result}"
  description = "Política que otorga acceso de Snowflake al bucket S3 específico"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Usar la versión completa de la política de acceso S3 aquí
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.data_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.data_bucket.arn
        Condition = { StringLike = { "s3:prefix": ["*"] } }
      }
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
  name = upper(var.snowflake_db_name)
  comment = "Base de datos para el lab dbt, gestionada por Terraform"
}

resource "snowflake_schema" "bronze_schema" {
  database = snowflake_database.lab_db.name
  name     = upper(var.snowflake_schema_name)
  comment  = "Esquema de datos crudos (bronze) para el lab dbt, gestionado por Terraform"
}

# Crear la Integración de Almacenamiento
# Referencia el rol con la política de confianza temporal.
resource "snowflake_storage_integration" "s3_integration" {
  name                 = upper(var.snowflake_integration_name)
  type                 = "EXTERNAL_STAGE"
  storage_provider     = "S3"
  enabled              = true
  storage_aws_role_arn = aws_iam_role.snowflake_access_role_initial.arn # ARN del rol temporal
  storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"]
  comment              = "Integración S3 para el lab dbt"
  depends_on           = [aws_iam_role.snowflake_access_role_initial] # Asegurar que el rol existe
}

# ELIMINADO: resource "aws_iam_role" "snowflake_access_role_policy_update" { ... }

# Crear el Stage Externo
# Depende de la integración. Puede que funcione inicialmente o no hasta que se arregle la política del rol.
resource "snowflake_stage" "s3_stage" {
  name                = upper(var.snowflake_stage_name)
  database            = snowflake_database.lab_db.name
  schema              = snowflake_schema.bronze_schema.name
  url                 = "s3://${aws_s3_bucket.data_bucket.bucket}/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  comment             = "Stage externo apuntando al bucket S3 para datos de clientes"
  file_format         = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE"
  depends_on          = [snowflake_storage_integration.s3_integration] # Solo depende de la integración
}
