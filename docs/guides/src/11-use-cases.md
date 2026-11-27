# Use Cases: What This Platform Is For

<div class="cover" markdown>
<p class="sub">Real-world situations (shopping, food delivery, logistics, customer support) and which part of the platform solves each.</p>
<span class="status">Concept guide &middot; examples are illustrative, not real customers</span>
</div>

[[diagram:quickcart]]

<div class="simple" markdown>
Companies like large online stores, food delivery apps and logistics firms all face the same problems:
traffic spikes, attacks, data that must not leak, outages they must survive, and now AI features that
must be safe. This guide walks through those problems with **QuickCart** (fictional shop + food delivery)
and shows which phase of this project answers each one.
</div>

## Use case 1: Festival sale traffic spike
<div class="story" markdown>
At 12:00 on sale day, traffic jumps 10x in two minutes.
</div>
| Need | Solved by |
|---|---|
| More app instances fast | HPA adds pods (Phase 4) |
| More machines for those pods | Karpenter adds spot nodes in ~1 minute (Phase 1) |
| Database keeps up | Aurora Serverless scales ACUs (Phase 4) |
| Repeat reads cheap | Valkey cache (Phase 4) |
| Know before customers complain | SLO burn-rate alerts (Phase 6) |
| Proof it works | Load test spike profile (Phase 8) |

## Use case 2: Bots and attackers
<div class="story" markdown>
Scrapers hammer the catalog, someone tries SQL injection on the search box, and a Log4j scan hits every URL.
</div>
WAF rate limit, SQLi and Known Bad Inputs rules block at the edge; the ALB has no public address
(Phase 5). GuardDuty flags unusual API activity; Security Hub shows misconfigurations.

## Use case 3: A compromised developer laptop
<div class="story" markdown>
An attacker builds a modified image and pushes it to the registry.
</div>
Kyverno refuses it: not signed with the KMS key and no signed SBOM (Phases 2-3). CI is the only signer,
from `main`, through GitHub OIDC. Deploys are PRs, so changes are reviewed and reversible.

## Use case 4: One service gets hacked
<div class="story" markdown>
A bug lets an attacker run code inside the backend pod.
</div>
They find no passwords (IAM tokens only), a database user that can only read/insert, a cache user limited
to `backend:*`, NetworkPolicy blocking other destinations, mesh AuthZ blocking other services, and IMDSv2
blocking the node's credentials (Phases 1, 3, 4). Blast radius stays small.

## Use case 5: Support assistant for agents (AI)
<div class="story" markdown>
"Customer says the food arrived cold and late; what credit can I offer?" The agent gets the answer from
the delivery-delay SOP, with the source, in seconds.
</div>
RAG on pgvector + Claude on Bedrock with citations (Phase 9); answers only from company documents;
prompt-injection defence; cost alerts; eval before go-live (FDE track).

## Use case 6: Many business customers on one platform (B2B)
<div class="story" markdown>
QuickCart sells its assistant to restaurant chains. Chain A must never see Chain B's documents.
</div>
Tenant API keys, PostgreSQL row-level security, onboarding/offboarding by Git PR (Phase 9, FDE).

## Use case 7: A whole AWS region goes down
<div class="story" markdown>
Mumbai has a major outage during dinner rush.
</div>
Aurora Global Database copy in Frankfurt, replicated signed images and keys, same Terraform in a `dr`
workspace, measured drill (Phase 7).

## Use case 8: "Why is the bill so high?"
Budget alert at 80%, Karpenter CPU cap, spot nodes, Aurora at 0 ACU when idle, AMP keep-list, dev destroyed
daily, cost report per service (Phases 0, 5, 6, 8).

## Summary table
| Problem | Phase(s) |
|---|---|
| Traffic spikes | 1, 4, 6, 8 |
| Web attacks, bots | 5 |
| Malicious images | 2, 3 |
| Compromised service | 1, 3, 4 |
| AI answers from company docs | 9, FDE |
| Many customers, strict isolation | 9, FDE |
| Region outage | 7 |
| Cost control | 0, 5, 6, 8 |
