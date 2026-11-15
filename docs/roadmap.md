# Roadmap

| Phase | Goal | Proof / deliverable |
|---|---|---|
| 0 | Foundations: repo, state backend, OIDC, budget alerts, problem statement | Bootstrap applied, CI checks green |
| 1 | VPC + EKS in Mumbai (dev only): Karpenter, IRSA, ALB controller | Cluster up, cost noted |
| 2 | CI/CD and supply chain: GitHub Actions OIDC, SBOM, Trivy, ECR by digest, Cosign, GitOps repo, Argo CD | Signed image deployed by Argo CD |
| 3 | Zero Trust in cluster: Istio mTLS + AuthZ, Kyverno verifyImages, pod security, NetworkPolicy, secrets | Unsigned image rejected (demo) |
| 4 | Data and sample app: Aurora, Redis, Flask app, HPA | App serving traffic |
| 5 | Edge and security: Route 53, CloudFront, WAF, Shield, GuardDuty, Security Hub | WAF blocking test traffic |
| 6 | Observability: Prometheus, Grafana, logs, tracing, alerts, SLOs | Dashboards + alert test |
| 7 | Multi-region DR: one lean DR region, Aurora Global DB, ECR replication | Failover test with measured RTO / RPO |
| 8 | Hardening and proof: game day, cost report, README, demo video, blog posts | Public write-ups |
| 9 | Future: vector DB / RAG (planned, not built) | n/a |

Cost rule: dev only in Mumbai first. Treat Phase 7 as a temporary demo: build, test, record, destroy.
