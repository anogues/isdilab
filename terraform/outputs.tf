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
