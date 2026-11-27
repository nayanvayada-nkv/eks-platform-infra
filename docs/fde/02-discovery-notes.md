# 2. Discovery notes (fictional)

## Stakeholders
| Role | Cares about | Success for them |
|---|---|---|
| Head of Customer Support (sponsor) | Handle time, new-agent ramp-up | Shorter calls, fewer escalations |
| Support team leads (2) | Answer correctness | No wrong refund or customs advice |
| IT security lead | Data isolation, keys, audit | Passes their vendor security review |
| Finance | Monthly cost | Predictable spend, under the agreed cap |
| Agents (pilot group of 8) | Speed, trust | One search box, answers with sources |

## Current workflow (observed in a shadowing session)
1. Agent reads the ticket, guesses the SOP name, searches the shared drive.
2. Opens 2-4 documents, scrolls, sometimes asks a lead in chat.
3. Copies the relevant paragraph into the reply.

Pain points: file names do not match how customers phrase questions; outdated copies of SOPs;
leads are interrupted ~30 times a day.

## Requirements
- Answers **only** from Kestrel's documents, always with the source document named.
- Say "not in your documents" instead of guessing (wrong customs advice has legal cost).
- Kestrel's data never visible to any other tenant; keys and encryption in AWS.
- Document updates go live the same day.
- Works for 8 pilot agents, then 40 (peak ~5 questions/second at shift start).

## Constraints and risks
| Risk | Mitigation |
|---|---|
| Hallucinated answers | Grounding in retrieved chunks, citations, "not found" rule, eval set before go-live |
| Prompt injection through an uploaded document | Documents passed as data, not instructions; refusal metrics and alert |
| Data leak between tenants | Row-level security in PostgreSQL, tested in onboarding |
| Cost surprises | Answer cache, token metrics + alert, monthly budget alarm |
| Stale SOPs | Owner per document, re-upload replaces content (phase 2: versioning) |

## Decisions taken with the customer
- Pilot with 25 core SOPs first (claims, delays, customs, refunds), not all 300.
- Team leads write 20 questions with expected answers: this becomes the [eval set](eval/README.md).
- Weekly 30-minute check-in; go/no-go for all 40 agents after 4 weeks.
