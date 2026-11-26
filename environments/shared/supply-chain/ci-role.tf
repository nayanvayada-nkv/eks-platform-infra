# ---------------------------------------------------------------------------
# GitHub Actions build role: push images and sign them. Only the main branch
# of this repository can assume it; pull requests build and scan without AWS.
# The OIDC provider itself is created once in bootstrap/.
# ---------------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "build_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_build" {
  name                 = "${var.project}-github-build"
  description          = "GitHub Actions on main: push images to ECR and sign them with Cosign (KMS)"
  assume_role_policy   = data.aws_iam_policy_document.build_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "build" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "PushAndReadImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [for r in aws_ecr_repository.this : r.arn]
  }

  statement {
    sid       = "SignWithCosignKey"
    actions   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
    resources = [aws_kms_key.cosign.arn]
  }
}

resource "aws_iam_role_policy" "github_build" {
  name   = "push-and-sign"
  role   = aws_iam_role.github_build.id
  policy = data.aws_iam_policy_document.build.json
}
