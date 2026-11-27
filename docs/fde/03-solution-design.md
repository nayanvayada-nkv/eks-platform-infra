# 3. Solution design (fictional customer, real platform)

## Flow
Agent's browser -> CloudFront + WAF -> internal ALB -> Istio gateway (mTLS) -> backend `/ask`
-> tenant from API key -> pgvector search limited to Kestrel's rows (row-level security)
-> Claude on Amazon Bedrock answers from those chunks with citations -> answer + sources.

## Mapping requirements to the platform
| Requirement | How it is met | Where |
|---|---|---|
| Answers only from their documents, with sources | Document blocks + citations, "not found" rule, no model call without matches | `apps/backend/rag.py`, ADR 0011 |
| Isolation from other tenants | API key -> tenant; FORCE'd row-level security in PostgreSQL | `migrate.py`, ADR 0011 |
| Keys and encryption in AWS | KMS for Aurora, Valkey, secrets; TLS everywhere | ADR 0007 |
| No training on their data | Amazon Bedrock does not use inputs to train models | Bedrock data protection docs |
| Audit trail | Tenant changes are Git PRs; CloudTrail; WAF and app logs | `gitops/workloads/backend/tenants` |
| Same-day document updates | `POST /documents` by the customer's own key | API |
| 5 requests/second at peak | HPA + Karpenter, Aurora scaling; verified by the Phase 8 load test | `loadtest/` |
| 99.5% availability | SLO + burn-rate alerts, DR to Frankfurt | ADR 0009, ADR 0010 |

## Answers for their security questionnaire (short form)
- **Where is data stored?** Aurora PostgreSQL in Mumbai (ap-south-1), replicated to Frankfurt only
  if DR is enabled. Inference runs on Amazon Bedrock's global endpoint for Mumbai, so requests may be
  processed in another region; if that is not acceptable, a geographic/regional option must be used.
- **Who can read it?** Only requests carrying Kestrel's API key, enforced in the database. Platform
  admins can access the database; access is logged.
- **How are keys handled?** We generate a 256-bit key once and hand it over securely; only its hash is
  stored. Rotation = new key by PR, old one stops working at the next deploy.
- **Deletion?** On offboarding the tenant is disabled by PR; documents are deleted on request.

## Not built for the pilot (honest list)
Per-user login (SSO) for agents, document versioning, Hindi documents, usage reports per agent.
