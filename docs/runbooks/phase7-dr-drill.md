# Runbook: Phase 7 DR drill (Mumbai -> Frankfurt -> Mumbai)

Goal: prove "failover test with measured RTO / RPO" ([ADR 0010](../adr/0010-pilot-light-dr-frankfurt.md)).
Precondition: the Phases 1-6 run day has succeeded and Mumbai is serving traffic.
Expected extra cost: about **$3 to $5** for 3 to 4 hours. Every apply needs your OK.

| # | Who | Step | Check it worked |
|---|---|---|---|
| 1 | Claude | `shared/supply-chain`: set `replication_regions = ["eu-central-1"]`, plan, apply (ECR replication + template, Cosign key replica) | ECR console in Frankfurt shows `eks-platform/backend` after the next image push |
| 2 | Both | Push a new image (merge a backend change) so it replicates with its signature | image + `.sig` + `.att` tags in Frankfurt |
| 3 | Claude | Mumbai `dev/data`: set `dr_region = "eu-central-1"`, plan, apply (global cluster, data key replica, secret replica, min 0.5 ACU) | RDS console: global database with Mumbai as primary |
| 4 | Claude | `scripts/up-dr.sh`: network, eks, data (headless secondary), edge, platform in the `dr` workspace | prints the build time (part of the pilot-light RTO) |
| 5 | Claude | Frankfurt `dev/data`: `dr_instances = 1` in `dr.tfvars`, plan, apply (a reader that can take over) | secondary shows 1 instance, replication lag < 1 s |
| 6 | Claude | `scripts/dr-drill.sh dr switchover` | prints RTO (db), RTO (app write), RPO = 0 |
| 7 | You | Screenshots: drill output, RDS global database page, Frankfurt app answering | |
| 8 | Claude | `scripts/dr-drill.sh home switchover` (writer back to Mumbai) | Mumbai app accepts writes again |
| 9 | Optional | `scripts/dr-drill.sh dr failover` then `home switchover`: unplanned case, RPO = lag | RPO line in the output |
| 10 | Claude | `scripts/destroy-dr.sh`, then Mumbai `dev/data` with `dr_region = ""` (back to auto-pause), supply-chain `replication_regions = []` | no Frankfurt resources left (`aws resourcegroupstaggingapi get-resources --region eu-central-1`) |

Notes
- Before the switchover the Frankfurt backend shows **sync failed** in Argo CD: its db-migrate hook
  cannot write to a read-only secondary. Argo CD retries (backoff up to 3 min) and succeeds after the
  promotion; that retry time is inside the measured "RTO (app write)".
- After moving the writer to Frankfurt, Mumbai's API can read but not write (its endpoint is now a
  reader). That is expected in a regional-endpoint design; move it back with step 8.
- Interview numbers to report: RTO (db), RTO (app), RPO, plus the DR build time from step 4.
