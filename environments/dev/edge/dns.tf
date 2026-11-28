# ---------------------------------------------------------------------------
# Optional custom domain (only when domain_name is set): ACM certificate in us-east-1,
# validated by DNS in your Route 53 zone, and an alias record to CloudFront.
# ---------------------------------------------------------------------------
data "aws_route53_zone" "this" {
  count        = local.use_domain ? 1 : 0
  name         = var.hosted_zone_name
  private_zone = false
}

resource "aws_acm_certificate" "edge" {
  count             = local.use_domain ? 1 : 0
  region            = local.global_region # CloudFront only uses us-east-1 certificates
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = local.use_domain ? {
    for o in aws_acm_certificate.edge[0].domain_validation_options : o.domain_name => o
  } : {}
  zone_id         = data.aws_route53_zone.this[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "edge" {
  count                   = local.use_domain ? 1 : 0
  region                  = local.global_region
  certificate_arn         = aws_acm_certificate.edge[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alias" {
  for_each = local.use_domain ? toset(["A", "AAAA"]) : toset([])
  zone_id  = data.aws_route53_zone.this[0].zone_id
  name     = var.domain_name
  type     = each.value

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
