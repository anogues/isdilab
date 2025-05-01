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

resource "aws_iam_role" "snowflake_access_role" {
  name = "snowflake-lab-access-role-${random_string.bucket_suffix.result}"

  # The assume_role_policy will be updated by Terraform on the second apply.
  # It references attributes from the snowflake_storage_integration resource.
  # These attributes are only known *after* the integration is created (Apply 1).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          # Use the ARN provided by the Snowflake integration resource after creation
          AWS = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
        }
        Action = "sts:AssumeRole"
        Condition = {
           StringEquals = {
              # Use the External ID provided by the Snowflake integration resource after creation
              "sts:ExternalId" = snowflake_storage_integration.s3_integration.storage_aws_external_id
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

  # This role depends on the storage integration being created first,
  # so that the storage_aws_iam_user_arn and storage_aws_external_id are available.
  depends_on = [snowflake_storage_integration.s3_integration]
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

# Create the Storage Integration
# This resource provides 'storage_aws_iam_user_arn' and 'storage_aws_external_id'
# outputs AFTER it is successfully created by Snowflake via the provider.
resource "snowflake_storage_integration" "s3_integration" {
  name = upper(var.snowflake_integration_name)
  type = "EXTERNAL_STAGE" # Indicates this is for S3 stages
  storage_provider = "S3"
  enabled = true
  storage_aws_role_arn = aws_iam_role.snowflake_access_role.arn # Reference the role ARN
  storage_allowed_locations = ["s3://${aws_s3_bucket.data_bucket.bucket}/"] # Restrict to our bucket
  comment = "S3 Integration for dbt lab"

  # IMPORTANT: storage_aws_role_arn must reference an EXISTING role when Snowflake creates
  # the integration. However, the role's trust policy needs values FROM the integration.
  # This creates a cycle that requires two applies.
  # Apply 1: Creates role (with potentially incomplete/placeholder trust policy initially if values not known), creates integration referencing role ARN. Snowflake populates ARN/ExternalID.
  # Apply 2: Terraform detects change in role's assume_role_policy based on populated values from integration, updates the role.
}

# Actualizar la política de confianza del rol IAM DESPUÉS de que la integración Snowflake se haya creado
# Esto requiere que la integración exista primero para obtener los valores correctos.
# Ejecutar `terraform apply` dos veces podría ser necesario.

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
     aws_iam_role.snowflake_access_role, # Asegura que la política del rol esté actualizada antes de que el stage use la integración
     snowflake_storage_integration.s3_integration
  ]
}
