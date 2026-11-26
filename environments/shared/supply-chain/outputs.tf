output "registry" {
  description = "ECR registry host."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "github_build_role_arn" {
  description = "Set as the GitHub repo variable AWS_BUILD_ROLE_ARN."
  value       = aws_iam_role.github_build.arn
}

output "cosign_key_ref" {
  description = "Key reference for cosign sign / verify."
  value       = "awskms:///${aws_kms_alias.cosign.name}"
}

output "cosign_public_key_pem" {
  description = "Public key Kyverno uses to verify image signatures (Phase 3). Not secret."
  value       = data.aws_kms_public_key.cosign.public_key_pem
}
