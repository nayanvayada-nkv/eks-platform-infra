#!/usr/bin/env bash
# Usage: [WORKSPACE=dr] scripts/tf.sh <stack-path> <init|plan|apply|destroy>
# WORKSPACE (default "default" = Mumbai) selects a Terraform workspace; any other workspace
# also loads <stack>/<workspace>.tfvars, e.g. dr.tfvars for the Frankfurt DR copy (Phase 7).
set -euo pipefail
STACK="${1:?Usage: tf.sh <stack-path> <init|plan|apply|destroy>}"
ACTION="${2:?Usage: tf.sh <stack-path> <init|plan|apply|destroy>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${WORKSPACE:-default}"
export AWS_PROFILE="${AWS_PROFILE:-zte-dev}"
export AWS_REGION="${AWS_REGION:-ap-south-1}"
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"
echo "Stack: $STACK  Workspace: $WORKSPACE"
cd "$ROOT/$STACK"

VARFILE=()
if [ "$WORKSPACE" != "default" ]; then
  [ -f "$WORKSPACE.tfvars" ] || { echo "Missing $STACK/$WORKSPACE.tfvars (copy $WORKSPACE.tfvars.example)."; exit 1; }
  VARFILE=(-var-file="$WORKSPACE.tfvars")
fi

case "$ACTION" in
  init)    terraform init -backend-config="$ROOT/environments/backend.hcl"
           terraform workspace select -or-create "$WORKSPACE" ;;
  plan)    terraform workspace select "$WORKSPACE"
           terraform fmt -recursive; terraform validate
           terraform plan "${VARFILE[@]}" -out=tfplan ;;
  apply)   [ -f tfplan ] || { echo "No tfplan found. Run plan first."; exit 1; }
           terraform workspace select "$WORKSPACE"
           terraform apply tfplan; rm -f tfplan ;;
  destroy) terraform workspace select "$WORKSPACE"
           terraform destroy "${VARFILE[@]}" ;;
  *)       echo "Unknown action: $ACTION"; exit 1 ;;
esac
