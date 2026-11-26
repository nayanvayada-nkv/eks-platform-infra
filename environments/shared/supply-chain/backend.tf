terraform {
  backend "s3" {
    key = "shared/ap-south-1/supply-chain/terraform.tfstate"
    # bucket, region, encryption: supplied at init: terraform init -backend-config=../../backend.hcl
  }
}
