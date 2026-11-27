# 6. Handover (pilot -> steady state)

## Service levels
| Item | Value |
|---|---|
| Availability SLO | 99.5% of requests non-5xx over 30 days (support hours) |
| Latency objective | 95% of `/ask` answers within 10 s (cached: < 0.5 s) |
| Alerts | BackendErrorBudgetBurnFast/Slow, BackendDown, RagTokenSpendHigh, RagRefusalsRising |
| Recovery | Pilot-light DR to Frankfurt, measured RTO/RPO in the DR drill report |

## Who does what (RACI)
| Task | Customer | Platform team |
|---|---|---|
| Upload / update SOPs | R, A | C |
| Eval set and correctness sign-off | R, A | C |
| Key requests and rotation | R (request) | A (PR + handover) |
| Incidents and on-call | I | R, A |
| Cost reporting (monthly) | I | R, A |

## Known limits (pilot)
English only; no per-agent login; answers cached for 10 minutes after an SOP update;
inference may run outside India (Bedrock global endpoint).

## Support
Severity 1 (assistant down in support hours): response 30 min. Severity 2 (wrong answers on a topic):
next business day, with the failing question added to the eval set.
