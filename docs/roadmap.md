# Roadmap

| Phase | Goal | Proof / deliverable |
|---|---|---|
| 0 | Foundations: repo, state backend, OIDC, budget alerts, problem statement | Bootstrap applied, CI checks green |
| 1 | (code written) VPC + EKS in Mumbai (dev only): Karpenter, Pod Identity (IRSA available), ALB controller | Cluster up, cost noted |
| 2 | (code written) CI/CD and supply chain: GitHub Actions OIDC, SBOM, Trivy, ECR by digest, Cosign, GitOps repo, Argo CD | Signed image deployed by Argo CD |
| 3 | (code written) Zero Trust in cluster: Istio ambient mTLS + AuthZ, Kyverno image signatures, pod security, NetworkPolicy (secrets moved to Phase 4) | Unsigned image rejected (demo) |
| 4 | (code written) Data and sample app: Aurora Serverless v2, Valkey, Flask app, HPA, IAM logins, ALB -> Istio gateway | App serving traffic |
| 5 | (code written) Edge and security: CloudFront + WAF + internal ALB (VPC origin), optional Route 53/ACM, Shield Standard, GuardDuty, Security Hub, Config, budget | WAF blocking test traffic |
| 6 | Observability: Prometheus, Grafana, logs, tracing, alerts, SLOs | Dashboards + alert test |
| 7 | Multi-region DR: one lean DR region, Aurora Global DB, ECR replication | Failover test with measured RTO / RPO |
| 8 | Hardening and proof: game day, cost report, README, demo video, blog posts | Public write-ups |
| 9 | Vector DB + RAG (in scope, will be built): tenant-filtered semantic search, private endpoint + KMS. Option to decide: pgvector vs OpenSearch vs Qdrant | Working RAG query on the platform, cost noted |
| FDE | Forward Deployed Engineer track (runs alongside phases 4 to 9, meaning to confirm): customer problem statement, discovery notes, onboard a "customer" tenant, customer-facing RAG use case, demo + runbook + handover | Customer-style demo and write-up |

Cost rule: dev only in Mumbai first. Treat Phase 7 as a temporary demo: build, test, record, destroy.
