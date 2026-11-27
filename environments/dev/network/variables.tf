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
variable "vpc_cidr" {
  description = "Mumbai 10.20.0.0/16, Frankfurt DR 10.21.0.0/16 (dr.tfvars). Both inside 10.20.0.0/15, which the backend NetworkPolicy allows, and non-overlapping so the VPCs could be peered later."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zone_ids" {
  description = "Exactly three AZ IDs to use. Mumbai: aps1-az1..3; Frankfurt DR (dr.tfvars): euc1-az1..3."
  type        = list(string)
  default     = ["aps1-az1", "aps1-az2", "aps1-az3"]

  validation {
    condition     = length(var.availability_zone_ids) == 3
    error_message = "The network module builds one public and one private subnet in exactly three AZs."
  }
}
