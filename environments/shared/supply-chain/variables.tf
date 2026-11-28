variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "eks-platform"
}

variable "github_org" {
  description = "GitHub user or organisation that owns the repo."
  type        = string

  validation {
    condition     = var.github_org != "CHANGE_ME" && length(var.github_org) > 0
    error_message = "Set github_org in terraform.tfvars."
  }
}

variable "github_repo" {
  description = "Repository whose main branch may push and sign images."
  type        = string
  default     = "eks-platform-infra"
}

variable "repositories" {
  description = "ECR repositories to create, one per service image. Created as <project>/<name>."
  type        = list(string)
  default     = ["backend"]
}

variable "keep_image_count" {
  description = "Tagged artifacts kept per repository. Each build adds 3 (image, .sig, .att), so 90 is about 30 builds."
  type        = number
  default     = 90
}

variable "replication_regions" {
  description = "DR regions that receive a copy of every image (Phase 7), e.g. [\"eu-central-1\"]."
  type        = list(string)
  default     = []
}

variable "force_delete_repositories" {
  description = "Allow terraform destroy to delete repositories that still hold images. true for dev, false for prod."
  type        = bool
  default     = true
}

variable "github_subject_prefix" {
  description = "Start of the GitHub OIDC 'sub' claim. Empty = repo:<org>/<repo>. Repos with immutable subjects (GitHub setting, default for new repos) send repo:<org>@<owner-id>/<repo>@<repo-id>; check with: gh api repos/<org>/<repo>/actions/oidc/customization/sub"
  type        = string
  default     = ""
}
