# Read by the platform stack and passed to Argo CD (no secrets).
output "collectors_config" {
  value = {
    region              = var.aws_region
    ampRemoteWriteUrl   = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
    containerLogGroup   = aws_cloudwatch_log_group.containers.name
    ampWorkspaceId      = aws_prometheus_workspace.this.id
    ampQueryEndpointUrl = aws_prometheus_workspace.this.prometheus_endpoint
  }
}

output "grafana_url" {
  value = "https://${aws_grafana_workspace.this.endpoint}"
}

output "grafana_dashboards_token" {
  description = "Short-lived token for scripts/grafana-dashboards.sh."
  value       = aws_grafana_workspace_service_account_token.dashboards.key
  sensitive   = true
}
