#!/usr/bin/env bash
# Loads the Grafana dashboards from Git (environments/dev/observability/dashboards) into
# Amazon Managed Grafana. Uses the short-lived service-account token from Terraform output;
# the token is never printed. Run after `scripts/tf.sh environments/dev/observability apply`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK="$ROOT/environments/dev/observability"

GRAFANA_URL="$(terraform -chdir="$STACK" output -raw grafana_url)"
GRAFANA_TOKEN="$(terraform -chdir="$STACK" output -raw grafana_dashboards_token)"
export GRAFANA_TOKEN

for f in "$STACK"/dashboards/*.json; do
  echo "==> $(basename "$f")"
  python3 -c 'import json,sys; print(json.dumps({"dashboard": json.load(open(sys.argv[1])), "overwrite": True}))' "$f" |
    curl -fsS -X POST "$GRAFANA_URL/api/dashboards/db" \
      -H "Authorization: Bearer $GRAFANA_TOKEN" \
      -H "Content-Type: application/json" \
      --data-binary @- >/dev/null
  echo "    loaded"
done
echo "Open $GRAFANA_URL and pick the Amazon Managed Prometheus data source in each dashboard."
