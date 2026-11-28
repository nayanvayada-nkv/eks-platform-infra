variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "alert_email" {
  description = "Where budget alerts and HIGH/CRITICAL security findings go. Empty = no email (findings still appear in the console). Kept in terraform.tfvars (git-ignored)."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget; email at 80% actual and 100% forecast."
  type        = number
  default     = 10
}

variable "guardduty_runtime_monitoring" {
  description = "GuardDuty EKS Runtime Monitoring (agent DaemonSet + a GuardDuty-managed VPC endpoint). Off by default: the managed endpoint must be removed before the dev VPC can be destroyed."
  type        = bool
  default     = false
}

variable "config_bucket_retention_days" {
  type    = number
  default = 90
}
