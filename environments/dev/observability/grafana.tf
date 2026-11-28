# ---------------------------------------------------------------------------
# Amazon Managed Grafana: dashboards without running (or pulling) a Grafana image.
# Login via IAM Identity Center (enable it once in the console); UI limited to your IP.
# Its role may only READ metrics (AMP), CloudWatch and X-Ray.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "grafana_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "grafana_read" {
  #checkov:skip=CKV_AWS_356:CloudWatch and X-Ray read APIs do not support resource-level permissions
  statement {
    sid       = "QueryPrometheus"
    actions   = ["aps:QueryMetrics", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata", "aps:DescribeWorkspace", "aps:ListWorkspaces"]
    resources = [aws_prometheus_workspace.this.arn]
  }

  statement {
    sid = "ReadCloudWatchAndXRay"
    actions = [
      "cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "cloudwatch:DescribeAlarms",
      "logs:StartQuery", "logs:GetQueryResults", "logs:DescribeLogGroups", "logs:GetLogEvents",
      "xray:GetTraceSummaries", "xray:BatchGetTraces", "xray:GetServiceGraph", "xray:GetTraceGraph",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DecryptEncryptedLogs"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.observability.arn]
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${local.name}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
}

resource "aws_iam_role_policy" "grafana" {
  name   = "read-telemetry"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_read.json
}

resource "aws_ec2_managed_prefix_list" "grafana_viewers" {
  count          = length(var.grafana_allowed_cidrs) > 0 ? 1 : 0 # free; kept for when Grafana is enabled
  name           = "${local.name}-grafana-viewers"
  address_family = "IPv4"
  max_entries    = 5

  dynamic "entry" {
    for_each = var.grafana_allowed_cidrs
    content {
      cidr = entry.value
    }
  }
}

resource "aws_grafana_workspace" "this" {
  count                    = var.grafana_enabled ? 1 : 0
  name                     = local.name
  description              = "Dashboards for ${local.name}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH", "XRAY"]
  grafana_version          = var.grafana_version

  dynamic "network_access_control" {
    for_each = aws_ec2_managed_prefix_list.grafana_viewers
    content {
      prefix_list_ids = [network_access_control.value.id]
      vpce_ids        = []
    }
  }
}

resource "aws_grafana_role_association" "admins" {
  count        = var.grafana_enabled && length(var.grafana_admin_user_ids) > 0 ? 1 : 0
  workspace_id = aws_grafana_workspace.this[0].id
  role         = "ADMIN"
  user_ids     = var.grafana_admin_user_ids
}

# Used once by scripts/grafana-dashboards.sh to load dashboards from Git. Expires after a day.
resource "aws_grafana_workspace_service_account" "dashboards" {
  count        = var.grafana_enabled ? 1 : 0
  workspace_id = aws_grafana_workspace.this[0].id
  name         = "dashboards-as-code"
  grafana_role = "EDITOR"
}

resource "aws_grafana_workspace_service_account_token" "dashboards" {
  count              = var.grafana_enabled ? 1 : 0
  workspace_id       = aws_grafana_workspace.this[0].id
  service_account_id = aws_grafana_workspace_service_account.dashboards[0].service_account_id
  name               = "dashboards-as-code"
  seconds_to_live    = 86400
}
