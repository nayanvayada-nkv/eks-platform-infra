# Demo video script (8-10 minutes)

1. **Intro (30 s).** "A Zero Trust EKS platform on AWS: Mumbai primary, Frankfurt DR, built as code.
   I'll show deploy, security, data, edge, observability, AI and recovery, with evidence."
2. **Architecture (60 s).** `docs/architecture.webp`, then the layer list in CLAUDE.md.
3. **GitOps deploy (90 s).** Merge a backend change -> pipeline (Trivy, SBOM, Cosign) -> auto PR with
   the digest -> merge -> Argo CD sync. Point at `image@sha256`.
4. **Zero Trust (90 s).** Unsigned image refused; Docker Hub image refused; namespace without labels
   refused; cross-namespace call blocked; ztunnel mTLS metric.
5. **Edge (60 s).** CloudFront URL works; XSS/SQLi/Log4j probes get 403; the ALB has no public address.
6. **Data + AI (90 s).** Upload an SOP, ask a question, show citations; another tenant sees nothing;
   prompt-injection document is reported, not obeyed.
7. **Observability (60 s).** SLO dashboard, X-Ray trace with Aurora/Valkey/Bedrock spans, alert email.
8. **Resilience (60 s).** Load test result (max RPS within SLO) and DR drill output (RTO/RPO).
9. **Close (30 s).** What I would do differently in a company (multi-account, SSO, warm standby).
