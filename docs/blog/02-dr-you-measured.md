# Draft: Pilot-light DR you have actually measured (Mumbai -> Frankfurt)

*Draft. Numbers marked [measure] come from `scripts/dr-drill.sh` output.*

**Claim vs evidence.** "We have DR" usually means a diagram. I wanted two numbers: RTO and RPO.

**Design (pilot light).** Aurora Global Database keeps a headless copy of the data in Frankfurt
(storage replication, no instance); ECR replicates images *and* their Cosign signatures; the KMS keys
are multi-Region, so Frankfurt verifies signatures without calling Mumbai. Compute is rebuilt from the
same Terraform code in a `dr` workspace. One code path, so DR cannot drift from production.

**Gotchas found while building:** RDS-managed admin passwords are not supported with global databases
(write-only Terraform arguments instead, never in state); global databases cannot auto-pause; ElastiCache
Serverless has no cross-region replication (the cache is disposable, so that is fine).

**Results:** planned switchover RTO (database) [measure] s, RTO (first successful write in Frankfurt)
[measure] s, RPO 0 (marker row present). Unplanned failover RPO: [measure]. DR compute build time:
[measure] min, so the honest pilot-light RTO is about [measure] min.

**Trade-off:** pilot light is cheap but slow to recover; a business that needs minutes would pay for
warm standby (DR EKS always running) or active-active.
