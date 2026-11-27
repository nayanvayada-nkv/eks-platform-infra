# Roadmap

| Phase | Goal | Proof / deliverable |
|---|---|---|
| 0 | Foundations: repo, state backend, OIDC, budget alerts, problem statement | Bootstrap applied, CI checks green |
| 1 | (code written) VPC + EKS in Mumbai (dev only): Karpenter, Pod Identity (IRSA available), ALB controller | Cluster up, cost noted |
| 2 | (code written) CI/CD and supply chain: GitHub Actions OIDC, SBOM, Trivy, ECR by digest, Cosign, GitOps repo, Argo CD | Signed image deployed by Argo CD |
| 3 | (code written) Zero Trust in cluster: Istio ambient mTLS + AuthZ, Kyverno image signatures, pod security, NetworkPolicy (secrets moved to Phase 4) | Unsigned image rejected (demo) |
| 4 | (code written) Data and sample app: Aurora Serverless v2, Valkey, Flask app, HPA, IAM logins, ALB -> Istio gateway | App serving traffic |
| 5 | (code written) Edge and security: CloudFront + WAF + internal ALB (VPC origin), optional Route 53/ACM, Shield Standard, GuardDuty, Security Hub, Config, budget | WAF blocking test traffic |
| 6 | (code written) Observability: Prometheus -> AMP, Amazon Managed Grafana, Fluent Bit -> CloudWatch, OTel -> X-Ray, burn-rate SLO alerts | Dashboards + alert test |
| 7 | (code written) Multi-region DR: Frankfurt pilot light (same stacks in a `dr` workspace), Aurora Global DB, ECR + Cosign key replication, drill script | Failover test with measured RTO / RPO |
| 8 | (written) Hardening and proof: load test (Locust), game day (+ AWS FIS templates), cost report, actions pinned by SHA + Dependabot, Checkov blocking in CI (0 failed), bootstrap protection restored, README, interview guide, blog drafts, demo video script | Public write-ups |
| 9 | (code written) Vector DB + RAG: pgvector on Aurora (HNSW, row-level security per tenant), Titan embeddings + Claude on Amazon Bedrock with citations, tenants onboarded by Git PR | Working RAG query on the platform, cost noted |
| FDE | (written) Forward Deployed Engineer track, customer-facing: fictional customer Kestrel Logistics on the RAG API, problem statement, discovery, design, onboarding by PR, demo script, eval set (90% go-live bar), handover, pilot report (docs/fde) | Customer-style demo and write-up |

Cost rule: dev only in Mumbai first. Treat Phase 7 as a temporary demo: build, test, record, destroy.
