data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.state_region}"
  eks          = data.terraform_remote_state.eks.outputs
  network      = data.terraform_remote_state.network.outputs
  kube_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "platform"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
    exec                   = local.kube_exec
  }
}

provider "kubectl" {
  host                   = local.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = local.kube_exec.api_version
    command     = local.kube_exec.command
    args        = local.kube_exec.args
  }
}
