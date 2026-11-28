#!/usr/bin/env bash
# Phase 7 DR drill: moves the Aurora writer between Mumbai and Frankfurt and measures
#   RTO (database): until the target cluster is the global writer
#   RTO (app):      until the target region's API accepts a write again
#   RPO:            whether a marker written just before the move survived
# Usage: scripts/dr-drill.sh dr|home [switchover|failover]
#   switchover = planned, no data loss (default). failover = simulated outage, allows data loss.
set -euo pipefail
TARGET="${1:?Usage: dr-drill.sh dr|home [switchover|failover]}"
MODE="${2:-switchover}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export AWS_PROFILE="${AWS_PROFILE:-zte-dev}"
HOME_REGION=ap-south-1
DR_REGION=eu-central-1

out() { # out <workspace> <stack> <output>
  TF_WORKSPACE="$1" terraform -chdir="$ROOT/environments/dev/$2" output -raw "$3"
}

GLOBAL_ID="$(out default data global_cluster_id)"
[ -n "$GLOBAL_ID" ] || { echo "No global database: set dr_region in the Mumbai data stack first."; exit 1; }
HOME_ARN="$(out default data cluster_arn)"
DR_ARN="$(out dr data cluster_arn)"
HOME_URL="$(out default edge url)"
DR_URL="$(out dr edge url)"

case "$TARGET" in
  dr)   TARGET_ARN="$DR_ARN";   TARGET_URL="$DR_URL";   FROM_URL="$HOME_URL"; TARGET_REGION="$DR_REGION" ;;
  home) TARGET_ARN="$HOME_ARN"; TARGET_URL="$HOME_URL"; FROM_URL="$DR_URL";   TARGET_REGION="$HOME_REGION" ;;
  *)    echo "Target must be dr or home."; exit 1 ;;
esac
case "$MODE" in
  switchover) API=switchover-global-cluster; EXTRA=() ;;
  failover)   API=failover-global-cluster;   EXTRA=(--allow-data-loss) ;;
  *)          echo "Mode must be switchover or failover."; exit 1 ;;
esac

MEMBERS="$(aws rds describe-db-clusters --region "$TARGET_REGION" --db-cluster-identifier "$TARGET_ARN" \
  --query 'length(DBClusters[0].DBClusterMembers)' --output text)"
[ "$MEMBERS" -ge 1 ] || { echo "Target cluster has no instance (headless). Set dr_instances = 1 and apply the dr data stack first."; exit 1; }

echo "Global cluster: $GLOBAL_ID"
echo "Move writer to: $TARGET_ARN ($MODE)"
read -r -p "Type 'drill' to start: " ANSWER
[ "$ANSWER" = "drill" ] || { echo "Cancelled."; exit 1; }

MARKER="drill-$(date +%s)"
echo "Writing marker $MARKER through $FROM_URL"
curl -fsS -X POST "$FROM_URL/items" -H 'Content-Type: application/json' -d "{\"name\":\"$MARKER\"}"; echo

T0="$(date +%s)"
aws rds "$API" --region "$TARGET_REGION" --global-cluster-identifier "$GLOBAL_ID" \
  --target-db-cluster-identifier "$TARGET_ARN" "${EXTRA[@]}" >/dev/null
echo "$API started at $(date -u -d "@$T0" +%H:%M:%SZ)"

until [ "$(aws rds describe-global-clusters --region "$TARGET_REGION" --global-cluster-identifier "$GLOBAL_ID" \
  --query "GlobalClusters[0].GlobalClusterMembers[?IsWriter].DBClusterArn | [0]" --output text)" = "$TARGET_ARN" ] &&
  [ "$(aws rds describe-global-clusters --region "$TARGET_REGION" --global-cluster-identifier "$GLOBAL_ID" \
  --query 'GlobalClusters[0].Status' --output text)" = "available" ]; do
  sleep 10
done
T_DB="$(date +%s)"
echo "Database writer moved after $(( T_DB - T0 )) s"

until curl -fsS -o /dev/null -X POST "$TARGET_URL/items" -H 'Content-Type: application/json' \
  -d "{\"name\":\"after-$MARKER\"}"; do
  sleep 10
done
T_APP="$(date +%s)"

if curl -fsS "$TARGET_URL/items" | grep -q "\"$MARKER\""; then RPO="0 (marker replicated)"; else RPO="DATA LOST (marker missing)"; fi

echo
echo "================ DR drill result ================"
echo "Mode:            $MODE to $TARGET"
echo "RTO (database):  $(( T_DB - T0 )) s"
echo "RTO (app write): $(( T_APP - T0 )) s"
echo "RPO:             $RPO"
echo "Pilot-light full RTO also includes building DR compute (scripts/up-dr.sh prints it)."
