# FDE Guide: Forward Deployed Engineer Track

<div class="cover" markdown>
<p class="sub">How a Forward Deployed Engineer turns a vague customer request into a measured, secure, handed-over solution.</p>
<span class="status">Written (fictional customer) &middot; eval and demo run after the AWS run</span>
</div>

<div class="simple" markdown>
A **Forward Deployed Engineer (FDE)** works directly with a customer: listens, finds the real problem,
builds on the company's platform, proves it works, and hands it over. The skills are half engineering,
half consulting. This track simulates one engagement with a **fictional** logistics company,
*Kestrel Logistics*, on top of the RAG platform (Phase 9). In interviews, present it as a simulation.
</div>

[[diagram:fde]]

## 1. From vague ask to measurable problem
| | |
|---|---|
| First ask | "Our support team wastes time searching documents. Can we have an AI chatbot?" |
| After discovery | 40 agents, ~1,200 questions/day, ~300 SOPs, lookup takes 4-6 minutes, new agents need 6 weeks |
| Goal | Correct, cited answer in < 10 s; median lookup < 30 s; >= 90% correct on the eval set; 99.5% SLO |
| Out of scope | Answering end customers, ticket-system writes, Hindi (phase 2) |

<div class="story" markdown>
Same pattern for QuickCart: "we want AI" becomes "support agents answer refund and delivery questions
from our own policy documents in seconds, always with the source, and say 'not covered' instead of guessing".
</div>

## 2. Discovery: who and what
Stakeholders and what success means to each (support head: handle time; team leads: correctness;
IT security: isolation and audit; finance: predictable cost; agents: speed and trust). Shadow the
current workflow, list pain points, agree risks and mitigations, start small (25 core SOPs).

## 3. Design: map needs to platform features
| Customer need | Platform feature |
|---|---|
| Only their documents, with sources | RAG with citations, "not found" rule |
| Isolation from other customers | Tenant API key + PostgreSQL row-level security |
| Keys and encryption in AWS | KMS everywhere, no model API keys |
| Audit trail | Tenant changes are Git PRs; CloudTrail; logs |
| Peak 5 requests/second | HPA + Karpenter + Aurora scaling (load test) |
| 99.5% availability | SLO burn-rate alerts, Frankfurt DR |

## 4. Onboarding (by pull request)
`scripts/new-tenant-key.sh` -> key handed over securely, only the hash goes into
`gitops/workloads/backend/tenants/tenants.yaml` by PR -> load documents -> **isolation check** (another
tenant gets nothing) -> **eval** -> monitoring -> handover. Offboarding = remove the entry by PR.

## 5. Prove it: the eval set
<div class="simple" markdown>
"It looked good in the demo" is not evidence. Team leads write 10-20 questions with the facts a correct
answer must contain and the SOP it must cite, plus questions the documents cannot answer (must say "not
found"). `docs/fde/eval/run_eval.py` scores the live API; go-live needs 90%. Every wrong answer reported
during the pilot becomes a new eval question.
</div>

## 6. Demo (10 minutes) and handover
Demo: the pain -> a cited answer -> honesty ("not in your documents") -> safety (prompt-injection
document, other tenant sees nothing) -> speed and cost dashboard -> next step (4-week pilot).
Handover: SLOs, alerts, RACI (who uploads, who rotates keys, who is on call), known limits, support levels,
pilot report against the original success criteria.

## 7. Interview questions
**Tell me about a customer engagement.** Use this track honestly as a simulation: problem -> discovery -> design -> eval -> demo -> handover, with the numbers.

**How do you handle a security questionnaire?** Map each question to a concrete control and say clearly what is *not* covered (e.g. inference region).

**How do you know the AI is good enough?** A fixed eval set agreed with the customer, a go-live bar, regression on every change.

## Test yourself
1. Rewrite "we want a chatbot" as a measurable goal.
2. Which three people must sign off before go-live, and on what?

<div class="evidence" markdown>
Eval score (date, model), demo recording, pilot report table filled.
</div>
