#!/usr/bin/env bash
# Service layer smoke: health, version and the index listing must answer.
# Usage: smoke-service-layer.sh BASE_URL
set -euo pipefail

BASE_URL="${1:?base url}"
for path in /actuator/health /api/version /api/indices; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL$path" || echo 000)
  echo "GET $path -> $code"
  [ "$code" = "200" ] || { echo "service-layer smoke failed on $path"; exit 1; }
done
echo "service-layer smoke passed"
