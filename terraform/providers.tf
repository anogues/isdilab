terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 1.0.5" 
    }
  }
  cloud {
    organization = "anogues-ISDI" # Reemplaza con el nombre de tu org de TFC

    workspaces {
      name = "dbt-snowflake-lab"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "snowflake" {
  # Credenciales obtenidas de variables de entorno (SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, etc.)
  # La región se especifica vía variable por claridad si se necesita en otro lugar
  # role = var.snowflake_role # A menudo también se establece vía variable de entorno
  preview_features_enabled = [
      "snowflake_storage_integration_resource"
  ]
}
