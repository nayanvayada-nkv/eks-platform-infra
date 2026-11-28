data "aws_caller_identity" "current" {}

locals {
  cluster_name = "${var.project}-${var.environment}"
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.state_region}"
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

module "eks" {
  source = "../../../modules/eks"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids

  endpoint_public_access = true
  public_access_cidrs    = var.public_access_cidrs
  admin_principal_arns   = var.admin_principal_arns

  # Dev: two small on-demand nodes for system pods. Workloads land on Karpenter nodes.
  system_node_instance_types = ["t3.medium"]
  system_node_size           = { desired = 2, min = 2, max = 3 }
}

# ---------------------------------------------------------------------------
# Karpenter: controller role (Pod Identity), node role + access entry, SQS interruption queue
# ---------------------------------------------------------------------------
module "karpenter" {
  #checkov:skip=CKV_TF_1:Registry module pinned by version constraint and lock file
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.30"

  cluster_name = module.eks.cluster_name
  namespace    = "kube-system"

  # The controller policy JSON is larger than the 6,144-character limit for managed IAM
  # policies (apply failed with LimitExceeded on the first real run). Inline role policies
  # allow 10,240 characters; the permissions are identical.
  enable_inline_policy = true

  # Karpenter-launched nodes get SSM access too (no SSH keys).
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller role (Pod Identity)
# ---------------------------------------------------------------------------
module "aws_lb_controller_pod_identity" {
  #checkov:skip=CKV_TF_1:Registry module pinned by version constraint and lock file
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.11"

  name                            = "${local.cluster_name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}
