# ---------------------------------------------------------------------------
# Pod Identity roles for the collectors. Each can only write its own kind of data to
# its own destination; none can read metrics, logs or traces back.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

locals {
  collectors = {
    prometheus = {
      namespace       = "monitoring"
      service_account = "prometheus"
      statements = [{
        actions   = ["aps:RemoteWrite"]
        resources = [aws_prometheus_workspace.this.arn]
      }]
    }
    fluent-bit = {
      namespace       = "logging"
      service_account = "fluent-bit"
      statements = [{
        actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        resources = [aws_cloudwatch_log_group.containers.arn, "${aws_cloudwatch_log_group.containers.arn}:*"]
      }]
    }
    otel-collector = {
      namespace       = "monitoring"
      service_account = "otel-collector"
      # X-Ray write APIs have no resource-level permissions.
      statements = [{
        actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        resources = ["*"]
      }]
    }
  }
}

data "aws_iam_policy_document" "collector" {
  #checkov:skip=CKV_AWS_356:X-Ray write actions do not support resource-level permissions; others are scoped to one ARN
  #checkov:skip=CKV_AWS_111:Same: X-Ray PutTraceSegments requires "*"
  for_each = local.collectors

  dynamic "statement" {
    for_each = each.value.statements
    content {
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role" "collector" {
  for_each           = local.collectors
  name               = "${local.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy" "collector" {
  for_each = local.collectors
  name     = "write-telemetry"
  role     = aws_iam_role.collector[each.key].id
  policy   = data.aws_iam_policy_document.collector[each.key].json
}

resource "aws_eks_pod_identity_association" "collector" {
  for_each        = local.collectors
  cluster_name    = local.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.collector[each.key].arn
}
