# Key for the Config bucket and the alerts topic. The key policy lets AWS Config,
# EventBridge and Managed Prometheus (alerts) use it, scoped to this account; everything else goes through IAM.
data "aws_iam_policy_document" "security_key" {
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
    sid       = "ServicesEncrypt"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com", "events.amazonaws.com", "aps.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "security" {
  description             = "${local.name} security tooling (Config bucket, alerts topic)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.security_key.json
}

resource "aws_kms_alias" "security" {
  name          = "alias/${local.name}-security"
  target_key_id = aws_kms_key.security.key_id
}
