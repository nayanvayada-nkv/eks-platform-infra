# Runbook: load test (Phase 8)

Goal: find the platform's real limits and check that autoscaling, SLOs and alerts behave under load.
Tool: Locust (`loadtest/`, installed with pip, no Docker). Run from your laptop against CloudFront.

## Before (each needs your OK; revert after the test)
| Guard rail | Normal | For the test window | Why |
|---|---|---|---|
| WAF rate limit (`environments/dev/edge`, `rate_limit_per_minute`) | 100 / min per IP | 20000 for one load-generator IP | otherwise the test measures the WAF (that is a separate test) |
| WAF allow-list (`allowed_viewer_cidrs`) | your IP | your IP | unchanged |
| Aurora max (`environments/dev/data`, `aurora_max_acu`) | 2 ACU | 8 ACU | lets the database scale; note the ACU peak |
| Karpenter CPU limit (platform) | 16 vCPU | keep | hitting it is a result, not a failure |
| RAG traffic | off | `RAG_KEY` set, low weight | every uncached answer costs Claude tokens |

AWS allows normal load tests without approval; very large or DDoS-like tests (roughly >1 Gbps sustained)
need prior approval. These profiles are far below that.

## Run
```bash
URL=$(cd environments/dev/edge && terraform output -raw url)
URL="$URL" scripts/loadtest.sh smoke      # 1 min, 5 users: wiring check
URL="$URL" scripts/loadtest.sh ramp       # 15 min, up to 200 users: find the knee
URL="$URL" scripts/loadtest.sh spike      # 10 min, jump to 300 users: autoscaling reaction time
URL="$URL" scripts/loadtest.sh soak       # 33 min, 60 users steady: leaks, drift, cost per hour
```

## Watch during the run
Backend SLO dashboard (RPS, p95, error ratio vs burn thresholds), `kubectl get hpa -n backend -w`,
`kubectl get nodes -w` (Karpenter spot nodes), RDS console (ServerlessDatabaseCapacity), Valkey ECPU,
WAF metrics (should show no blocks for the allow-listed IP), alert emails.

## Report
Fill [docs/loadtest-report.md](../loadtest-report.md) from `loadtest/results/<run>/report.html` and the
dashboards: max sustained RPS within SLO, the first limit hit, scale-out times, cost of the hour.
