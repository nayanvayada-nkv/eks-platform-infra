# ---------------------------------------------------------------------------
# GuardDuty: threat detection from CloudTrail, VPC flow logs, DNS logs and the EKS audit log
# (e.g. anonymous API access, pods talking to crypto-mining or known-bad IPs, credential misuse).
# Account + region wide, which is why it lives in shared/, not dev/.
# ---------------------------------------------------------------------------
resource "aws_guardduty_detector" "this" {
  #checkov:skip=CKV2_AWS_3:Single account; no AWS Organizations delegated admin to configure
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "runtime" {
  detector_id = aws_guardduty_detector.this.id
  name        = "RUNTIME_MONITORING"
  status      = var.guardduty_runtime_monitoring ? "ENABLED" : "DISABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT" # GuardDuty installs and updates its agent add-on
    status = var.guardduty_runtime_monitoring ? "ENABLED" : "DISABLED"
  }
}
