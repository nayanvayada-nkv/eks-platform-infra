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

variable "kubernetes_version" {
  description = "Must be in EKS standard support and supported by the Karpenter version in the platform stack."
  type        = string
  default     = "1.36"
}

variable "public_access_cidrs" {
  description = "Who can reach the Kubernetes API. Put your own public IP here, e.g. [\"203.0.113.10/32\"]."
  type        = list(string)

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "Do not open the API endpoint to the whole internet; use your IP /32."
  }
}

variable "admin_principal_arns" {
  description = "Extra IAM roles/users that get cluster-admin (the creator is admin already)."
  type        = list(string)
  default     = []
}
