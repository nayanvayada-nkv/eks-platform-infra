# Runbook: game day (Phase 8)

Goal: break things on purpose, in dev, while watching the dashboards, and write down what happened.
Every scenario: say the hypothesis first, run it, measure, restore, note the result.

| # | Scenario | How | Hypothesis (expected) |
|---|---|---|---|
| 1 | Pod crash | `kubectl -n backend delete pod -l app.kubernetes.io/name=backend --wait=false` (one pod) | other replica serves; no SLO burn; replacement Ready < 60 s |
| 2 | Spot interruption | `environments/dev/chaos` apply, then its `spot_interruption` start command | Karpenter drains within the 2-min notice, new node, no 5xx spike |
| 3 | System node loss | chaos `system_node_loss` start command | node group replaces it; CoreDNS/Argo CD recover; backend unaffected or brief blip |
| 4 | Bad deploy | merge a GitOps PR with an unsigned digest | Kyverno refuses; old pods keep serving; Argo CD shows sync failed; fix = git revert |
| 5 | Policy engine down | `kubectl -n kyverno scale deploy kyverno-admission-controller --replicas=0` | fail closed: new pods in app namespaces refused; running pods unaffected; scale back to 1 |
| 6 | Database pause / resume | stop traffic 10 min (Aurora to 0 ACU), then one request | first request ~15 s (readiness timeout covers it), no alert storm |
| 7 | Cache loss | NetworkPolicy blocks 6379 temporarily (edit by PR) | `/readyz` fails -> pods leave the Service -> BackendDown alert; restore by revert |
| 8 | Credential misuse | from a debug pod in `backend`, try `aws s3 ls` with the backend identity | AccessDenied (least privilege); GuardDuty may flag unusual API calls |
| 9 | WAF | `scripts`-free: curl with `<script>` / SQLi / 150 fast requests | 403s, WAF sampled requests show the rule |
| 10 | Region loss (DR) | `docs/runbooks/phase7-dr-drill.md` | measured RTO / RPO |

Record per scenario: start/end time, what the dashboards showed, alerts received (and how fast),
user impact, and one improvement. Destroy the chaos stack afterwards.
