# 4. Onboarding runbook: new tenant (example: kestrel-logistics)

Preconditions: the platform runs (test-run runbook), RAG check passed.

| # | Step | Command / action | Check |
|---|---|---|---|
| 1 | Create the key | `scripts/new-tenant-key.sh kestrel-logistics "Kestrel Logistics"` | key printed once, entry printed |
| 2 | Hand over the key | Send through the customer's secure channel (never email, chat, or a ticket) | customer confirms receipt |
| 3 | Register the tenant | PR adding the entry to `gitops/workloads/backend/tenants/tenants.yaml`; review; merge | Argo CD sync OK; `kubectl -n backend logs job/db-migrate` says "N tenant(s) active" |
| 4 | Load documents | `URL=... KEY=... scripts/fde-load-docs.sh docs/fde/sample-data` | each file prints `chunks: n` |
| 5 | Isolation check | Ask the same question with another tenant's key | 404 "no documents for this tenant", never Kestrel text |
| 6 | Quality check | `URL=... KEY=... python3 docs/fde/eval/run_eval.py` | score >= 90% before go-live |
| 7 | Monitoring | Backend SLO dashboard; RagTokenSpendHigh / RagRefusalsRising alerts active | dashboards show traffic |
| 8 | Hand over | Walk through [handover](06-handover.md) with support lead and IT | sign-off |

Offboarding: remove the entry by PR (key stops working at the next sync), then delete the tenant's
documents on written request and confirm in writing.
