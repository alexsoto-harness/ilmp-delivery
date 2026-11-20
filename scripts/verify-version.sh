#!/usr/bin/env bash
# FR-008 verify: the endpoint must report the digest this pipeline deployed on
# 3 consecutive reads (so no old task is still answering behind the ALB).
# Usage: verify-version.sh VERSION_URL EXPECTED_DIGEST [EXPECTED_TASKDEF] [TIMEOUT_SECONDS]
set -euo pipefail

URL="${1:?version url}"
EXPECTED="${2:?expected digest}"
EXPECTED_TASKDEF="${3:-}"
TIMEOUT="${4:-180}"

field() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }

streak=0
deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  body=$(curl -fsS "$URL" || true)
  digest=$(echo "$body" | field image_digest)
  taskdef=$(echo "$body" | field task_definition)
  if [ "$digest" = "$EXPECTED" ] && { [ -z "$EXPECTED_TASKDEF" ] || [ "$taskdef" = "$EXPECTED_TASKDEF" ]; }; then
    streak=$((streak + 1))
    echo "  match $streak/3: $digest $taskdef"
    if [ "$streak" -ge 3 ]; then
      echo "verified: running $digest ($taskdef)"
      exit 0
    fi
  else
    streak=0
    echo "  running ${digest:-?} ${taskdef:-} (want $EXPECTED ${EXPECTED_TASKDEF})"
  fi
  sleep 5
done
echo "FR-008 verify failed: $URL never reported $EXPECTED"
exit 1
