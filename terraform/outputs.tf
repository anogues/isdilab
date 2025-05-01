# terraform/outputs.tf

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
  # El ARN/Nombre es determinado por el bloque de creación inicial del recurso
  value       = aws_iam_role.snowflake_access_role_initial.arn
}

output "snowflake_integration_name" {
  description = "Nombre de la integración de almacenamiento Snowflake"
  value       = snowflake_storage_integration.s3_integration.name
}

# Mostrar los valores proporcionados por el recurso de integración Snowflake después de la creación
output "snowflake_integration_aws_iam_user_arn_output" {
  description = "ARN de usuario IAM de AWS de Snowflake para la política de confianza de la integración (disponible después del apply)"
  value       = snowflake_storage_integration.s3_integration.storage_aws_iam_user_arn
  sensitive   = true # Contiene info de la cuenta
}

output "snowflake_integration_aws_external_id_output" {
   description = "ID Externo de AWS de Snowflake para la política de confianza de la integración (disponible después del apply)"
   value       = snowflake_storage_integration.s3_integration.storage_aws_external_id
   sensitive   = true
}
