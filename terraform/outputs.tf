# terraform/outputs.tf
output "aws_s3_bucket_name" { description = "Nombre del bucket S3"; value = aws_s3_bucket.data_bucket.bucket }
output "aws_s3_bucket_arn" { description = "ARN del bucket S3"; value = aws_s3_bucket.data_bucket.arn }
output "snowflake_database_name" { description = "Nombre DB Snowflake"; value = snowflake_database.lab_db.name }
output "snowflake_schema_name" { description = "Nombre Schema Snowflake ('bronze')"; value = snowflake_schema.bronze_schema.name }
output "snowflake_stage_name" { description = "Nombre completo Stage Externo"; value = "${snowflake_database.lab_db.name}.${snowflake_schema.bronze_schema.name}.${snowflake_stage.s3_stage.name}" }
output "snowflake_iam_role_arn" { description = "ARN Rol IAM"; value = aws_iam_role.snowflake_access_role_initial.arn }
output "snowflake_integration_name" { description = "Nombre Integración Snowflake"; value = snowflake_storage_integration.s3_integration.name }

# Outputs informativos que se necesitarán para el paso manual
output "manual_step_info_integration_name" {
  description = "Nombre de la integración a describir en Snowflake para obtener datos para la política IAM"
  value       = upper(var.snowflake_integration_name)
}
output "manual_step_info_iam_role_name" {
  description = "Nombre del Rol IAM a editar en la consola de AWS"
  value       = aws_iam_role.snowflake_access_role_initial.name
}
