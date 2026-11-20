#!/usr/bin/env bash
# Service layer smoke: health, version and the index listing must answer.
# Requests retry on 503: during a Prod traffic shift the ALB answers 503 for the
# share weighted to a target group with no targets (the first Prod release has
# no blue service).
# Usage: smoke-service-layer.sh BASE_URL
set -euo pipefail

BASE_URL="${1:?base url}"
# Not /dev/null: a retry rewrites the output file and fails with exit 23 if it can't truncate it.
out=$(mktemp)
trap 'rm -f "$out"' EXIT
for path in /actuator/health /api/version /api/indices; do
  code=$(curl -s -o "$out" -w '%{http_code}' --max-time 10 --retry 15 --retry-delay 1 --retry-max-time 60 "$BASE_URL$path" || echo 000)
  echo "GET $path -> $code"
  [ "$code" = "200" ] || { echo "service-layer smoke failed on $path"; exit 1; }
done
echo "service-layer smoke passed"
