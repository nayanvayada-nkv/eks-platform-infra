#!/usr/bin/env bash
# Builds dev stacks in dependency order. Never touches bootstrap.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/check-bootstrap.sh"
STACKS=(environments/dev/network environments/dev/eks environments/dev/platform)
for S in "${STACKS[@]}"; do
  if [ -d "$ROOT/$S" ]; then
    echo "==> $S"
    "$ROOT/scripts/tf.sh" "$S" init
    "$ROOT/scripts/tf.sh" "$S" plan
    read -r -p "Apply $S? (yes/no): " OK
    [ "$OK" = "yes" ] || { echo "Stopped at $S."; exit 1; }
    "$ROOT/scripts/tf.sh" "$S" apply
  fi
done
