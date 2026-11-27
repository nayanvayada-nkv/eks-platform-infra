# In-depth guides (PDF)

Written for learning and interviews: each starts with a real-life example (QuickCart, a fictional
shopping + food delivery app), then simple words, then the technical depth, security reasons, bugs we
caught, a glossary and self-test questions. Dashed **Evidence** boxes are filled after the AWS run.

| PDF | Topic |
|---|---|
| [00-architecture](pdf/00-architecture.pdf) | All diagrams with plain explanations (start here) |
| [01-foundation-network-eks](pdf/01-foundation-network-eks.pdf) | Phase 0 + 1: state, OIDC, VPC, EKS, Karpenter, Pod Identity |
| [02-supply-chain](pdf/02-supply-chain.pdf) | Phase 2: Trivy, SBOM, Cosign + KMS, GitOps, Argo CD |
| [03-zero-trust-cluster](pdf/03-zero-trust-cluster.pdf) | Phase 3: Kyverno, Istio ambient, NetworkPolicy |
| [04-data-and-app](pdf/04-data-and-app.pdf) | Phase 4: Aurora, Valkey, IAM logins, migrations |
| [05-edge-and-account-security](pdf/05-edge-and-account-security.pdf) | Phase 5: CloudFront, WAF, internal ALB, GuardDuty, Security Hub |
| [06-observability](pdf/06-observability.pdf) | Phase 6: AMP, Grafana, logs, traces, SLO burn-rate alerts |
| [07-disaster-recovery](pdf/07-disaster-recovery.pdf) | Phase 7: pilot light, Aurora Global DB, drill |
| [08-hardening-and-proof](pdf/08-hardening-and-proof.pdf) | Phase 8: load test, game days, hardening |
| [09-rag-vector-db](pdf/09-rag-vector-db.pdf) | Phase 9: pgvector, Bedrock, row-level security, how to enable |
| [10-fde-track](pdf/10-fde-track.pdf) | Forward Deployed Engineer engagement |
| [11-use-cases](pdf/11-use-cases.pdf) | Real-world use cases mapped to phases |
| [12-interview-prep](pdf/12-interview-prep.pdf) | Pitch, Q&A by topic, STAR stories, company-scale differences |

The older [Phase 1 guide](Phase1-InDepth-Guide.pdf) is kept; `01-foundation-network-eks` replaces it.

Rebuild after editing `src/*.md` or `src/diagram_specs.py`:
`pip install markdown` then `scripts/render-guides.sh [name ...]` (Chrome headless).
