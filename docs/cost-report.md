# Cost report (template)

Fill with `scripts/cost-report.sh <start> <end>` after each run day.

## Expected costs (ap-south-1, on-demand list prices, approximate)
| Item | While running | Notes |
|---|---|---|
| EKS control plane | ~$0.10 / h | per cluster (DR drill: two) |
| NAT gateway | ~$0.056 / h + data | single NAT in dev |
| 2x t3.medium system nodes | ~$0.09 / h | |
| Karpenter spot nodes | ~$0.01-0.03 / h each | only under load |
| Interface endpoints (secretsmanager, bedrock-runtime, bedrock-mantle) | ~$0.04 / h | 3 AZs each |
| Aurora Serverless v2 | $0 compute when paused; ~0.5 ACU floor while DR is on | storage per GB-month |
| Valkey serverless | per GB stored + ECPU | capped by usage limits |
| CloudFront + WAF | WAF ~$0.01 / h (ACL + rules) + requests | |
| Amazon Managed Prometheus / Grafana | cents / h with the keep-list; Grafana ~$9 in a month an editor logs in | |
| Bedrock (Titan + Claude) | per token | RAG token panel; cache cuts repeats |
| Shared: KMS keys, Config, GuardDuty, Security Hub | a few $ / month | while shared/security exists |

## Actuals
| Run | Dates | Total USD | Top 3 services | Notes |
|---|---|---|---|---|
| | | | | |
