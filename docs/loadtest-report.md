# Load test report (template, fill after the run)

Date: ___  Commit: ___  Profile(s): ___  Region: ap-south-1  Load generator: laptop / ___

| Question | Result | Evidence |
|---|---|---|
| Max sustained RPS with p95 < 500 ms and errors < 0.5% | | Locust report, SLO dashboard |
| First limit hit (pods, nodes, Karpenter cap, Aurora ACU, Valkey ECPU, NAT, other) | | dashboards |
| HPA reaction: time from load jump to new pods Ready | | `kubectl get hpa -w` timestamps |
| Karpenter reaction: time from Pending pods to new node Ready | | `kubectl get nodes -w` |
| Aurora: ACU peak, resume time from 0 ACU | | RDS metrics |
| Cache effect: share of /items served from Valkey | | `source` field sample |
| Alerts that fired (expected / unexpected) | | email, AMP |
| Cost of the test hour | | `scripts/cost-report.sh` |

What broke first, why, and what I changed (with before/after numbers):
