#!/usr/bin/env bash
# Uploads every .md file in a folder as documents for one tenant (FDE onboarding step 4).
# Usage: URL=https://<cloudfront> KEY=tk_... scripts/fde-load-docs.sh docs/fde/sample-data
set -euo pipefail
DIR="${1:?Usage: URL=... KEY=... fde-load-docs.sh <folder>}"
: "${URL:?set URL to the API base URL}"
: "${KEY:?set KEY to the tenant API key}"
for f in "$DIR"/*.md; do
  title="$(basename "$f" .md)"
  python3 -c 'import json,sys; print(json.dumps({"title": sys.argv[1], "content": open(sys.argv[2]).read()}))' "$title" "$f" |
    curl -fsS -X POST "${URL%/}/documents" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' --data-binary @- |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("title"), "- chunks:", d.get("chunks"))'
done
