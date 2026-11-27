#!/usr/bin/env bash
# Destroys dev stacks in reverse order to save cost. Never touches bootstrap.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACKS=(environments/dev/eks environments/dev/network)
read -r -p "Type 'destroy-dev' to destroy the dev stacks: " ANSWER
[ "$ANSWER" = "destroy-dev" ] || { echo "Cancelled."; exit 1; }
for S in "${STACKS[@]}"; do
  case "$S" in environments/dev/*) ;; *) echo "Refusing non-dev stack: $S"; exit 1 ;; esac
  if [ -d "$ROOT/$S" ]; then
    echo "==> Destroying $S"
    "$ROOT/scripts/tf.sh" "$S" destroy
  fi
done
