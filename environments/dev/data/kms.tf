# One customer-managed key for the data layer: Aurora storage, the admin secret, Valkey.
# Multi-Region, so the DR region gets a replica with the same key material: the replicated
# admin secret can be decrypted there even if Mumbai is down.
resource "aws_kms_key" "data" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM in this single account; explicit policies come in Phase 8 hardening
  description             = "${local.name} data layer (Aurora, Valkey, DB secret)"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  multi_region            = true
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_kms_replica_key" "data_dr" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM, same as the primary key
  count                   = local.global ? 1 : 0
  region                  = var.dr_region
  description             = "${local.name} data key (replica for DR)"
  primary_key_arn         = aws_kms_key.data.arn
  deletion_window_in_days = 7
}
