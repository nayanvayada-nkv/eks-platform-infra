data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-${var.environment}"
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}-${var.state_region}"
  eks          = data.terraform_remote_state.eks.outputs
  security     = data.terraform_remote_state.security.outputs
  log_group    = "/eks/${local.name}/containers"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "observability"
    }
  }
}

data "terraform_remote_state" "eks" {
  backend   = "s3"
  workspace = terraform.workspace # "default" = Mumbai, "dr" = Frankfurt
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/eks/terraform.tfstate"
    region = var.state_region # the state bucket stays in Mumbai
  }
}

# Alerts go to the one alert topic owned by shared/security (same email as GuardDuty and the budget).
data "terraform_remote_state" "security" {
  backend   = "s3"
  workspace = "default" # shared stacks are not per region
  config = {
    bucket = local.state_bucket
    key    = "shared/ap-south-1/security/terraform.tfstate"
    region = var.state_region # the state bucket stays in Mumbai
  }
}
