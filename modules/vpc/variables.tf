variable "name" {
  description = "Name prefix for all network resources."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR range."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to use."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR per AZ for public subnets (load balancers, NAT)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "Provide exactly one public subnet CIDR per AZ."
  }
}

variable "private_subnet_cidrs" {
  description = "One CIDR per AZ for private subnets (nodes and pods)."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "Provide exactly one private subnet CIDR per AZ."
  }
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, dev). false = one NAT per AZ (prod)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags. Optional."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
variable "interface_endpoints" {
  description = <<-EOT
    AWS services reached through private interface endpoints instead of NAT, e.g.
    ["ecr.api", "ecr.dkr", "sts", "logs", "ssm", "ssmmessages", "ec2messages"].
    Each costs about $0.013/h per AZ, so dev leaves this empty and prod turns it on.
  EOT
  type        = list(string)
  default     = []
}

variable "flow_logs_retention_days" {
  description = "VPC flow logs to CloudWatch (all traffic, 1-minute aggregation). 0 turns them off."
  type        = number
  default     = 14
}
