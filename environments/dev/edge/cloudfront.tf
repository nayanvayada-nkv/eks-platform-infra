# ---------------------------------------------------------------------------
# CloudFront: the only public entry point. HTTPS for viewers, WAF in front, AWS Shield
# Standard (automatic, free) against network-layer DDoS. API traffic is not cached.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${local.name}-edge-alb"
    arn                    = aws_lb.internal.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only" # private AWS network hop; TLS to the ALB needs a domain certificate

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled" # API responses are per request
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewerExceptHostHeader" # forward query strings, headers, cookies
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy" # HSTS, X-Content-Type-Options, X-Frame-Options...
}

resource "aws_cloudfront_distribution" "this" {
  #checkov:skip=CKV_AWS_86:Access logs come with the Phase 6 logging bucket; WAF logs every request already
  #checkov:skip=CKV_AWS_310:Single origin in dev; origin failover arrives with DR (Phase 7)
  #checkov:skip=CKV_AWS_305:API distribution, there is no root object
  #checkov:skip=CKV_AWS_374:No geo restriction for a public demo API
  #checkov:skip=CKV_AWS_174:With the default *.cloudfront.net certificate the TLS policy is fixed by AWS; with a domain it is TLSv1.2_2021
  #checkov:skip=CKV2_AWS_47:The attached web ACL has AWSManagedRulesKnownBadInputsRuleSet (Log4j); CKV_AWS_192 passes on it, this graph check misses the cross-region link
  #checkov:skip=CKV2_AWS_42:A custom certificate is used when domain_name is set; the default domain uses CloudFront's certificate
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name} API"
  price_class     = "PriceClass_200" # includes India; excludes the most expensive edges
  aliases         = local.use_domain ? [var.domain_name] : []
  web_acl_id      = aws_wafv2_web_acl.edge.arn

  origin {
    origin_id   = "internal-alb"
    domain_name = aws_lb.internal.dns_name

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_read_timeout      = 30 # Aurora resume from 0 ACU can take ~15 s
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id           = "internal-alb"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_domain
    acm_certificate_arn            = local.use_domain ? aws_acm_certificate_validation.edge[0].certificate_arn : null
    ssl_support_method             = local.use_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_domain ? "TLSv1.2_2021" : "TLSv1"
  }
}
