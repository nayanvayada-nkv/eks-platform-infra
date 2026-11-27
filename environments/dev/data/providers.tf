data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-${var.environment}"
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}-${var.state_region}"
  network      = data.terraform_remote_state.network.outputs
  eks          = data.terraform_remote_state.eks.outputs
  is_primary   = var.role == "primary"
  global       = local.is_primary && var.dr_region != ""
  primary      = local.is_primary ? {} : data.terraform_remote_state.primary[0].outputs
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "data"
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

data "terraform_remote_state" "eks" {
  backend   = "s3"
  workspace = terraform.workspace # "default" = Mumbai, "dr" = Frankfurt
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/eks/terraform.tfstate"
    region = var.state_region # the state bucket stays in Mumbai
  }
}

# Secondary (DR) only: the Mumbai data stack (default workspace) owns the global cluster.
data "terraform_remote_state" "primary" {
  count     = var.role == "secondary" ? 1 : 0
  backend   = "s3"
  workspace = "default"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/data/terraform.tfstate"
    region = var.state_region
  }
}
