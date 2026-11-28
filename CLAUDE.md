# CLAUDE.md

Guidance for Claude (and humans) working in this repo: Zero Trust EKS platform on AWS, Mumbai first.
Target architecture: `docs/architecture.webp`, mapped box by box in `docs/architecture.md`.

## Folder layout

| Path | What lives there |
|---|---|
| `bootstrap/` | One-time stack: Terraform state bucket, state KMS key, GitHub OIDC provider, plan role. Local state first, then migrated into its own bucket. |
| `modules/` | Reusable building blocks (`vpc`, `eks`). No backend, no lock file. |
| `environments/dev/<stack>` | Deployed dev stacks, one state file each: `network` -> `eks` -> `platform`. |
| `environments/shared/<stack>` | Shared, long-lived stacks (`supply-chain`: ECR, Cosign KMS key, build role). |
| `gitops/` | What Argo CD deploys: app-of-apps chart (`clusters/dev`), cluster-wide Zero Trust policies (`platform/zero-trust`) and workloads (Kustomize). |
| `scripts/` | Bash wrappers for Terraform (`tf.sh`, `up-dev.sh`, `destroy-dev.sh`, `check-bootstrap.sh`). |
| `docs/` | Roadmap, ADRs, architecture, runbooks, session logs, study guides. |
| `apps/` | Application source (`backend`), built by `.github/workflows/backend-image.yml`. |

## Decisions

- **Bootstrap stays on and is never destroyed.** Only dev stacks are destroyed to save cost.
  `scripts/destroy-dev.sh` refuses anything outside `environments/dev/`.
  Note: `bootstrap/main.tf` still has `force_destroy = true` / `prevent_destroy = false` on the state
  bucket from an earlier teardown; set them back to `false` / `true` before the next bootstrap apply.
- **Nodes:** a small managed node group (2x t3.medium) runs system pods and Karpenter; Karpenter
  launches app nodes on demand (spot first, CPU limit as the cost guard).
- **No Docker Hub.** Our images live in our ECR; base images come from ECR Public
  (`public.ecr.aws/docker/library/...`). Platform charts use their vendors' own registries
  (registry.istio.io, reg.kyverno.io, public.ecr.aws, registry.k8s.io, quay.io), never docker.io. Apps run on EKS only.
  Kyverno (`restrict-image-registries`) enforces "our ECR only" for workload namespaces.
- **Rollback is a Git revert.** Deploys are digest bumps in `gitops/`; reverting the commit makes
  Argo CD sync the previous signed digest. Nobody runs `kubectl apply` or `kubectl rollout undo` by hand.
- **Security in layers:** network (private subnets, API restricted to one IP, flow logs) -> identity
  (GitHub OIDC, access entries, Pod Identity, IMDSv2 hop 1) -> supply chain (Trivy gate, SBOM, Cosign
  signature with a KMS key, deploy by digest) -> cluster (PSA restricted now; Kyverno, Istio,
  NetworkPolicy as code in Phase 3, ADR 0006) -> data (KMS everywhere).
- **Be honest about status.** Only Phase 0 (bootstrap) has ever been applied to AWS, and that state
  bucket was later destroyed. Phases 1, 2 and 3 exist as code that passes validate, tflint, Checkov,
  actionlint, tests and Trivy, but they have **not** been applied. Never describe them as running or
  proven until the test run in `docs/runbooks/phase1-2-test-run.md` has succeeded.
- Never apply, destroy or call AWS without the user's explicit OK for that step (cost).

## Bash rules

- Use `scripts/tf.sh <stack> <init|plan|apply|destroy>` instead of raw `terraform`. It prints the AWS
  identity first, applies only a saved `tfplan`, and uses the shared backend config.
- Every script starts with `#!/usr/bin/env bash` and `set -euo pipefail`.
- No secrets in scripts, tfvars examples or commits. `backend.hcl`, `*.tfvars` and `tfplan` are git-ignored.
- Never use `-auto-approve`. Applies go through a reviewed plan file; destroys ask for confirmation.
- Quote every variable expansion (`"$VAR"`, `"${ARR[@]}"`).
- Scripts must pass `shellcheck` (also a pre-commit hook).
- Destroy only dev stacks (`environments/dev/*`). Never bootstrap, never `shared/` without an explicit request.

## Working style

- For every file created or changed, explain **what** it does, **why** it exists, and the
  **security reason** behind it. The user is learning this in depth for interviews.
- One command at a time: say what it will do, run it, show the result, then move on.
- Keep `docs/sessions/` updated at the end of a working session.
