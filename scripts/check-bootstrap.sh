#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-zte-dev}"
BUCKET="$(grep -E '^bucket' "$ROOT/environments/backend.hcl" | cut -d'"' -f2)"
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
aws s3 ls "s3://${BUCKET}/bootstrap/" || { echo "Bootstrap state NOT found. Apply the bootstrap first."; exit 1; }
echo "Bootstrap OK"
