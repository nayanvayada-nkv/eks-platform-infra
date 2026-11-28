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
