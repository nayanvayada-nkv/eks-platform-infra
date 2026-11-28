# ---------------------------------------------------------------------------
# Security Hub (CSPM): continuous checks against AWS Foundational Security Best Practices,
# plus GuardDuty findings in one place. Controls need AWS Config recording (config.tf).
# ---------------------------------------------------------------------------
resource "aws_securityhub_account" "this" {
  enable_default_standards  = false # we choose the standard explicitly below
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}
