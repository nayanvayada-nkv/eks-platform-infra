terraform {
  backend "s3" {
    key = "nonprod/dev/ap-south-1/network/terraform.tfstate"
    # bucket, region, encryption: supplied at init: terraform init -backend-config=../../backend.hcl
  }
}