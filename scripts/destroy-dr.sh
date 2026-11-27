#!/usr/bin/env bash
# Destroys the Frankfurt DR copy (dr workspace) in reverse order. Never touches Mumbai.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WORKSPACE=dr
STACKS=(environments/dev/platform environments/dev/edge environments/dev/data environments/dev/eks environments/dev/network)
echo "Before continuing, in the DR cluster: kubectl -n argocd delete application root-dev"
echo "If the drill left Frankfurt as the Aurora writer, switch back first: scripts/dr-drill.sh home"
read -r -p "Type 'destroy-dr' to destroy the DR stacks: " ANSWER
[ "$ANSWER" = "destroy-dr" ] || { echo "Cancelled."; exit 1; }
for S in "${STACKS[@]}"; do
  echo "==> Destroying $S (dr)"
  "$ROOT/scripts/tf.sh" "$S" destroy
done
