# Phase 5 Guide: Edge and Account Security

<div class="cover" markdown>
<p class="sub">CloudFront, AWS WAF, internal ALB via VPC origin, optional Route 53/ACM, Shield, GuardDuty, Security Hub, Config, budget.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
QuickCart's warehouse has **no street door at all**. Customers enter a **shop front in the mall**
(CloudFront) where a **guard** (WAF) checks everyone and stops anyone running in a hundred times a
minute. Orders reach the warehouse through a **private corridor** that only the mall can use. Separately,
**CCTV with an alarm company** (GuardDuty, Security Hub) watches the whole building.
</div>

[[diagram:edge]]

## 1. Why the ALB is internal
<div class="simple" markdown>
If the load balancer had a public address, attackers could skip CloudFront and the WAF and hit it
directly. Here it has **no public address**. CloudFront reaches it through a **VPC origin** (CloudFront
places network interfaces in our private subnets), and the ALB's security group accepts only those.
</div>

## 2. WAF rules (CloudFront scope, us-east-1)
| Priority | Rule | Blocks |
|---|---|---|
| 0 | Dev allow-list (your IP) | Everyone else while in dev |
| 1 | AWS IP reputation list | Known bad sources (botnets, scanners) |
| 2 | Common Rule Set | XSS, path traversal, bad bots, oversized bodies |
| 3 | Known Bad Inputs | Log4j (`${jndi:...}`) and similar exploit strings |
| 4 | SQL injection | `' OR '1'='1` style payloads |
| 5 | Rate limit | > 100 requests per minute per IP |

Logs go to a CloudWatch group `aws-waf-logs-...` with `authorization` and `cookie` headers redacted.

## 3. Connecting CloudFront to pods
Terraform owns the ALB, target group and listener (CloudFront needs the ALB ARN at creation).
Kubernetes only **binds targets**: a `TargetGroupBinding` makes the Load Balancer Controller keep the
target group equal to the Istio gateway pod IPs and opens the node security group only to the ALB, only
on ports 80 and 15021 (health checks).

## 4. Domain and TLS
No domain: viewers use `https://<id>.cloudfront.net` with CloudFront's certificate. With `domain_name`
set: ACM certificate in us-east-1 (DNS validation in Route 53), TLS 1.2+ policy, A/AAAA alias records.
The CloudFront -> ALB hop is HTTP on the AWS private network (TLS there needs a domain certificate).

## 5. Account-level security (`environments/shared/security`)
| Service | What it does | Setting |
|---|---|---|
| GuardDuty | Threat detection from CloudTrail, VPC flow, DNS and the EKS audit log | EKS audit logs on; runtime monitoring switch (off: its managed endpoint blocks VPC deletion) |
| Security Hub | Scores the account against AWS Foundational Security Best Practices | Controls auto-enabled |
| AWS Config | Records resource configuration for Security Hub | Daily recording (cheaper with EKS churn) |
| Alerts | HIGH/CRITICAL GuardDuty, CRITICAL Security Hub -> SNS -> email | KMS-encrypted topic |
| Budget | $10/month, email at 80% actual and 100% forecast | Phase 0 item, finally built |

<div class="why" markdown>
The WAF cannot be bypassed because there is nothing else to reach. Detection is separate from
prevention: even if a rule is missed, GuardDuty and Security Hub raise it, and the budget alert catches
the other kind of incident (a forgotten expensive resource).
</div>

## 6. Demo (after the run)
```bash
curl -s -o /dev/null -w "%{http_code}\n" "$URL/items"                                  # 200
curl -s -o /dev/null -w "%{http_code}\n" "$URL/items?q=<script>alert(1)</script>"      # 403
curl -s -o /dev/null -w "%{http_code}\n" -H 'User-Agent: ${jndi:ldap://x/a}' "$URL/"  # 403
for i in $(seq 1 150); do curl -s -o /dev/null -w "%{http_code} " "$URL/"; done        # 200s then 403s
```

<div class="bug" markdown>
Checkov could not "see" the Log4j rule inside a Terraform `dynamic` block and could not resolve the
CloudFront security group from a data source. The Log4j rule was made explicit; the other two are skips
with written reasons, which is how a real team should handle false positives.
</div>

## 7. Interview questions
**Why WAF on CloudFront and not on the ALB?** Blocks at the edge, closest to the attacker, and the ALB is unreachable anyway.

**Shield Standard vs Advanced?** Standard is free, automatic L3/L4 protection; Advanced (~$3k/month) adds DDoS response team and cost protection.

**Why is GuardDuty runtime monitoring off by default?** Its managed VPC endpoint blocks deleting the dev VPC; it is a switch for game days.

<div class="glossary" markdown>
**Glossary.** *CDN*: content delivery network. *VPC origin*: CloudFront reaching a private load balancer.
*Rate-based rule*: block an IP above N requests per window. *ACM*: AWS Certificate Manager.
</div>

## Test yourself
1. How would an attacker reach the ALB directly? (Trick question.)
2. Which WAF rule stops `${jndi:ldap://...}`?
3. What is the difference between GuardDuty and Security Hub?

<div class="evidence" markdown>
The 403 outputs, WAF sampled requests, GuardDuty and Security Hub summary pages, budget email.
</div>
