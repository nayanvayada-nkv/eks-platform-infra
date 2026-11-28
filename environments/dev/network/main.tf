data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../../modules/vpc"

  name         = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-${var.environment}"
  cidr_block   = "10.20.0.0/16"
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)

  public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
  private_subnet_cidrs = ["10.20.16.0/20", "10.20.32.0/20", "10.20.48.0/20"]

  single_nat_gateway = true

  # Dev: S3 gateway endpoint only (free). Prod: add ecr.api, ecr.dkr, sts, logs, ssm, ...
  interface_endpoints = []
}