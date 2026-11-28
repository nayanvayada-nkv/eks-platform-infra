# eks-platform-infra

A Zero Trust Kubernetes platform on AWS, built as code: EKS in Mumbai (ap-south-1) with a pilot-light
disaster-recovery copy in Frankfurt (eu-central-1). Terraform for infrastructure, Argo CD for everything
running in the cluster, and a supply chain where only scanned, signed images can run.

> **Status (honest):** Phases 0-9 and the FDE track are written and pass local checks (terraform
> validate, tflint, Checkov 0 failed, actionlint, shellcheck, unit tests, Trivy, Kyverno CLI, promtool).
> Only Phase 0 has ever been applied to AWS. Nothing else is proven on AWS until the test run in
> [docs/runbooks/phase1-2-test-run.md](docs/runbooks/phase1-2-test-run.md) succeeds.

Full architecture as built: [docs/architecture-full.png](docs/architecture-full.png). Original target diagram: [docs/architecture.webp](docs/architecture.webp), mapped box by box in
[docs/architecture.md](docs/architecture.md). Plan and status: [docs/roadmap.md](docs/roadmap.md).

## What is in it

| Layer | What | Decision record |
|---|---|---|
| Edge | CloudFront + WAF (OWASP, Log4j, SQLi, rate limit) -> internal ALB via VPC origin; Shield Standard | [ADR 0008](docs/adr/0008-edge-and-account-security.md) |
| Network | Private subnets, 1 NAT, VPC endpoints (S3, Secrets Manager, Bedrock), flow logs, API restricted to one IP | Phase 1 |
| Identity | GitHub OIDC (no keys in CI), EKS access entries, Pod Identity, IMDSv2 hop 1 | [ADR 0004](docs/adr/0004-pod-identity-over-irsa.md) |
| Supply chain | Trivy gate, SPDX SBOM, Cosign signature with a KMS key, deploy by digest via PR, actions pinned by SHA | [ADR 0005](docs/adr/0005-supply-chain-signing-and-gitops-pr.md) |
| Cluster | Kyverno CEL policies (signed images only), Istio ambient mTLS + AuthZ, default-deny NetworkPolicy, PSA restricted | [ADR 0006](docs/adr/0006-zero-trust-in-cluster.md) |
| Data | Aurora PostgreSQL Serverless v2, Valkey serverless, IAM-token logins (no passwords), KMS | [ADR 0007](docs/adr/0007-data-layer-and-ingress.md) |
| Observability | Prometheus -> Amazon Managed Prometheus, Managed Grafana, Fluent Bit -> CloudWatch, OTel -> X-Ray, SLO burn-rate alerts | [ADR 0009](docs/adr/0009-observability.md) |
| DR | Pilot light: Aurora Global Database, ECR + KMS replication, same stacks in a `dr` workspace, measured drill | [ADR 0010](docs/adr/0010-pilot-light-dr-frankfurt.md) |
| AI | Multi-tenant RAG: pgvector (HNSW, row-level security), Titan embeddings, Claude on Amazon Bedrock with citations | [ADR 0011](docs/adr/0011-rag-pgvector-bedrock.md) |
| Account security | GuardDuty, Security Hub, AWS Config, alert email, $10 budget | [ADR 0008](docs/adr/0008-edge-and-account-security.md) |

Customer story on top of it: [Forward Deployed Engineer track](docs/fde/README.md) (fictional customer).

## Layout

| Path | Purpose |
|---|---|
| `bootstrap/` | State bucket, state KMS key, GitHub OIDC provider, plan role (never destroyed) |
| `modules/` | `vpc`, `eks` |
| `environments/dev/*` | `network` -> `eks` -> `data` -> `edge` -> `observability` -> `platform` (+ optional `chaos`); `dr` workspace = Frankfurt |
| `environments/shared/*` | `supply-chain` (ECR, Cosign key, build role), `security` (GuardDuty, Security Hub, Config, alerts, budget) |
| `gitops/` | Argo CD app of apps, platform charts (Kyverno policies, observability, ingress), backend Kustomize |
| `apps/backend` | Flask API: items, RAG, metrics, traces |
| `loadtest/` | Locust load test |
| `scripts/` | `tf.sh` and up/destroy/DR/drill/load-test/cost helpers (shellcheck-clean) |
| `docs/` | ADRs, runbooks, roadmap, FDE track, interview guide, blog drafts, session logs |

## Run it (every apply needs a reviewed plan; costs money)

```bash
cp environments/backend.hcl.example environments/backend.hcl   # state bucket from bootstrap
scripts/check-bootstrap.sh                                      # state bucket and key exist
scripts/up-dev.sh                                               # plan + confirm each dev stack
scripts/destroy-dev.sh                                          # reverse order, typed confirmation
```

Step-by-step with checks: [test run](docs/runbooks/phase1-2-test-run.md), [DR drill](docs/runbooks/phase7-dr-drill.md),
[load test](docs/runbooks/load-test.md), [game day](docs/runbooks/game-day.md). Expected costs:
[docs/cost-report.md](docs/cost-report.md) (dev is about $6-7 per day while running; destroy after use).

Rules for working in this repo (also for AI assistants): [CLAUDE.md](CLAUDE.md).
