# ---------------------------------------------------------------------------
# Alerts: HIGH/CRITICAL GuardDuty findings and CRITICAL Security Hub findings by email,
# plus the cost budget (roadmap Phase 0 item, built here).
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-security-alerts"
  kms_master_key_id = aws_kms_key.security.arn
}

data "aws_iam_policy_document" "alerts_topic" {
  statement {
    sid       = "EventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${var.aws_region}:${local.account_id}:rule/${local.name}-*"]
    }
  }

  # Amazon Managed Prometheus Alertmanager (Phase 6 SLO and platform alerts).
  statement {
    sid       = "ManagedPrometheusPublish"
    actions   = ["sns:Publish", "sns:GetTopicAttributes"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["aps.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = local.alerts_on ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email" # AWS sends a confirmation email first
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${local.name}-guardduty-high"
  description = "GuardDuty findings with severity 7 or more"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_rule" "securityhub_critical" {
  name        = "${local.name}-securityhub-critical"
  description = "New, active CRITICAL Security Hub findings"
  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity    = { Label = ["CRITICAL"] }
        Workflow    = { Status = ["NEW"] }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_sns" {
  for_each = {
    guardduty   = aws_cloudwatch_event_rule.guardduty_high.name
    securityhub = aws_cloudwatch_event_rule.securityhub_critical.name
  }
  rule      = each.value
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn
}

resource "aws_budgets_budget" "monthly" {
  count        = local.alerts_on ? 1 : 0
  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
