# 1. Problem statement: Kestrel Logistics (fictional)

## The ask, as first heard
"Our support team wastes time searching documents. Can we have an AI chatbot?"

## The problem, after discovery
Kestrel's 40 customer-support agents answer about 1,200 shipment questions a day (delays, claims,
customs, refunds). The answers live in ~300 internal SOP documents. Agents search a shared drive by
file name, and **a typical lookup takes 4 to 6 minutes**; new agents need 6 weeks before they answer
claims questions without escalating.

## Goal (measurable)
Agents get a correct, **cited** answer from Kestrel's own SOPs in **under 10 seconds**, so that:

| Metric | Today | Target after a 4-week pilot |
|---|---|---|
| Median time to find an SOP answer | 5 min | < 30 s (including reading the citation) |
| Answers judged correct by team leads (eval set) | n/a | >= 90% |
| Questions answered without escalation (new agents) | ~60% | >= 80% |
| Availability during support hours | n/a | 99.5% (SLO) |

## Out of scope for the pilot
Answering end customers directly; writing to Kestrel's ticketing system; documents in Hindi
(planned for phase 2); personal data of shippers inside the documents (removed before upload).

## Why this platform
Kestrel's security team requires: data isolated from other customers, encryption with keys in AWS,
no customer data used for model training, an audit trail, and India-first hosting. The platform
already provides tenant isolation in the database, KMS everywhere, Bedrock (no training on inputs),
CloudTrail/flow logs, and Mumbai as the primary region.
