#!/usr/bin/env bash
# mock-pm-iterate.sh — hermetic mock of scripts/pm-iterate.sh used by the r1-03
# daemon smoke tests. Records each invocation (all argv) as a single JSON line
# to $MOCK_PM_LOG; behaviour tuned by env:
#   MOCK_PM_EXIT    — exit code (default 0)
#   MOCK_PM_STDOUT  — stdout line (default 'RAN: exit=0 transcript=/dev/null')
#
# Also honours MOCK_PM_SLEEP (seconds) so single-flight tests can force overlap.

set -euo pipefail

LOG="${MOCK_PM_LOG:-/dev/null}"
EXIT_CODE="${MOCK_PM_EXIT:-0}"
STDOUT="${MOCK_PM_STDOUT:-RAN: exit=0 transcript=/dev/null}"

TS="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build a JSON array of argv strings without relying on jq or python.
argv_json='['
first=1
for a in "$@"; do
    if [[ $first -eq 1 ]]; then first=0; else argv_json+=","; fi
    # Escape backslashes, double quotes, control chars.
    esc="${a//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    esc="${esc//$'\n'/\\n}"
    esc="${esc//$'\r'/\\r}"
    esc="${esc//$'\t'/\\t}"
    argv_json+="\"$esc\""
done
argv_json+="]"

echo "{\"ts\":\"$TS\",\"pid\":$$,\"argv\":$argv_json,\"exit\":$EXIT_CODE}" >> "$LOG"

if [[ -n "${MOCK_PM_SLEEP:-}" ]]; then
    sleep "$MOCK_PM_SLEEP"
fi

echo "$STDOUT"
exit "$EXIT_CODE"
