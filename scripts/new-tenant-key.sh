#!/usr/bin/env bash
# Creates an API key for a new RAG tenant (Phase 9 / FDE onboarding).
# Prints the key ONCE (give it to the customer over a secure channel) and the entry to add
# to gitops/workloads/backend/tenants/tenants.yaml. Nothing is stored or sent anywhere.
# Usage: scripts/new-tenant-key.sh <tenant-id> "<Display Name>"
set -euo pipefail
ID="${1:?Usage: new-tenant-key.sh <tenant-id> \"<Display Name>\"}"
NAME="${2:?Usage: new-tenant-key.sh <tenant-id> \"<Display Name>\"}"
[[ "$ID" =~ ^[a-z0-9-]{3,40}$ ]] || { echo "tenant-id: 3-40 characters, a-z 0-9 and -"; exit 1; }

KEY="tk_$(openssl rand -hex 32)" # 256 random bits
HASH="$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)"

echo "API key for $ID (shown once, not saved):"
echo "  $KEY"
echo
echo "Add this entry to the JSON list in gitops/workloads/backend/tenants/tenants.yaml:"
printf '  {"id": "%s", "name": "%s", "apiKeySha256": "%s"}\n' "$ID" "$NAME" "$HASH"
