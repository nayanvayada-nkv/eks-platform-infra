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

  # S3 gateway endpoint is free. Interface endpoints (~$0.013/hour per AZ each) keep these AWS
  # calls inside the VPC, so the backend NetworkPolicy never needs internet egress:
  #   secretsmanager  (Phase 4) db-migrate reads the Aurora admin secret
  #   bedrock-runtime (Phase 9) Titan embeddings
  #   bedrock-mantle  (Phase 9) Claude via the Messages API on Bedrock
  # Dev is destroyed after each run. Prod: add ecr.api, ecr.dkr, sts, logs, ssm.
  interface_endpoints = ["secretsmanager", "bedrock-runtime", "bedrock-mantle"]
}