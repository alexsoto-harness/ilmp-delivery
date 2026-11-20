#!/usr/bin/env bash
# Read releases/<release>.yaml and print shell exports for ILMP Deploy.
# Fails closed: both components must be present with a well-formed digest and
# a PASS Eval verdict bound to that digest.
# Usage: eval "$(resolve-release.sh RELEASE [RELEASES_DIR])"
set -euo pipefail

release="${1:?release}"
dir="${2:-$(dirname "$0")/../releases}"
file="$dir/$release.yaml"
[ -f "$file" ] || { echo "no release manifest $file" >&2; exit 1; }

get() {
  awk -v c="$1" -v k="$2" '
    $0 == "  " c ":" { f = 1; next }
    /^  [^ ]/        { f = 0 }
    f && $1 == k ":" { gsub(/"/, "", $2); print $2; exit }' "$file"
}

emit() {
  local comp="$1" prefix="$2" digest tag verdict
  digest=$(get "$comp" digest); tag=$(get "$comp" tag); verdict=$(get "$comp" eval_verdict)
  [ -n "$digest" ] || { echo "release $release has no $comp build; build it first" >&2; exit 1; }
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "$comp digest malformed: $digest" >&2; exit 1; }
  [ "$verdict" = "PASS" ] || { echo "$comp Eval verdict is '$verdict', not PASS" >&2; exit 1; }
  printf 'export %s_DIGEST=%q %s_TAG=%q %s_COMMIT=%q %s_BUILD=%q\n' \
    "$prefix" "$digest" "$prefix" "$tag" "$prefix" "$(get "$comp" commit)" "$prefix" "$(get "$comp" build_url)"
}

emit calc-engine CALC
emit service-layer SVC
