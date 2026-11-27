data "aws_caller_identity" "current" {}

locals {
  name         = "${var.project}-${var.environment}"
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.project}-tfstate-${local.account_id}-${var.aws_region}"
  network      = data.terraform_remote_state.network.outputs
  eks          = data.terraform_remote_state.eks.outputs
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
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/network/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = local.state_bucket
    key    = "nonprod/dev/ap-south-1/eks/terraform.tfstate"
    region = var.aws_region
  }
}
