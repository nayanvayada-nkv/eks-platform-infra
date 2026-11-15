# eks-platform-infra

Infrastructure as code for a secure, multi-region Kubernetes platform on AWS.

**What it does:** provisions EKS, networking and data layers with Terraform, delivers workloads
through Argo CD (GitOps), and only admits container images that are scanned, signed and verified.
Mumbai is primary, with a lean active-passive DR region.

**Status:** Phase 0 (foundations) in progress. See [docs/roadmap.md](docs/roadmap.md).

## Repo layout

| Path | Purpose |
|---|---|
| `bootstrap/` | One-time stack: state bucket, KMS key, GitHub OIDC provider and plan role |
| `modules/` | Reusable, versioned building blocks (network, eks, ecr, data, edge, ...) |
| `live/` | Deployed stacks per environment and region, one state file each |
| `gitops/` | Argo CD apps, Helm/Kustomize, Kyverno policies (may move to its own repo) |
| `policies/` | Custom Checkov / OPA / Kyverno rules |
| `docs/` | Roadmap, architecture diagrams, decision records (ADRs) |

## Phase 0: run the bootstrap

Prerequisites: Terraform >= 1.10, AWS CLI with a working profile (`aws sts get-caller-identity`).

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # set github_org
terraform init
terraform plan
terraform apply
```

Then:

1. Copy the outputs. In GitHub: Settings > Secrets and variables > Actions > Variables, add
   `AWS_PLAN_ROLE_ARN` = the `github_plan_role_arn` output.
2. Move the bootstrap state into the new bucket: rename `backend.tf.example` to `backend.tf`,
   fill in the bucket name, run `terraform init -migrate-state`. Then delete the local `*.tfstate`.
3. Enable the hooks: `pre-commit install`.

Never commit `terraform.tfvars`, state files or access keys.
