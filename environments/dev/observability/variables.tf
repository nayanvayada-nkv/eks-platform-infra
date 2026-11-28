variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "state_region" {
  description = "Region of the Terraform state bucket (Mumbai), also when this stack runs in the dr workspace."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "grafana_admin_user_ids" {
  description = "IAM Identity Center user IDs that become Grafana admins (Identity Center console > Users > user > User ID). Empty = nobody can log in yet."
  type        = list(string)
  default     = []
}

variable "grafana_allowed_cidrs" {
  description = "Only these IPs may open the Grafana UI (your IP /32). Empty = reachable from anywhere, still behind Identity Center login."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.grafana_allowed_cidrs, "0.0.0.0/0")
    error_message = "Leave the list empty instead of adding 0.0.0.0/0."
  }
}

variable "grafana_version" {
  description = "Amazon Managed Grafana version (e.g. \"10.4\"). Null = the service default."
  type        = string
  default     = null
}

variable "grafana_enabled" {
  description = "Create the Amazon Managed Grafana workspace. Managed Grafana is not offered in ap-south-1 (found on the first run), so it needs a supported region; off until that is decided."
  type        = bool
  default     = true
}
