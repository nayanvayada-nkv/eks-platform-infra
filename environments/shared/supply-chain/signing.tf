# ---------------------------------------------------------------------------
# Cosign signing key in KMS. The private key never leaves KMS: CI asks KMS to
# sign the image digest, and Kyverno (Phase 3) verifies with the public key.
# ---------------------------------------------------------------------------
resource "aws_kms_key" "cosign" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM; only the build role has kms:Sign
  description              = "${var.project} Cosign image signing key"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  # Multi-Region key (Phase 7): replicas in the DR regions share the same key material, so
  # the DR cluster verifies signatures locally, even when Mumbai is down.
  multi_region = true
  # Asymmetric keys cannot be auto-rotated. Rotate by creating a new key and
  # trusting both public keys in Kyverno during the switch.
}

resource "aws_kms_alias" "cosign" {
  name          = "alias/${var.project}-cosign"
  target_key_id = aws_kms_key.cosign.key_id
}

data "aws_kms_public_key" "cosign" {
  key_id = aws_kms_key.cosign.arn
}

# Replica of the Cosign key in each DR region, with the same alias, so Kyverno's
# awskms:///alias/<project>-cosign works unchanged there. Verify-only use in DR.
resource "aws_kms_replica_key" "cosign" {
  #checkov:skip=CKV2_AWS_64:Default key policy delegates to IAM, same as the primary key
  for_each                = toset(var.replication_regions)
  region                  = each.value
  description             = "${var.project} Cosign key (replica in ${each.value})"
  primary_key_arn         = aws_kms_key.cosign.arn
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "cosign_replica" {
  for_each      = aws_kms_replica_key.cosign
  region        = each.key
  name          = "alias/${var.project}-cosign"
  target_key_id = each.value.key_id
}
