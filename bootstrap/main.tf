data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = merge(
    {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    },
    var.extra_tags
  )
}

# ---------------------------------------------------------------------------
# KMS key for Terraform state
# ---------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM in this single account
  description             = "${var.project} Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# S3 bucket for remote state (versioned, encrypted, private, TLS only)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:State access is audited by CloudTrail; separate access-log bucket not worth it for one bucket
  #checkov:skip=CKV_AWS_144:Versioning covers state recovery; cross-region copy not needed: the DR stacks keep their state here too and the bucket is versioned
  #checkov:skip=CKV2_AWS_62:No consumers for bucket events
  bucket = local.state_bucket_name
  # Bootstrap is never destroyed in normal use: Terraform refuses to delete the state bucket, and
  # a delete fails while it holds state versions. (28 Nov 2026 the owner asked for an empty account;
  # protection was switched off only for that teardown and restored here afterwards.)
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------------------------------------------------------------------------
# GitHub Actions -> AWS via OIDC (no stored keys)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Published GitHub thumbprints. AWS also validates via its trusted CA store.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only this repo, only pull requests and the main branch.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.github_subject}:pull_request",
        "${local.github_subject}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name                 = "${var.project}-github-plan"
  description          = "Read-only role for terraform plan in GitHub Actions"
  assume_role_policy   = data.aws_iam_policy_document.github_plan_trust.json
  max_session_duration = 3600
}

# NOTE: ReadOnlyAccess is broad. Narrow it once you know what plan needs
# (use IAM Access Analyzer to generate a policy from CloudTrail activity).
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_state_access" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadWriteStateAndLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "UseStateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "plan_state_access" {
  name   = "state-access"
  role   = aws_iam_role.github_plan.id
  policy = data.aws_iam_policy_document.plan_state_access.json
}

# The scoped "apply" role (main branch only) is added in Phase 1.

locals {
  # Immutable subjects contain the owner and repo IDs, so a deleted and re-created repo with the
  # same name (possibly by someone else) can never assume this role.
  github_subject = var.github_subject_prefix != "" ? var.github_subject_prefix : "repo:${var.github_org}/${var.github_repo}"
}
