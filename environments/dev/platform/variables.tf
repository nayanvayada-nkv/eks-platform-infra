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

variable "aws_lb_controller_chart_version" {
  type    = string
  default = "3.6.3"
}

variable "karpenter_chart_version" {
  description = "Check the Karpenter compatibility matrix against the cluster's Kubernetes version before bumping."
  type        = string
  default     = "1.15.3"
}

variable "karpenter_cpu_limit" {
  description = "Hard cap on total vCPU Karpenter may launch. This is the main cost guard rail."
  type        = number
  default     = 16
}

variable "metrics_server_chart_version" {
  type    = string
  default = "3.14.0"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart from argoproj.github.io/argo-helm."
  type        = string
  default     = "10.18.2"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the Git repo Argo CD pulls from, e.g. https://github.com/<you>/eks-platform-infra.git. Empty = install Argo CD without the root app."
  type        = string
  default     = ""
}

variable "gitops_revision" {
  description = "Branch or tag Argo CD tracks."
  type        = string
  default     = "main"
}

variable "ingress_allowed_cidrs" {
  description = "Who may reach the public ALB in front of the Istio ingress gateway, e.g. [\"203.0.113.10/32\"]. Empty = no ALB."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.ingress_allowed_cidrs, "0.0.0.0/0")
    error_message = "Dev ALB is for your own IP only; open it to the internet only behind CloudFront + WAF (Phase 5)."
  }
}
