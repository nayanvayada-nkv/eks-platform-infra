output "url" {
  description = "Public HTTPS address of the API."
  value       = local.use_domain ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.this.domain_name}"
}

# Read by the platform stack: Argo CD binds the Istio gateway pods to this target group.
output "gateway_target_group_arn" {
  value = aws_lb_target_group.gateway.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "waf_log_group" {
  value = "${aws_cloudwatch_log_group.waf.name} (us-east-1)"
}
