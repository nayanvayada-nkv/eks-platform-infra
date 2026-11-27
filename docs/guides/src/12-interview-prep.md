# Interview Prep: Zero Trust EKS Platform

<div class="cover" markdown>
<p class="sub">Pitch, honest framing, questions by topic with short and deep answers, company-scale differences.</p>
<span class="status">Fill the [measure] numbers after the AWS run</span>
</div>

## 1. Framing (read this first)
Present it as **a personal project** you designed and built end to end, under *Projects*, not as job
experience. Claim only what you ran: "built and validated as code; [X] proven on AWS on [date]". Honest
framing survives deep follow-up questions; invented experience does not.

## 2. The 60-second pitch
"I built a Zero Trust platform on EKS in Mumbai with a pilot-light copy in Frankfurt, all in Terraform and
GitOps. Only images my pipeline built can run: Trivy gate, SBOM, Cosign signature with a KMS key, deploy
by digest through a pull request, verified by Kyverno at admission. Inside the cluster: Istio ambient mTLS,
default-deny NetworkPolicy, Pod Security restricted. Apps use IAM tokens, no passwords. Traffic enters only
via CloudFront and WAF to an internal ALB. SLOs with burn-rate alerts, a multi-tenant RAG API on pgvector
and Bedrock with row-level security, and I measured [load test RPS] and a DR drill with RTO [x], RPO [y]."

## 3. Questions by topic

### Kubernetes and EKS
**Why Karpenter?** Picks instance types per pending pods, spot first, consolidates; CPU cap as cost guard.

**Liveness vs readiness?** Liveness restarts; readiness removes from traffic. Dependencies only in readiness.

**How do pods get AWS permissions?** Pod Identity association per service account; IMDSv2 hop 1 blocks node credentials.

### Security
**What does Zero Trust mean here?** Every hop authenticates and authorizes: WAF, mTLS identities, NetworkPolicy, IAM per pod, RLS per tenant.

**How do you block an unsigned image?** Kyverno ImageValidatingPolicy with the Cosign KMS key; fail closed.

**Where are the secrets?** Almost none: IAM tokens for data, Pod Identity for Bedrock, admin password write-only and only for the migrate Job.

### CI/CD and GitOps
**Push vs pull deploys?** Pull (Argo CD) keeps cluster credentials out of CI and fixes drift.

**Rollback?** `git revert` of the digest commit; Argo CD syncs the previous signed digest.

**Why pin actions by SHA?** Tags move; a hijacked tag could run in the pipeline that signs images.

### Data
**Why IAM auth for Aurora?** 15-minute tokens tied to the pod identity; no password to rotate or leak.

**Why Serverless v2 at 0 ACU?** Idle dev costs almost nothing; note global databases cannot pause.

### Observability and reliability
**SLI, SLO, SLA?** Measurement, target, contract.

**Why burn-rate alerts?** Urgency proportional to budget impact; fewer false pages.

**RTO/RPO of your DR?** Planned switchover RPO 0, RTO [measure]; pilot-light total includes build time [measure].

### AI / RAG
**Why pgvector?** Reuse the secured, replicated database; exit to OpenSearch at large scale.

**Prompt injection?** Documents as data blocks, system prompt, citations, refusal alerts.

**Quality?** Eval set with a 90% go-live bar.

## 4. Stories that show judgement (STAR format)
| Situation | Action | Result |
|---|---|---|
| Kustomize override for DR | Tested the render, saw the digest was dropped | Layered overlay; Kyverno would otherwise block DR |
| NetworkPolicy selectors rewritten | Read rendered output, not just the source | Avoided a cluster-wide DNS outage |
| Action tag did not exist | Pinned every action by SHA | First publish would have failed at signing |
| Image missing `rag.py` | Import check inside the built image | Test the artifact you ship |

## 5. At company scale I would change...
Multi-account (Organizations, SCPs), SSO only, staging and prod with promotion gates, warm standby for
tier-1, central logging and security accounts with a SIEM, PagerDuty on-call and postmortems, FinOps
tagging and showback, policy exceptions with expiry, Kyverno with 3 replicas.

## 6. Numbers to fill (keep honest)
| Metric | Value | Date |
|---|---|---|
| Cluster build time | | |
| Run-day cost | | |
| Max RPS within SLO | | |
| HPA / Karpenter reaction | | |
| DR RTO (db / app), RPO | | |
| RAG eval score | | |
