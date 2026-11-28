data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source = "../../../modules/vpc"

  name         = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-${var.environment}"
  cidr_block   = var.vpc_cidr
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)

  # Subnets derived from the VPC range: /24 public, /20 private, one per AZ.
  public_subnet_cidrs  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(1, 4) : cidrsubnet(var.vpc_cidr, 4, i)]

  single_nat_gateway = true

  # S3 gateway endpoint is free. Secrets Manager (Phase 4): the db-migrate job reads the Aurora
  # admin secret over a private endpoint, so its NetworkPolicy needs no internet egress
  # (~$0.04/hour for 3 AZs; dev is destroyed after each run). Prod: add ecr.api, ecr.dkr, sts, logs, ssm.
  interface_endpoints = ["secretsmanager"]
}