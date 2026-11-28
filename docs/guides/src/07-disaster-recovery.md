# Phase 7 Guide: Disaster Recovery (Mumbai -> Frankfurt)

<div class="cover" markdown>
<p class="sub">Pilot light, Aurora Global Database, ECR + KMS replication, Terraform workspaces, measured drill.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
QuickCart keeps a **copy of its ledger and recipes in a second city**, updated every second, and the
**same building plans** to open a store there quickly. It does not pay rent for a second staffed store
every day. Twice a year it holds a **fire drill**: closes the main store, opens the backup, and times it.
</div>

[[diagram:dr]]

## 1. RTO and RPO
<div class="simple" markdown>
**RTO** (recovery time objective): how long until users are served again. **RPO** (recovery point
objective): how much recent data you can lose. Pilot light gives a small RPO (data copied continuously)
with a medium RTO (compute must be built), at low cost.
</div>

| Strategy | Always running in DR | RTO | Cost |
|---|---|---|---|
| Backup & restore | Backups only | Hours | Lowest |
| **Pilot light (here)** | Data + images + keys | ~30-60 min | Low |
| Warm standby | Smaller full stack | Minutes | Medium |
| Active-active | Full stack, serving | ~0 | Highest |

## 2. What is replicated
| Item | How | Why it matters |
|---|---|---|
| Aurora data | Global Database, storage-level, usually < 1 s lag; headless secondary (no instance) | Data survives a region loss; no compute bill until needed |
| Images + signatures | ECR registry replication + creation template (immutable, KMS) | DR runs the exact same signed digest |
| Cosign key, data key | KMS multi-Region keys + replicas | DR verifies signatures and decrypts the secret without Mumbai |
| Admin secret | Secrets Manager replica | db-migrate works in Frankfurt |
| Cache | Not replicated (Serverless has no Global Datastore) | Disposable; refills after failover |

## 3. Same code, two regions
<div class="simple" markdown>
Every dev stack runs unchanged in Frankfurt using a **Terraform workspace** called `dr` and a
`dr.tfvars` file (region, IP range 10.21.0.0/16, AZ IDs). One code path means the DR copy cannot drift
away from production. `WORKSPACE=dr scripts/tf.sh ...` loads the right file.
</div>

<div class="bug" markdown>
(1) AWS docs: RDS-managed admin passwords are **not supported** with Aurora Global Database, so Terraform
generates an ephemeral password and writes it with **write-only** arguments: it reaches RDS and Secrets
Manager but never the state file. (2) Global databases **cannot auto-pause**, so the floor is 0.5 ACU
while DR is on. (3) A Kustomize image override for the DR registry **dropped the digest**; a layered
`overlays/dr` keeps it, and Kyverno in Frankfurt would have refused the pods otherwise.
</div>

## 4. The drill
[[diagram:drill]]
```bash
scripts/up-dr.sh                         # build Frankfurt (prints build time)
scripts/dr-drill.sh dr switchover        # planned: RPO should be 0
scripts/dr-drill.sh home switchover      # back to Mumbai
scripts/dr-drill.sh dr failover          # optional: unplanned, RPO = lag
scripts/destroy-dr.sh
```
The script writes a marker row, moves the writer, measures **RTO (database)**, **RTO (first successful
write)** and checks the marker for **RPO**.

## 5. Interview questions
**Pilot light vs warm standby?** Pilot light replicates data but builds compute on demand (cheaper, slower).

**What is your RPO with Aurora Global Database?** Planned switchover 0; unplanned failover = replication lag at that moment, typically under a second.

**How do users reach Frankfurt?** With a domain, Route 53 failover or a DNS change; without one, the DR CloudFront URL.

<div class="glossary" markdown>
**Glossary.** *Switchover*: planned, no data loss. *Failover*: unplanned, may lose the replication lag.
*Headless cluster*: storage without database instances. *Workspace*: separate Terraform state for the same code.
</div>

## Test yourself
1. Why replicate the KMS keys, not just the images?
2. Why does the DR backend show "sync failed" until the switchover?
3. Which part of the pilot-light RTO is usually the largest?

<div class="evidence" markdown>
Drill output (RTO db, RTO app, RPO), RDS global database page, DR build time from `up-dr.sh`.
</div>
