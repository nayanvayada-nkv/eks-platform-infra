# Phase 4 Guide: Data Layer and the App Serving Traffic

<div class="cover" markdown>
<p class="sub">Aurora PostgreSQL Serverless v2, Valkey serverless, IAM-token logins, migrations, ingress gateway.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
QuickCart's **ledger** (orders, items) lives in a vault (Aurora). The **board of today's popular dishes**
(Valkey cache) answers most questions instantly. Staff do not carry vault keys: at the door they show
their badge and get a **15-minute pass** (IAM token). Only the night manager (the migration Job) has the
master key, once, to set up the shelves.
</div>

[[diagram:data_access]]

## 1. What was built
| Piece | Choice | Why |
|---|---|---|
| Database | Aurora PostgreSQL 17 Serverless v2, 0 to 2 ACU, auto-pause | Pay ~nothing when idle; PostgreSQL also gives pgvector (Phase 9) |
| Cache | ElastiCache Serverless for Valkey 8, 1 GB / 1000 ECPU limits | Same protocol as Redis, cheaper, capped |
| Keys | One customer-managed KMS key for the data layer | Encryption we control and audit |
| Network | Security groups allow only the cluster's security group | No CIDR ranges, no internet path |
| App | `/items` (Aurora + 30 s cache), `/readyz`, `/healthz` | Real reads/writes to prove the stack |
| Migrations | `db-migrate` Job as an Argo CD Sync hook | Schema ready before new pods start |

## 2. Logging in without passwords
<div class="simple" markdown>
The app asks AWS (through its Pod Identity) to **sign** a short login token, then uses it as the
password. The token works for 15 minutes, only for the database user `app`, only from this identity.
There is no password to leak, rotate or forget in a config file.
</div>

```python
password = rds.generate_db_auth_token(DBHostname=host, Port=5432, DBUsername="app", Region=region)
psycopg.connect(host=host, user="app", password=password,
                sslmode="verify-full", sslrootcert="certs/rds-global-bundle.pem")
```

`verify-full` means the connection is encrypted **and** the server's certificate is checked against the
RDS certificate authority, so a fake database cannot impersonate Aurora. Valkey uses the same idea: a
presigned `connect` request is the AUTH password, refreshed before 15 minutes.

## 3. Least privilege, everywhere
| Layer | Rule |
|---|---|
| IAM (backend role) | `rds-db:connect` for user `app` on this cluster only; `elasticache:Connect` for one cache + one user |
| PostgreSQL | role `app`: `SELECT, INSERT` on `items`; no UPDATE, DELETE or DDL |
| Valkey ACL | keys `backend:*` only; read/write commands; no dangerous commands (FLUSHALL, CONFIG) |
| Secrets | Admin password only in Secrets Manager, readable only by the `db-migrate` identity via a VPC endpoint |

## 4. Health checks done right
`/healthz` (liveness) never checks dependencies, so a database blip does not restart every pod.
`/readyz` (readiness) checks Aurora and Valkey, so a broken pod leaves the Service but stays alive to recover.
Readiness timeout is 12 s because the first query after idle wakes Aurora from 0 ACU (~15 s).

## 5. Getting traffic in (with strict mTLS)
Strict mTLS (Phase 3) means a load balancer cannot talk to pods directly. Traffic enters through the
**Istio ingress gateway** (identity `istio-ingress`), the only caller the backend allows. Phase 5 puts
CloudFront + WAF in front of it.

<div class="bug" markdown>
(1) The repo ignores `*.pem` (to keep private keys out of Git), which would have silently left out the
public RDS CA bundle; a narrow exception was added. (2) Checkov wanted every SQL statement logged; we log
DDL and slow queries only, because full logging copies customer data into CloudWatch.
</div>

<div class="why" markdown>
Compromising the API pod gives an attacker 15-minute tokens for one database user that can only read and
add rows, from inside the cluster. No master password, no delete rights, no cache flush.
</div>

## 6. How to switch it on
1. `dev/data` plan + apply (after `eks`), then `dev/platform` passes the endpoints to Argo CD.
2. Argo CD syncs: ConfigMap -> `db-migrate` Job -> Deployment.
3. Check: `curl $URL/items -X POST -d '{"name":"first"}'`, then `GET /items` twice (`database`, then `cache`).

## 7. Interview questions
**Why Serverless v2 with 0 ACU?** Dev is idle most of the time; compute stops billing when paused.

**Liveness vs readiness?** Liveness restarts a stuck process; readiness removes a pod from traffic. Never put dependency checks in liveness.

**Why a migration Job instead of migrating on app start?** One run per deploy, separate identity with admin rights, app never holds them.

<div class="glossary" markdown>
**Glossary.** *ACU*: Aurora capacity unit (~2 GB RAM). *ECPU*: ElastiCache compute unit. *IAM auth*: login
with a signed AWS token. *Sync hook*: an Argo CD resource run at a specific point of a sync.
</div>

## Test yourself
1. What can an attacker do with the backend's database token? What can they not do?
2. Why is `/healthz` dependency-free?
3. Why must traffic pass through the Istio gateway?

<div class="evidence" markdown>
`/items` responses (database, then cache), db-migrate Job log, Aurora ACU graph scaling from 0.
</div>
