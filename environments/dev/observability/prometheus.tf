# ---------------------------------------------------------------------------
# Amazon Managed Service for Prometheus: long-term metric storage, rule evaluation and
# Alertmanager, managed and highly available. In-cluster Prometheus only scrapes and
# forwards (remote write), keeping a few hours locally.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "amp" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; 14 days in dev for cost (container logs are the bulk of the bill), raise for prod
  name              = "/aws/prometheus/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.observability.arn
}

resource "aws_prometheus_workspace" "this" {
  alias       = local.name
  kms_key_arn = aws_kms_key.observability.arn

  # Rule evaluation and alert delivery errors (e.g. SNS permission problems) land here.
  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }
}

# SLO recording rules, burn-rate alerts and platform alerts (tested with promtool).
resource "aws_prometheus_rule_group_namespace" "rules" {
  for_each     = fileset("${path.module}/rules", "*.rules.yaml")
  name         = trimsuffix(each.value, ".rules.yaml")
  workspace_id = aws_prometheus_workspace.this.id
  data         = file("${path.module}/rules/${each.value}")
}

resource "aws_prometheus_alert_manager_definition" "this" {
  workspace_id = aws_prometheus_workspace.this.id
  definition = templatefile("${path.module}/alertmanager.yaml.tftpl", {
    topic_arn = local.security.alerts_topic_arn
    region    = var.aws_region
  })
}
