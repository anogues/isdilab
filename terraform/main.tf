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

# Rol IAM para Integración Snowflake - Paso 1: Creación Inicial
# Definir con una política temporal (placeholder) que no crea el ciclo.
# Esto permite que el rol exista para que la integración pueda referenciar su ARN.
resource "aws_iam_role" "snowflake_access_role_initial" {
  # Usar una estrategia de nombre consistente que incluya el sufijo aleatorio
  name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"

  # Política temporal: Permite la creación del rol sin depender aún de la integración.
  # Usar el principal raíz de la cuenta es un placeholder común.
  # Esta política SERÁ SOBREESCRITA por el recurso _policy_update más tarde.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          # Placeholder Temporal - no crea ciclo de dependencia
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "snowflake-lab-access-role" # Mantener la etiqueta consistente si es necesario
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Política IAM que otorga acceso S3 (permanece igual)
resource "aws_iam_policy" "snowflake_access_policy" {
  name        = "snowflake-lab-s3-policy-${random_string.bucket_suffix.result}"
  description = "Política que otorga acceso de Snowflake al bucket S3 específico"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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

# Adjuntar la política de acceso S3 al rol (misma lógica)
resource "aws_iam_role_policy_attachment" "snowflake_access_attach" {
  # Adjuntar política al rol usando el nombre generado por el bloque _initial
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
  comment  = "Esquema de datos crudos para el lab dbt, gestionado por Terraform"
}

# Crear la Integración de Almacenamiento - Paso 2
# Esto depende de que el ARN del rol inicial esté disponible.
resource "snowflake_storage_integration" "s3_integration" {
  name = upper(var.snowflake_integration_name)
  type = "EXTERNAL_STAGE"
  storage_provider = "S3"
  enabled = true
  # Referenciar el ARN del rol creado inicialmente
  storage_aws_role_arn = aws_iam_role.snowflake_access_role_initial.arn
  storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"]
  comment = "Integración S3 para el lab dbt"

  # Asegurar que el rol inicial exista antes de crear la integración
  depends_on = [aws_iam_role.snowflake_access_role_initial]
}

# Actualización de Política de Confianza del Rol IAM - Paso 3
# Este recurso apunta al MISMO nombre de rol pero actualiza SOLO la política de confianza
# DESPUÉS de que la integración de snowflake exista y proporcione los valores necesarios.
resource "aws_iam_role" "snowflake_access_role_policy_update" {
  # Usar el MISMO nombre EXACTO que el bloque de recurso del rol inicial
  name = aws_iam_role.snowflake_access_role_initial.name

  # Definir la política de confianza (assume_role_policy) CORRECTA usando valores de la integración
  # Estos valores (storage_aws_iam_user_arn, storage_aws_external_id) son poblados
  # por Snowflake DESPUÉS de que el recurso de integración se crea exitosamente.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Usar el ARN proporcionado por el recurso de integración Snowflake
          AWS = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
           StringEquals = {
              # Usar el ID Externo proporcionado por el recurso de integración Snowflake
              "sts:ExternalId" = snowflake_storage_integration.s3_integration.storage_aws_external_id
           }
        }
      }
    ]
  })

  # Asegurar que esta actualización ocurra DESPUÉS de que se cree la integración
  depends_on = [snowflake_storage_integration.s3_integration]

  # Decirle a Terraform que este bloque de recurso es SÓLO responsable de la assume_role_policy.
  # Debería ignorar cambios en otros atributos gestionados por el bloque de recurso _initial.
  lifecycle {
    ignore_changes = [
      # Listar todos los atributos EXCEPTO assume_role_policy que son gestionados por el bloque _initial
      tags,
      description, # Si estableciste description en _initial, ignorar aquí
      force_detach_policies, # Adjunto de política gestionado separadamente
      inline_policy, # No usado
      managed_policy_arns, # Adjunto de política gestionado separadamente
      max_session_duration, # Si se estableció en _initial, ignorar aquí
      path, # Si se estableció en _initial, ignorar aquí
      permissions_boundary, # Si se estableció en _initial, ignorar aquí
    ]
  }
}


# Crear el Stage Externo - Paso 4
# Esto depende de la integración Y de que la política del rol haya sido actualizada correctamente.
resource "snowflake_stage" "s3_stage" {
  name     = upper(var.snowflake_stage_name)
  database = snowflake_database.lab_db.name
  schema   = snowflake_schema.bronze_schema.name
  url      = "s3://${aws_s3_bucket.data_bucket.bucket}/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  comment  = "Stage externo apuntando al bucket S3 para datos de clientes"
  file_format = "TYPE = CSV FIELD_DELIMITER = ',' SKIP_HEADER = 1 EMPTY_FIELD_AS_NULL = TRUE"

  depends_on = [
     # Depender explícitamente de que el recurso de actualización de política complete
     aws_iam_role.snowflake_access_role_policy_update,
     snowflake_storage_integration.s3_integration # También depende de la integración directamente
  ]
}
