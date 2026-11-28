# After the first apply, rename to backend.tf, fill in the bucket name from
# `terraform output state_bucket`, then run: terraform init -migrate-state
terraform {
  backend "s3" {
    bucket       = "eks-platform-tfstate-464243369696-ap-south-1"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    kms_key_id   = "alias/eks-platform-tfstate"
    use_lockfile = true
  }
}
