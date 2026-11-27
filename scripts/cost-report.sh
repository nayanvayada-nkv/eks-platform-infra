#!/usr/bin/env bash
# Cost of the project for a date range, per AWS service (Phase 8 cost report).
# Usage: scripts/cost-report.sh <start YYYY-MM-DD> <end YYYY-MM-DD, exclusive>
# Read-only Cost Explorer call (about $0.01 per request). Paste the table into docs/cost-report.md.
set -euo pipefail
START="${1:?Usage: cost-report.sh <start YYYY-MM-DD> <end YYYY-MM-DD>}"
END="${2:?Usage: cost-report.sh <start YYYY-MM-DD> <end YYYY-MM-DD>}"
export AWS_PROFILE="${AWS_PROFILE:-zte-dev}"
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
aws ce get-cost-and-usage --region us-east-1 \
  --time-period "Start=$START,End=$END" --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE --output json |
  python3 -c '
import json, sys
rows = {}
for period in json.load(sys.stdin)["ResultsByTime"]:
    for g in period["Groups"]:
        rows[g["Keys"][0]] = rows.get(g["Keys"][0], 0) + float(g["Metrics"]["UnblendedCost"]["Amount"])
total = sum(rows.values())
print("| Service | USD |\n|---|---:|")
for name, amount in sorted(rows.items(), key=lambda r: -r[1]):
    if amount >= 0.005:
        print(f"| {name} | {amount:.2f} |")
print(f"| **Total** | **{total:.2f}** |")
'
