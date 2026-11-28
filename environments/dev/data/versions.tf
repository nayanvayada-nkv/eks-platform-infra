terraform {
  required_version = ">= 1.11.0" # write-only arguments keep the DB admin password out of state
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9" # ephemeral random_password
    }
  }
}
