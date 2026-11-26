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
