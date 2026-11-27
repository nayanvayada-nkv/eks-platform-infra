# ---------------------------------------------------------------------------
# AWS WAF on CloudFront (global scope, so it lives in us-east-1). Rule order:
#   0 allow-list (dev only, optional)  1 IP reputation  2 common exploits (OWASP)
#   3 known bad inputs (Log4j...)      4 SQL injection   5 rate limit per IP
# Phase 5 proof: an XSS / SQLi probe and a request flood get HTTP 403.
# ---------------------------------------------------------------------------
locals {
  managed_rule_groups = {
    AWSManagedRulesAmazonIpReputationList = 1
    AWSManagedRulesCommonRuleSet          = 2
    AWSManagedRulesSQLiRuleSet            = 4
  }
}

resource "aws_wafv2_ip_set" "viewers" {
  count              = length(var.allowed_viewer_cidrs) > 0 ? 1 : 0
  region             = local.global_region
  name               = "${local.name}-allowed-viewers"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = var.allowed_viewer_cidrs
}

resource "aws_wafv2_web_acl" "edge" {
  region = local.global_region
  name   = "${local.name}-edge"
  scope  = "CLOUDFRONT"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = aws_wafv2_ip_set.viewers
    content {
      name     = "dev-allow-list"
      priority = 0
      action {
        block {}
      }
      statement {
        not_statement {
          statement {
            ip_set_reference_statement {
              arn = rule.value.arn
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "dev-allow-list"
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups
    content {
      name     = rule.key
      priority = rule.value
      override_action {
        none {} # use the rule group's own block actions
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = rule.key
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # Explicit (not in the loop above) so scanners can see the Log4j (CVE-2021-44228) protection.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 5
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit                 = var.rate_limit_per_minute
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-edge"
    sampled_requests_enabled   = true
  }
}

# WAF log group names must start with "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption is enough for dev WAF logs
  #checkov:skip=CKV_AWS_338:Retention is a variable; 30 days in dev for cost
  region            = local.global_region
  name              = "aws-waf-logs-${local.name}-edge"
  retention_in_days = var.waf_log_retention_days
}

resource "aws_wafv2_web_acl_logging_configuration" "edge" {
  region                  = local.global_region
  resource_arn            = aws_wafv2_web_acl.edge.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # Never write credentials into logs.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}
