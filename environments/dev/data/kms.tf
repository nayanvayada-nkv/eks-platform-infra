# One customer-managed key for the data layer: Aurora storage, its master-password secret,
# Valkey storage and snapshots. Separate from the EKS secrets key and the Cosign key, so each
# key's policy and CloudTrail trail describe one purpose.
resource "aws_kms_key" "data" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM in this single account; explicit policies come in Phase 8 hardening
  description             = "${local.name} data layer (Aurora, Valkey, DB secret)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
