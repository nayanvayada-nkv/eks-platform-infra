data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# One private repository per service image.
# Immutable tags: a tag can never be re-pointed to different content, and
# deployments pin the digest anyway (GitOps writes image@sha256:...).
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  #checkov:skip=CKV_AWS_51:Release tags are immutable; only Cosign sha256-* signature/attestation tags are excluded
  for_each = toset(var.repositories)

  name         = "${var.project}/${each.value}"
  force_delete = var.force_delete_repositories

  # Release tags (git SHA) are immutable. Cosign stores signatures and attestations
  # under tags like sha256-<digest>.sig / .att and must be able to update them
  # (re-sign, add an attestation), so those tags are excluded.
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  image_tag_mutability_exclusion_filter {
    filter      = "sha256-*"
    filter_type = "WILDCARD"
  }

  # Basic scanning is free. Trivy in CI is the blocking gate; this is a second
  # opinion that keeps re-checking stored images.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS" # AWS-managed aws/ecr key
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged layers/manifests after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the newest tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_image_count
        }
        action = { type = "expire" }
      },
    ]
  })
}

# Registry-wide: copy every <project>/* image to the DR regions (diagram: "replicated to DR").
resource "aws_ecr_replication_configuration" "this" {
  count = length(var.replication_regions) > 0 ? 1 : 0

  replication_configuration {
    rule {
      dynamic "destination" {
        for_each = var.replication_regions
        content {
          region      = destination.value
          registry_id = data.aws_caller_identity.current.account_id
        }
      }

      repository_filter {
        filter      = var.project
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# Repositories that replication creates in the DR region get the same protections as the
# originals (otherwise they would be created with mutable tags and no scanning).
resource "aws_ecr_repository_creation_template" "replication" {
  count                = length(var.replication_regions) > 0 ? 1 : 0
  prefix               = var.project
  description          = "Settings for replicated ${var.project}/* repositories in DR regions"
  applied_for          = ["REPLICATION"]
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "sha256-*" # Cosign signature / attestation tags
    filter_type = "WILDCARD"
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}
