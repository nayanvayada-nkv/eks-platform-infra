#!/usr/bin/env bash
# Runs the Locust load test headless from this machine against the API (Phase 8).
# Usage: URL=https://<cloudfront> [RAG_KEY=tk_...] scripts/loadtest.sh <smoke|ramp|spike|soak>
# Results (CSV + HTML report) go to loadtest/results/<profile>-<time>/ (git-ignored).
# Before ramp/spike/soak: open the WAF rate limit for the test window (docs/runbooks/load-test.md).
set -euo pipefail
PROFILE="${1:?Usage: URL=... loadtest.sh <smoke|ramp|spike|soak>}"
: "${URL:?set URL to the API base URL}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/loadtest/.venv"
OUT="$ROOT/loadtest/results/$PROFILE-$(date +%Y%m%d-%H%M%S)"

[ -x "$VENV/bin/locust" ] || { python3 -m venv "$VENV"; "$VENV/bin/pip" install -q -r "$ROOT/loadtest/requirements.txt"; }
mkdir -p "$OUT"
export LOAD_PROFILE="$PROFILE"
echo "Load test '$PROFILE' against $URL -> $OUT"
"$VENV/bin/locust" -f "$ROOT/loadtest/locustfile.py" --headless --host "${URL%/}" \
  --csv "$OUT/stats" --html "$OUT/report.html" --only-summary
