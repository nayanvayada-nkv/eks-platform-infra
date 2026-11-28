# Container logs from Fluent Bit (one stream per pod/container). Encrypted, short retention.
resource "aws_cloudwatch_log_group" "containers" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; 14 days in dev for cost (container logs are the bulk of the bill), raise for prod
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.observability.arn
}
