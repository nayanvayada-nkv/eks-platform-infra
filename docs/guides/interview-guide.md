# Interview guide: talking about this project

## Framing (be accurate)
"A personal project: a production-grade Zero Trust platform on EKS that I designed and built end to
end, and tested on AWS." List it under **Projects**, not as employment. Claim only what you ran:
until the test run succeeds, say "built and validated as code; [X] proven on AWS on [date]".

## 60-second pitch
"It's a Zero Trust EKS platform in Mumbai with a Frankfurt DR copy, all Terraform and GitOps.
Only images built by my pipeline can run: Trivy gate, SBOM, Cosign signature with a KMS key, deploy by
digest through a pull request, and Kyverno verifies at admission. Inside the cluster there's Istio
ambient mTLS, default-deny NetworkPolicy and Pod Security restricted. Apps use IAM tokens, no
passwords, for Aurora and Valkey. Traffic enters only through CloudFront and WAF to an internal ALB.
I run SLOs with burn-rate alerts in Managed Prometheus and Grafana, a multi-tenant RAG API on pgvector
and Bedrock with row-level security, and I measured [load test RPS] and a DR drill with RTO [x] / RPO [y]."

## Likely questions, short answers (with where to point)
| Question | Answer in one breath | Evidence |
|---|---|---|
| Why Pod Identity over IRSA? | No OIDC trust policy per role, simpler association API, session tags; IRSA kept for tools that need it | ADR 0004 |
| How do you stop an unsigned image? | Kyverno ImageValidatingPolicy: our ECR, digest, Cosign KMS signature + signed SBOM; fails closed | ADR 0006 |
| What if Kyverno is down? | `failurePolicy: Fail` blocks new pods in app namespaces; running pods continue; prod runs 3 replicas | game day #5 |
| Why Istio ambient, not sidecars? | No per-pod proxy cost; sidecar init needs NET_ADMIN, which breaks PSA restricted; Jobs finish normally | ADR 0006 |
| How does traffic reach pods with strict mTLS? | CloudFront -> WAF -> internal ALB (VPC origin) -> Istio gateway -> HBONE mTLS -> pod | ADR 0007/0008 |
| Why is the ALB internal? | So the WAF cannot be bypassed: there is no public address to call | ADR 0008 |
| Secrets? | Apps hold none: IAM tokens for Aurora/Valkey, Bedrock via Pod Identity; admin password ephemeral + write-only, never in state | ADR 0007/0010 |
| How do you deploy and roll back? | CI opens a digest PR; merge = deploy; git revert = rollback; nobody runs kubectl apply | ADR 0005 |
| How do you know it's healthy? | SLO 99.5% / p95 500 ms; multi-window burn-rate alerts, unit-tested with promtool | ADR 0009 |
| Multi-tenancy for RAG? | API key -> tenant; PostgreSQL FORCE'd row-level security; tenants onboarded by PR | ADR 0011 |
| Prompt injection? | Retrieved text as document blocks, system prompt treats it as data, citations, refusal metrics | ADR 0011 |
| DR strategy and numbers? | Pilot light; Aurora Global DB headless secondary; same code in a `dr` workspace; RTO [x] RPO [y] | ADR 0010 |
| Cost control? | Destroy dev daily, Aurora to 0 ACU, Karpenter CPU cap, spot, AMP keep-list, budget alert | cost report |
| Biggest bug you caught? | Kustomize image override dropped the digest (Kyverno would block DR); `includeSelectors` rewrote NetworkPolicy selectors (would have blocked DNS); a missing action tag would have broken CI | session logs |
| What would you change at a company? | Multi-account (Organizations, SCPs), SSO, staging + prod with promotion, warm standby for tier-1, central security account | below |

## At company scale I would...
Separate accounts per environment with SCPs; Identity Center/SSO only; staging and prod with promotion
gates; warm standby or active-active for tier-1 services; central logging/security accounts and a SIEM;
on-call with PagerDuty and postmortems; FinOps tagging and showback; policy exceptions with expiry.

## Numbers to fill after the run (keep this table honest)
| Metric | Value | Date |
|---|---|---|
| Cluster up (network+eks+platform) time | | |
| Cost of the test day | | |
| Max RPS within SLO (load test) | | |
| HPA / Karpenter scale-out time | | |
| DR switchover RTO (db / app) and RPO | | |
| RAG eval score (FDE) | | |
