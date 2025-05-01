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
  default     = "bronze"
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
