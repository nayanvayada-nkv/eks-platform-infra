# Key for metrics (AMP) and container logs (CloudWatch Logs). Logs need an explicit key
# policy grant, scoped by encryption context to this account's log groups.
data "aws_iam_policy_document" "observability_key" {
  #checkov:skip=CKV_AWS_356:In a key policy "*" means this key only (standard KMS key policy form)
  #checkov:skip=CKV_AWS_111:Account root admin statement is the AWS default key policy; access is then governed by IAM
  #checkov:skip=CKV_AWS_109:Same as CKV_AWS_111
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "observability" {
  description             = "${local.name} metrics and logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.observability_key.json
}

resource "aws_kms_alias" "observability" {
  name          = "alias/${local.name}-observability"
  target_key_id = aws_kms_key.observability.key_id
}
