variable "name" {
  description = "EKS cluster name."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. Keep it in EKS standard support: extended support costs 6x more per hour."
  type        = string
  default     = "1.36"
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and the system node group."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API publicly (restricted by public_access_cidrs). Private access is always on."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Set to your own IP /32."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.endpoint_public_access || (length(var.public_access_cidrs) > 0 && !contains(var.public_access_cidrs, "0.0.0.0/0"))
    error_message = "With a public endpoint, list specific CIDRs (your IP /32), never 0.0.0.0/0."
  }
}

variable "cluster_log_types" {
  description = "Control plane log types sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "CloudWatch retention for control plane logs."
  type        = number
  default     = 30
}

variable "admin_principal_arns" {
  description = "Extra IAM principals (roles/users) given cluster-admin through EKS access entries. The identity that creates the cluster is admin automatically."
  type        = list(string)
  default     = []
}

variable "system_node_instance_types" {
  description = "Instance types for the small managed node group that runs system pods and Karpenter."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_capacity_type" {
  description = "ON_DEMAND or SPOT for the system node group. Karpenter must run on stable nodes, so ON_DEMAND is safer."
  type        = string
  default     = "ON_DEMAND"
}

variable "system_node_size" {
  description = "Desired, min and max nodes in the system node group."
  type = object({
    desired = number
    min     = number
    max     = number
  })
  default = {
    desired = 2
    min     = 2
    max     = 3
  }
}

variable "system_node_disk_gb" {
  description = "Root volume size for system nodes."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
