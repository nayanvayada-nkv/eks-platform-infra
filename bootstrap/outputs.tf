output "state_bucket" {
  description = "S3 bucket for Terraform remote state."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "KMS key encrypting the state bucket."
  value       = aws_kms_key.state.arn
}

output "github_plan_role_arn" {
  description = "Set this as the GitHub repo variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.github_plan.arn
}
