# Phase 6 Guide: Observability, SLOs and Alerts

<div class="cover" markdown>
<p class="sub">Prometheus -> Amazon Managed Prometheus, Managed Grafana, Fluent Bit -> CloudWatch, OpenTelemetry -> X-Ray.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
QuickCart's manager watches three things: **counters** (orders per minute, failed payments), a
**diary** of everything that happened (logs) and **parcel tracking** that shows each order's journey
through kitchen, rider and door (traces). The manager promises "99.5% of orders succeed" and gets a
phone call only when that promise is in real danger, not for every single burnt pizza.
</div>

[[diagram:observability]]

## 1. Three signals
| Signal | Question | Tool here |
|---|---|---|
| Metrics | How many, how fast, how often failing? | Prometheus -> AMP, Grafana dashboards |
| Logs | What exactly happened in this pod? | Fluent Bit -> CloudWatch Logs |
| Traces | Where did this one slow request spend its time? | OpenTelemetry -> ADOT collector -> X-Ray |

## 2. Metrics without exposing them
<div class="simple" markdown>
The app counts requests (`http_requests_total`) and measures latency (`http_request_duration_seconds`),
labelled by **route pattern** (`/items`, never `/items/123`, so the number of series stays small).
Probes are not counted, or they would make the SLO look better than reality. Metrics are served on a
**separate port 9464** that the Service and gateway never expose; only Prometheus's mesh identity may call it.
</div>

Prometheus keeps 6 hours locally and **remote-writes** a filtered list of metrics to Amazon Managed
Prometheus (AMP bills per sample, so only what dashboards and alerts use is shipped).

## 3. SLOs and burn-rate alerts
[[diagram:slo_burn]]
<div class="deep" markdown>
SLO: 99.5% of requests are not 5xx over 30 days, so the error budget is 0.5% (~3.6 hours of full
outage a month). Alert on **burn rate**: how fast the budget is being used. Fast burn (14.4x) over 1 h
*and* still burning over 5 min pages you; slow burn (6x) over 6 h and 30 min warns. The short window makes
alerts stop soon after a fix. Rules are unit-tested with `promtool test rules` (10% errors fires,
0.1% stays silent, scale-to-0 fires BackendDown).
</div>

```yaml
- alert: BackendErrorBudgetBurnFast
  expr: slo:backend_errors:ratio_rate1h > (14.4 * 0.005) and slo:backend_errors:ratio_rate5m > (14.4 * 0.005)
  for: 2m
  labels: { severity: critical }
```

## 4. Why managed services, and why Managed Grafana
Alerting runs in AMP, outside the cluster, so a broken cluster can still page you. Grafana's image is
only on Docker Hub (against the project's rule), so **Amazon Managed Grafana** is used: login via IAM
Identity Center, UI limited to your IP, workspace role read-only. Dashboards are JSON in Git, loaded by
`scripts/grafana-dashboards.sh` with a one-day token.

## 5. Each component's identity
| Component | Can do | Cannot do |
|---|---|---|
| Prometheus | `aps:RemoteWrite` to one workspace | Read metrics back |
| Fluent Bit | Write streams to one log group | Read logs |
| ADOT collector | Put trace segments to X-Ray | Anything else |
| Grafana | Read AMP, CloudWatch, X-Ray | Write anything |

<div class="bug" markdown>
Rendering kube-prometheus-stack with our values failed: with admission webhooks off, the operator's TLS
setting must be off too. Caught locally by `helm template`, before any cluster existed.
</div>

## 6. Alert test (run day)
Pause Argo CD auto-sync for the backend, `kubectl -n backend scale deploy backend --replicas=0`, wait:
an email "[FIRING] BackendDown" arrives in ~5 minutes; scale back and "[RESOLVED]" follows.

## 7. Interview questions
**SLI vs SLO vs SLA?** SLI = what you measure (good requests / all). SLO = target (99.5%). SLA = contract with penalties.

**Why burn rate instead of "error rate > 1%"?** It scales alert urgency to budget impact and avoids paging for short blips.

**Why a separate metrics port?** Keeps metrics off the public path and lets mesh AuthZ allow only Prometheus.

<div class="glossary" markdown>
**Glossary.** *Error budget*: allowed failures within the SLO. *Remote write*: Prometheus sending samples
to another store. *Cardinality*: number of unique label combinations. *Span*: one timed step of a trace.
</div>

## Test yourself
1. What happens to alerting if the whole EKS cluster dies?
2. Why exclude `/healthz` from the SLO metrics?
3. What does 14.4 mean in the fast-burn rule?

<div class="evidence" markdown>
Backend SLO dashboard, an X-Ray trace with Aurora/Valkey/Bedrock spans, the BackendDown email pair.
</div>
