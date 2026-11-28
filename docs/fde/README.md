# Forward Deployed Engineer (FDE) track

A complete, **fictional** customer engagement on top of this platform, written the way a Forward
Deployed Engineer would run it: understand the customer's problem, design with their constraints,
onboard them safely, prove value with a demo and measured results, and hand over.

> The customer, people and numbers below are invented for practice. In interviews, present this as
> "a simulated engagement I ran on my own platform", not as a real client.

| Step | Document | What it shows |
|---|---|---|
| 1 | [Problem statement](01-problem-statement.md) | Turning a vague ask into a measurable problem |
| 2 | [Discovery notes](02-discovery-notes.md) | Stakeholders, current workflow, constraints, risks |
| 3 | [Solution design](03-solution-design.md) | Mapping needs to the platform; security review answers |
| 4 | [Onboarding runbook](04-onboarding-runbook.md) | Tenant onboarding by pull request, data load, isolation check |
| 5 | [Demo script](05-demo-script.md) | A 10-minute customer demo with a clear storyline |
| 6 | [Evaluation](eval/README.md) | Answer quality measured with a fixed question set |
| 7 | [Handover](06-handover.md) | SLOs, alerts, support model, costs, known limits |
| 8 | [Pilot report template](07-pilot-report.md) | Results against the success criteria |

Platform pieces it uses: RAG API (ADR 0011), tenants in Git, row-level security, CloudFront + WAF
(ADR 0008), SLO alerts (ADR 0009), DR (ADR 0010).
