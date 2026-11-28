# ---------------------------------------------------------------------------
# Pod Identity roles for the backend namespace. Two identities, two jobs:
#   backend    : log in to Aurora as "app" and to Valkey as the app user. Nothing else.
#   db-migrate : read the Aurora admin secret once per deploy to create the "app" role and tables.
# The running API never sees the admin password.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "backend" {
  statement {
    sid       = "AuroraIamLogin"
    actions   = ["rds-db:connect"]
    resources = ["arn:aws:rds-db:${var.aws_region}:${local.account_id}:dbuser:${aws_rds_cluster.this.cluster_resource_id}/${var.app_db_user}"]
  }

  statement {
    sid       = "ValkeyIamLogin"
    actions   = ["elasticache:Connect"]
    resources = [aws_elasticache_serverless_cache.this.arn, aws_elasticache_user.app.arn]
  }
}

resource "aws_iam_role" "backend" {
  name               = "${local.name}-backend"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "backend" {
  name   = "data-access"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend.json
}

resource "aws_eks_pod_identity_association" "backend" {
  cluster_name    = local.eks.cluster_name
  namespace       = var.app_namespace
  service_account = "backend"
  role_arn        = aws_iam_role.backend.arn
}

data "aws_iam_policy_document" "db_migrate" {
  statement {
    sid       = "ReadAdminSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_rds_cluster.this.master_user_secret[0].secret_arn]
  }

  # Decrypt only when Secrets Manager asks on our behalf, not raw KMS calls.
  statement {
    sid       = "DecryptAdminSecret"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.data.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_migrate" {
  name               = "${local.name}-db-migrate"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "db_migrate" {
  name   = "read-admin-secret"
  role   = aws_iam_role.db_migrate.id
  policy = data.aws_iam_policy_document.db_migrate.json
}

resource "aws_eks_pod_identity_association" "db_migrate" {
  cluster_name    = local.eks.cluster_name
  namespace       = var.app_namespace
  service_account = "db-migrate"
  role_arn        = aws_iam_role.db_migrate.arn
}
