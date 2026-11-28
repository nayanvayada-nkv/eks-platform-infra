# eks-platform-infra

Infrastructure as code for a secure, multi-region Kubernetes platform on AWS.

**What it does:** provisions EKS, networking and data layers with Terraform, delivers workloads
through Argo CD (GitOps), and only admits container images that are scanned, signed and verified.
Mumbai is primary, with a lean active-passive DR region.

**Status:** Phases 1 to 5 written and validated, not applied yet. Diagram and per-box status: [docs/architecture.md](docs/architecture.md). See [docs/roadmap.md](docs/roadmap.md).

## Repo layout

| Path | Purpose |
|---|---|
| `bootstrap/` | One-time stack: state bucket, KMS key, GitHub OIDC provider and plan role |
| `modules/` | Reusable, versioned building blocks (network, eks, ecr, data, edge, ...) |
| `environments/` | Deployed stacks per environment (`dev/network`, `dev/eks`, `dev/platform`), one state file each |
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

## Phase 1: dev network, EKS and platform add-ons

Three stacks, applied in order. Each has its own state file in the bootstrap bucket.

| Stack | What it creates |
|---|---|
| `environments/dev/network` | VPC 10.20.0.0/16, 3 public + 3 private subnets, 1 NAT gateway, S3 gateway endpoint |
| `environments/dev/eks` | EKS cluster (secrets encrypted with KMS, API restricted to your IP), 2x t3.medium system nodes, managed add-ons (VPC CNI, CoreDNS, kube-proxy, Pod Identity agent, EBS CSI), Karpenter IAM + SQS queue, Load Balancer Controller IAM role |
| `environments/dev/platform` | Helm: AWS Load Balancer Controller, metrics-server (for HPA), Karpenter, plus a default `EC2NodeClass` and `NodePool` (spot first, capped at 16 vCPU) |

Approximate cost while running (ap-south-1): EKS control plane ~$0.10/h, NAT gateway ~$0.056/h plus data,
2x t3.medium ~$0.09/h, plus any Karpenter nodes. Roughly **$6-7/day**. Destroy when not in use.

```bash
cp environments/backend.hcl.example environments/backend.hcl   # set your bucket name
cp environments/dev/eks/terraform.tfvars.example environments/dev/eks/terraform.tfvars  # set your IP

cd environments/dev/network  && terraform init -backend-config=../../backend.hcl && terraform plan
cd ../eks                    && terraform init -backend-config=../../backend.hcl && terraform plan
cd ../platform               && terraform init -backend-config=../../backend.hcl && terraform plan
```

Apply in the same order (network, eks, platform). Destroy in reverse order (platform, eks, network),
and delete any Ingress / LoadBalancer Services first so the controller removes its ALBs.

## Phase 2: supply chain (build, scan, sign, deploy by digest)

| Piece | Where |
|---|---|
| ECR repos (immutable tags, scan on push, lifecycle, optional DR replication), Cosign KMS key, GitHub build role | `environments/shared/supply-chain` |
| Sample backend (Flask, non-root, read-only filesystem) | `apps/backend` |
| Pipeline: test, build, Trivy gate, SBOM, push, Cosign sign + attest, GitOps PR | `.github/workflows/backend-image.yml` |
| Argo CD + root app (app of apps) | `environments/dev/platform/argocd.tf`, `gitops/clusters/dev` |
| Backend manifests (PSA restricted, HPA, probes, digest-pinned) | `gitops/workloads/backend` |

Cost: ECR storage cents, Cosign KMS key $1/month. Argo CD runs on the existing cluster.

```bash
cp environments/shared/supply-chain/terraform.tfvars.example environments/shared/supply-chain/terraform.tfvars  # set github_org
cp environments/dev/platform/terraform.tfvars.example environments/dev/platform/terraform.tfvars                # set gitops_repo_url
cd environments/shared/supply-chain && terraform init -backend-config=../../backend.hcl && terraform plan
```

One-time GitHub setup (Settings of this repo):

1. Actions > Variables: `AWS_BUILD_ROLE_ARN` = output `github_build_role_arn`.
2. Actions > General > Workflow permissions: allow GitHub Actions to create pull requests.
3. If the repo is private, give Argo CD read access (a deploy key or a read-only token as an Argo CD repository secret).

Flow: merge to `main` under `apps/backend/` -> image built, scanned, pushed, signed -> a PR updates the digest in
`gitops/workloads/backend/overlays/dev` -> merging that PR is the deploy approval -> Argo CD syncs.
