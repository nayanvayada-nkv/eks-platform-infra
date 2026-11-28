# ADR 0007: Data layer with IAM logins, and ALB -> Istio gateway ingress

- Status: accepted (code written 27 Nov 2026, not applied)
- Context: Phase 4 ("app serving traffic"): Aurora, Redis, Flask app, HPA. Phase 3 left two items here:
  secrets management, and how outside traffic enters a mesh with strict mTLS.
- Decisions:
  1. **Aurora PostgreSQL Serverless v2, min 0 ACU** (auto-pause after 5 min). Dev pays mostly for storage.
     PostgreSQL rather than MySQL because pgvector is the recommended vector store (Phase 9).
  2. **ElastiCache Serverless for Valkey** instead of Redis OSS: same protocol, lower price, open licence.
     Usage limits (1 GB, 1000 ECPU/s) cap the bill.
  3. **No passwords for the app.** The backend logs in to Aurora and Valkey with 15-minute IAM tokens
     signed by its Pod Identity role (`rds-db:connect` for user `app`, `elasticache:Connect` for one cache
     user). Nothing to store, rotate or leak, and every login is tied to a Kubernetes service account.
  4. **The admin password exists only in Secrets Manager**, generated and rotated by RDS
     (`manage_master_user_password`), encrypted with our data KMS key. Only the `db-migrate` Job's
     identity can read it, through a VPC endpoint. This replaces "External Secrets" from the Phase 3
     plan: there is no app secret left to sync.
  5. **Least privilege inside the database and cache:** role `app` gets `SELECT, INSERT` on `items` only;
     the Valkey user may touch keys `backend:*` only, without dangerous commands.
  6. **TLS everywhere with verification:** `sslmode=verify-full` against the RDS CA bundle (vendored in
     the image), `rds.force_ssl=1`, Valkey serverless is TLS-only.
  7. **Ingress: ALB -> Istio ingress gateway -> backend (mTLS).** Strict mTLS (ADR 0006) means the ALB
     cannot talk to pods directly. The ALB is restricted to your IP and HTTP only until Phase 5 adds
     Route 53, ACM, CloudFront and WAF in front of it.
  8. **Migrations as an Argo CD Sync hook** using the same signed image, before new pods start.
- Consequences: a Secrets Manager interface endpoint (~$0.04/hour) in dev; Aurora's first query after
  idle takes ~15 s (readiness probe timeout raised); readiness depends on Aurora and Valkey, liveness
  does not. Security groups for pods would narrow DB access from "cluster" to "backend pods" at the AWS
  layer; today NetworkPolicy + IAM do that inside the cluster.
