# ---------------------------------------------------------------------------
# Kyverno admission controller role (Pod Identity), Phase 3.
# Kyverno checks Cosign signatures at admission time, so it needs to:
#   - read image manifests and signatures from our ECR repositories (read-only), and
#   - read the public half of the Cosign KMS key (never kms:Sign).
# Kyverno itself is installed by Argo CD (gitops/clusters/dev/templates/kyverno.yaml);
# a Pod Identity association can exist before the namespace and service account do.
# ---------------------------------------------------------------------------
locals {
  kyverno_namespace       = "kyverno"
  kyverno_service_account = "kyverno-admission-controller" # chart default for release "kyverno"
  cosign_key_alias        = "alias/${var.project}-cosign"  # created by environments/shared/supply-chain
}

data "aws_iam_policy_document" "kyverno_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "kyverno" {
  # GetAuthorizationToken has no resource-level permissions in IAM.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrReadProjectRepos"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}/*"]
  }

  # Only the Cosign key, matched by alias, so this stack does not depend on the
  # supply-chain state. Public-key reads only: Kyverno can verify, never sign.
  statement {
    sid       = "CosignPublicKey"
    actions   = ["kms:GetPublicKey", "kms:DescribeKey"]
    resources = ["arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:ResourceAliases"
      values   = [local.cosign_key_alias]
    }
  }
}

resource "aws_iam_role" "kyverno" {
  name               = "${local.cluster_name}-kyverno"
  assume_role_policy = data.aws_iam_policy_document.kyverno_assume.json
  tags               = { Component = "kyverno" }
}

resource "aws_iam_role_policy" "kyverno" {
  name   = "verify-images"
  role   = aws_iam_role.kyverno.id
  policy = data.aws_iam_policy_document.kyverno.json
}

resource "aws_eks_pod_identity_association" "kyverno" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.kyverno_namespace
  service_account = local.kyverno_service_account
  role_arn        = aws_iam_role.kyverno.arn
}
