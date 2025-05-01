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
