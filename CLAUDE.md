# CLAUDE.md

Guidance for Claude (and humans) working in this repo: Zero Trust EKS platform on AWS, Mumbai first.
Target architecture: `docs/architecture.webp`, mapped box by box in `docs/architecture.md`.

## Folder layout

| Path | What lives there |
|---|---|
| `bootstrap/` | One-time stack: Terraform state bucket, state KMS key, GitHub OIDC provider, plan role. Local state first, then migrated into its own bucket. |
| `modules/` | Reusable building blocks (`vpc`, `eks`). No backend, no lock file. |
| `environments/dev/<stack>` | Deployed dev stacks, one state file each: `network` -> `eks` -> `data` -> `edge` -> `observability` -> `platform`. |
| `environments/shared/<stack>` | Shared, long-lived stacks (`supply-chain`: ECR, Cosign KMS key, build role; `security`: GuardDuty, Security Hub, Config, alerts, budget). |
| `gitops/` | What Argo CD deploys: app-of-apps chart (`clusters/dev`), cluster-wide Zero Trust policies (`platform/zero-trust`) and workloads (Kustomize). |
| `scripts/` | Bash wrappers for Terraform (`tf.sh`, `up-dev.sh`, `destroy-dev.sh`, `check-bootstrap.sh`), DR (`up-dr.sh`, `destroy-dr.sh`, `dr-drill.sh`), `grafana-dashboards.sh`, `new-tenant-key.sh`, `fde-load-docs.sh`, `loadtest.sh`, `cost-report.sh`, `render-guides.sh`. |
| `docs/` | Roadmap, ADRs, architecture, runbooks, session logs, FDE engagement (`docs/fde`), in-depth PDF guides (`docs/guides`, sources in `src/*.md`). |
| `apps/` | Application source (`backend`), built by `.github/workflows/backend-image.yml`. |
| `loadtest/` | Locust load test (`scripts/loadtest.sh`), results git-ignored. |

## Decisions

- **Bootstrap stays on and is never destroyed.** Only dev stacks are destroyed to save cost.
  `scripts/destroy-dev.sh` refuses anything outside `environments/dev/`.
  The state bucket has `force_destroy = false` and `prevent_destroy = true` (restored in Phase 8).
- **DR = same stacks, `dr` workspace.** Frankfurt (eu-central-1) is a pilot-light copy: `WORKSPACE=dr scripts/tf.sh ...`
  loads `<stack>/dr.tfvars`. Aurora Global Database and ECR/KMS replication keep data and images there (ADR 0010).
- **RAG tenants live in Git** (`gitops/workloads/backend/tenants`, key hashes only); isolation is PostgreSQL row-level
  security. Claude runs on Amazon Bedrock via the official Anthropic SDK, no API keys (ADR 0011).
- **Nodes:** a small managed node group (2x t3.medium) runs system pods and Karpenter; Karpenter
  launches app nodes on demand (spot first, CPU limit as the cost guard).
- **No Docker Hub.** Our images live in our ECR; base images come from ECR Public
  (`public.ecr.aws/docker/library/...`). Platform charts use their vendors' own registries
  (registry.istio.io, reg.kyverno.io, public.ecr.aws, registry.k8s.io, quay.io), never docker.io. Apps run on EKS only.
  Kyverno (`restrict-image-registries`) enforces "our ECR only" for workload namespaces.
- **Rollback is a Git revert.** Deploys are digest bumps in `gitops/`; reverting the commit makes
  Argo CD sync the previous signed digest. Nobody runs `kubectl apply` or `kubectl rollout undo` by hand.
- **Security in layers:** edge (CloudFront + WAF, ALB internal only, ADR 0008) -> network (private subnets, API restricted to one IP, flow logs) -> identity
  (GitHub OIDC, access entries, Pod Identity, IMDSv2 hop 1) -> supply chain (Trivy gate, SBOM, Cosign
  signature with a KMS key, deploy by digest) -> cluster (PSA restricted now; Kyverno, Istio,
  NetworkPolicy as code in Phase 3, ADR 0006) -> data (KMS everywhere; apps log in with IAM tokens, no passwords, ADR 0007).
- **Be honest about status.** First real AWS run on 28 Nov 2026 (`docs/sessions/2026-11-28-run-day-1.md`):
  Phases 0-4 proven live (signed deploy, unsigned image refused, app serving from Aurora/Valkey with IAM
  logins); Phases 5-6 partly (security stack, WAF, AMP up; CloudFront blocked pending AWS account
  verification; Managed Grafana unavailable in Mumbai). Phases 7-9 and the FDE eval are code only, not
  yet run. At the end of the day every stack, bootstrap included, was destroyed at the owner's request
  (account empty of this project). Never claim more than this.
- Never apply, destroy or call AWS without the user's explicit OK for that step (cost).

## Bash rules

- Use `scripts/tf.sh <stack> <init|plan|apply|destroy>` instead of raw `terraform`. It prints the AWS
  identity first, applies only a saved `tfplan`, and uses the shared backend config.
- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- No secrets in scripts, tfvars examples or commits. `backend.hcl`, `*.tfvars` and `tfplan` are git-ignored.
- Never use `-auto-approve`. Applies go through a reviewed plan file; destroys ask for confirmation.
- Quote every variable expansion (`"$VAR"`, `"${ARR[@]}"`).
- Scripts must pass `shellcheck` (also a pre-commit hook).
- Local check tools must not come from Docker Hub either: use `ghcr.io/bridgecrewio/checkov`, `ghcr.io/aquasecurity/trivy`,
  `ghcr.io/terraform-linters/tflint`, `ghcr.io/kyverno/kyverno-cli`, or pip/binary installs.
- GitHub Actions are pinned by commit SHA (comment = version); Dependabot proposes updates.
- Destroy only dev stacks (`environments/dev/*`, either workspace). Never bootstrap, never `shared/` without an explicit request.

## Working style

- For every file created or changed, explain **what** it does, **why** it exists, and the
  **security reason** behind it. The user is learning this in depth for interviews.
- One command at a time: say what it will do, run it, show the result, then move on.
- Keep `docs/sessions/` updated at the end of a working session.
