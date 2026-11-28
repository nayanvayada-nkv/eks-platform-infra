#!/usr/bin/env bash
# Usage: scripts/tf.sh <stack-path> <init|plan|apply|destroy>
set -euo pipefail
STACK="${1:?Usage: tf.sh <stack-path> <init|plan|apply|destroy>}"
ACTION="${2:?Usage: tf.sh <stack-path> <init|plan|apply|destroy>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-zte-dev}"
export AWS_REGION="${AWS_REGION:-ap-south-1}"
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
cd "$ROOT/$STACK"
case "$ACTION" in
  init)    terraform init -backend-config="$ROOT/environments/backend.hcl" ;;
  plan)    terraform fmt -recursive; terraform validate; terraform plan -out=tfplan ;;
  apply)   [ -f tfplan ] || { echo "No tfplan found. Run plan first."; exit 1; }
           terraform apply tfplan; rm -f tfplan ;;
  destroy) terraform destroy ;;
  *)       echo "Unknown action: $ACTION"; exit 1 ;;
esac
