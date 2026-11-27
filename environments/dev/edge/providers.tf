data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-${var.environment}"
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.state_region}"
  network      = data.terraform_remote_state.network.outputs
  # CloudFront-scoped resources (WAF, its logs, ACM certificates) must live in us-east-1.
  # AWS provider v6 sets the region per resource, so no second provider block is needed.
  global_region = "us-east-1"
  use_domain    = var.domain_name != ""
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "edge"
    }
  }
}

data "terraform_remote_state" "network" {
  backend   = "s3"
  workspace = terraform.workspace # "default" = Mumbai, "dr" = Frankfurt
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/network/terraform.tfstate"
    region = var.state_region # the state bucket stays in Mumbai
  }
}
