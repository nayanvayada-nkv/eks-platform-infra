# Phase 8 Guide: Hardening, Load Testing and Game Days

<div class="cover" markdown>
<p class="sub">Locust load tests, AWS FIS chaos experiments, pinned actions, blocking scans, cost report, write-ups.</p>
<span class="status">Written and validated as code &middot; not yet run on AWS</span>
</div>

<div class="story" markdown>
Before a festival sale, QuickCart **rehearses**: it sends fake shoppers in waves to see where the queue
forms (load test), switches off one kitchen on purpose to see if orders still flow (game day), and
checks every supplier's seal again (hardening).
</div>

## 1. Load testing
[[diagram:loadtest]]
<div class="simple" markdown>
A load test answers "how much traffic can we take while keeping our promise (SLO), and what breaks
first?". Locust (Python, installed with pip) simulates users: 80% read `/items`, 10% write, 10% index.
RAG questions run only with a key and at a low share, because each answer costs model tokens.
</div>

| Profile | Shape | Question |
|---|---|---|
| smoke | 5 users, 1 min | Does it work at all? |
| ramp | up to 200 users over 13 min | Where is the knee (latency starts rising)? |
| spike | jump to 300 users | How fast do HPA and Karpenter react? |
| soak | 60 users for 30 min | Leaks, drift, cost per hour |

**Guard rails to open for the test window:** WAF rate limit (100/min would block the test), Aurora max
ACU (2 -> 8). Keep the Karpenter CPU cap: hitting it is a valid result. AWS allows normal load tests;
DDoS-like floods need approval.

## 2. Game days
| Scenario | Hypothesis |
|---|---|
| Delete a backend pod | No SLO burn; replacement Ready in < 60 s |
| FIS spot interruption | Karpenter drains in the 2-min notice; no 5xx spike |
| FIS system node loss | Node group replaces it; platform recovers |
| Unsigned digest merged | Kyverno refuses; old pods keep serving; `git revert` fixes |
| Kyverno scaled to 0 | Fail closed: new app pods refused, running pods fine |
| Cache blocked | `/readyz` fails, BackendDown alert, recovery on revert |
| Region loss | DR drill numbers |

<div class="simple" markdown>
Always write the **hypothesis first**, then measure. A game day without a hypothesis is just breaking things.
</div>

## 3. Hardening done in this phase
| Change | Why |
|---|---|
| All GitHub Actions pinned by commit SHA + Dependabot | A moved/hijacked tag cannot run code in the signing pipeline |
| Checkov blocking in CI (0 failed) | New findings cannot merge silently |
| AZs allow-listed by zone ID | New AWS zones cannot change the network layout |
| Bootstrap `prevent_destroy = true` | The state bucket cannot be deleted by accident |
| No Docker Hub for local tools | Same supply-chain rule for developer tooling |

<div class="bug" markdown>
Pinning revealed `sigstore/cosign-installer@v4` was **not a published tag** (releases are `v4.1.x`):
the image pipeline would have failed at signing on its first real run. Also found: local checks had been
using Docker Hub images; switched to ghcr.io and pip.
</div>

## 4. Cost report and write-ups
`scripts/cost-report.sh <start> <end>` prints cost per service from Cost Explorer. Write-ups: the
interview guide, two blog drafts (signed images, measured DR), a demo video script. Numbers are
`[measure]` placeholders until the run day.

## 5. Interview questions
**What did the load test show?** (fill after the run: max RPS within SLO, first bottleneck, fix.)

**What is chaos engineering?** Controlled experiments with a hypothesis, small blast radius, and a way to stop.

**Why pin actions by SHA?** Tags are mutable; SHAs are not.

## Test yourself
1. Why open the WAF rate limit for the load test but keep the Karpenter cap?
2. What makes a game day different from just breaking things?

<div class="evidence" markdown>
Locust report (RPS vs p95), scale-out timestamps, FIS experiment results, cost table for the run days.
</div>
