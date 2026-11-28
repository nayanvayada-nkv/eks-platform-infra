variable "aws_region" {
  description = "Region for the state bucket and KMS key."
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project name used in resource names."
  type        = string
  default     = "eks-platform"
}

variable "github_org" {
  description = "GitHub username or organisation that owns the repo."
  type        = string

  validation {
    condition     = var.github_org != "CHANGE_ME" && length(var.github_org) > 0
    error_message = "Set github_org in terraform.tfvars (copy terraform.tfvars.example)."
  }
}

variable "github_repo" {
  description = "Repository name allowed to assume the CI roles."
  type        = string
  default     = "eks-platform-infra"
}

variable "extra_tags" {
  description = "Additional tags for every resource."
  type        = map(string)
  default     = {}
}

variable "github_subject_prefix" {
  description = "Start of the GitHub OIDC 'sub' claim. Empty = repo:<org>/<repo>. Repos with immutable subjects (GitHub setting, default for new repos) send repo:<org>@<owner-id>/<repo>@<repo-id>; check with: gh api repos/<org>/<repo>/actions/oidc/customization/sub"
  type        = string
  default     = ""
}
