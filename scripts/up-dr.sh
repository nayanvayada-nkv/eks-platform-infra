#!/usr/bin/env bash
# Builds the Frankfurt DR copy (Phase 7, pilot light) from the same stacks as Mumbai, in the
# "dr" workspace with each stack's dr.tfvars. Mumbai must already run with dr_region set in
# its data stack (Aurora Global Database) and replication_regions in shared/supply-chain.
# No observability stack in DR by default (cost); platform treats it as optional.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WORKSPACE=dr
"$ROOT/scripts/check-bootstrap.sh"
STACKS=(environments/dev/network environments/dev/eks environments/dev/data environments/dev/edge environments/dev/platform)
START="$(date +%s)"
for S in "${STACKS[@]}"; do
  echo "==> $S (dr)"
  "$ROOT/scripts/tf.sh" "$S" init
  "$ROOT/scripts/tf.sh" "$S" plan
  read -r -p "Apply $S in the dr workspace? (yes/no): " OK
  [ "$OK" = "yes" ] || { echo "Stopped at $S."; exit 1; }
  "$ROOT/scripts/tf.sh" "$S" apply
done
echo "DR build took $(( $(date +%s) - START )) s (part of the pilot-light RTO; includes your review time)."
