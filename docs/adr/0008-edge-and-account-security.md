# ADR 0008: Edge (CloudFront + WAF + private ALB) and account-level threat detection

- Status: accepted (code written 27 Nov 2026, not applied)
- Context: Phase 5 (Route 53, CloudFront, WAF, Shield, GuardDuty, Security Hub). Proof: "WAF blocking
  test traffic". Phase 4 had a public ALB limited to one IP, over HTTP.
- Decisions:
  1. **The ALB becomes internal; CloudFront reaches it through a VPC origin.** The load balancer has no
     public address at all, and its security group accepts only CloudFront's VPC-origin interfaces.
     Bypassing the WAF by calling the ALB directly is impossible, not just forbidden.
  2. **Terraform owns the ALB; Kubernetes only binds targets** (`TargetGroupBinding`). CloudFront needs
     the ALB's ARN at creation time, which a Kubernetes-created ALB would only have later.
  3. **WAF rules:** AWS IP reputation, Common Rule Set (OWASP-style XSS, LFI, bad bots...), Known Bad
     Inputs (Log4j), SQL injection, and a per-IP rate limit (100/min). In dev an IP allow-list
     (your IP) blocks everyone else first. WAF logs redact `authorization` and `cookie`.
  4. **Domain optional.** Without one, viewers use `https://<id>.cloudfront.net` with CloudFront's
     certificate. With `domain_name`, an ACM certificate (us-east-1, DNS-validated in Route 53),
     TLS 1.2+ policy and alias records are created. The CloudFront -> ALB hop is HTTP on the AWS network
     (TLS on that hop needs a certificate for a domain we own).
  5. **Shield Standard** (automatic, free) covers L3/L4 DDoS. Shield Advanced ($3,000/month) is out of
     scope for this project; the WAF rate rule covers L7 floods.
  6. **GuardDuty, Security Hub, AWS Config and the budget live in `environments/shared/security`**, not
     in dev: they are per account and region. GuardDuty watches the EKS audit log; Runtime Monitoring is
     a switch (off by default) because its managed VPC endpoint blocks deleting the dev VPC.
     Security Hub runs AWS Foundational Security Best Practices; Config records daily to keep cost low.
     HIGH/CRITICAL GuardDuty and CRITICAL Security Hub findings, and the $10 budget, go to your email.
- Consequences: dev edge costs WAF (~$0.01/hour for the ACL and rules) plus ALB hours; CloudFront
  create/destroy takes ~15 minutes each way. The shared security stack bills while it exists
  (GuardDuty, Config, Security Hub checks: a few dollars a month for this account); destroy it after
  the test run if you do not want it running.
