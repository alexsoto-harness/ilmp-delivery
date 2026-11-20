#!/usr/bin/env bash
# FR-009 smoke backtest: POST /backtest, poll until COMPLETED. Anything else
# (FAILED, timeout, unreachable) exits 1 so the stage rolls back.
# Usage: smoke-backtest.sh BASE_URL [DAYS] [TIMEOUT_SECONDS]
set -euo pipefail

BASE_URL="${1:?base url}"
DAYS="${2:-3}"
TIMEOUT="${3:-120}"

field() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",}]*\).*/\1/p"; }

job=$(curl -fsS -X POST "$BASE_URL/backtest" -H 'Content-Type: application/json' \
  -d "{\"index_id\":\"SPDJI-DEMO-50\",\"days\":$DAYS}")
job_id=$(echo "$job" | field job_id)
[ -n "$job_id" ] || { echo "no job_id in response: $job"; exit 1; }
echo "smoke backtest $job_id ($DAYS days) against $BASE_URL"

deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  body=$(curl -fsS "$BASE_URL/backtest/$job_id" || true)
  status=$(echo "$body" | field status)
  echo "  status=$status"
  case "$status" in
    COMPLETED) echo "smoke backtest COMPLETED: $body"; exit 0 ;;
    FAILED) echo "smoke backtest FAILED: $body"; exit 1 ;;
  esac
  sleep 3
done
echo "smoke backtest timed out after ${TIMEOUT}s"
exit 1
