variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "domain_name" {
  description = "Optional. A hostname in a Route 53 hosted zone you own, e.g. api.example.com. Empty = use the free *.cloudfront.net address (HTTPS still works)."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Route 53 public hosted zone that contains domain_name, e.g. example.com. Needed only with domain_name."
  type        = string
  default     = ""
}

variable "allowed_viewer_cidrs" {
  description = "Dev: only these IPs pass the WAF (your IP /32). Empty = open to everyone, still filtered by the managed rules and the rate limit."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_viewer_cidrs, "0.0.0.0/0")
    error_message = "Leave the list empty instead of adding 0.0.0.0/0."
  }
}

variable "rate_limit_per_minute" {
  description = "Requests per client IP per minute before the WAF blocks it (rate-based rule, 1-minute window)."
  type        = number
  default     = 100
}

variable "waf_log_retention_days" {
  type    = number
  default = 30
}
