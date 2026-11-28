# ADR 0010: Pilot-light DR in Frankfurt with Aurora Global Database

- Status: accepted (code written 27 Nov 2026, not applied). Supersedes the open "one or two DR regions"
  question in docs/architecture.md: you chose **Germany only** (eu-central-1).
- Context: Phase 7 (one lean DR region, Aurora Global DB, ECR replication). Proof: failover test with
  measured RTO / RPO. ADR 0003: pilot light, cost first.
- Decisions:
  1. **Pilot light:** data and artifacts are replicated all the time; compute is rebuilt on demand.
     - Always on (while DR is enabled): Aurora Global Database secondary (headless: replicated storage,
       no instance), ECR replication incl. Cosign signatures, multi-Region KMS keys (Cosign key, data key),
       replicated admin secret.
     - On demand: VPC, EKS, platform, edge in Frankfurt, built by `scripts/up-dr.sh`.
  2. **Same code, two regions:** every dev stack runs unchanged in a `dr` Terraform workspace with a
     `dr.tfvars` (region, CIDR 10.21.0.0/16, names `*-dr`). State stays in the Mumbai bucket;
     shared stacks are always read from the default workspace. One code path means DR cannot drift.
  3. **Admin password without RDS management:** RDS-managed master passwords are not supported with
     Aurora Global Database (AWS docs), so Terraform generates an ephemeral password and writes it with
     write-only arguments to RDS and Secrets Manager: never in state or Git. Rotation: bump
     `admin_password_version` (no automatic rotation yet; Phase 8).
  4. **No auto-pause while global:** AWS does not pause Serverless v2 in global databases, so the floor is
     0.5 ACU in both regions while DR is on. DR stays off (`dr_region = ""`) outside drills.
  5. **Cache is not replicated:** ElastiCache Serverless has no Global Datastore (node-based only). The
     cache is disposable by design; Frankfurt gets an empty one and warms up.
  6. **Images in DR come from the DR ECR replica, same digest.** Argo CD uses `overlays/dr`, a layer over
     `overlays/dev` plus an image override that only changes the registry (overriding inside `dev`
     drops the digest; tested). Kyverno in Frankfurt verifies with the replica Cosign key.
  7. **Failover is measured, not assumed:** `scripts/dr-drill.sh` writes a marker, runs a managed
     switchover (or a simulated failover with data loss allowed), and prints RTO for the database and
     for the first successful API write, plus RPO from the marker.
  8. **Cutover of users:** without a domain, each region has its own CloudFront URL. With a domain,
     Route 53 would switch (failover record or manual change); not built, because there is no domain yet.
- Consequences: while DR is on, Aurora costs two 0.5 ACU floors plus cross-region replication; the
  drill day adds a second EKS cluster, NAT and CloudFront for a few hours. The pilot-light RTO is
  roughly "build DR compute (~30-40 min) + switchover (~1-2 min)"; RPO for a planned switchover is 0,
  for an unplanned failover it is the replication lag at that moment (usually under a second).
