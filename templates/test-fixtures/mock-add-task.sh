#!/usr/bin/env bash
# mock-add-task.sh — hermetic mock of super-agent's add-task.sh / add-task-local.sh.
# Mirrors the real contract: accepts optional --repo/--priority flags, then a task-text
# arg; prints "ID: <18-digit id>" and "Task queued: <id>"; exits 0.
#
# Env overrides for failure-path testing:
#   MOCK_ADDTASK_FAIL=1  → simulate local-fallback (prints "Task saved locally: /tmp/x.json", exits 0)
#   MOCK_ADDTASK_EXIT=1  → exits non-zero without queueing

set -euo pipefail

REPO=""
PRIORITY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)     REPO="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        *)          break ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "mock-add-task: task text required" >&2
    exit 2
fi

TASK_TEXT="$1"

# Generate an 18-digit id (nanoseconds since epoch, padded).
TASK_ID="$(printf '%018d' "$(date +%s%N)")"
TASK_ID="${TASK_ID: -18}"

if [[ "${MOCK_ADDTASK_EXIT:-0}" == "1" ]]; then
    echo "mock-add-task: forced exit 1" >&2
    exit 1
fi

if [[ "${MOCK_ADDTASK_FAIL:-0}" == "1" ]]; then
    echo "mock-add-task: queue unreachable, falling back to local file" >&2
    echo "Task saved locally: /tmp/mock-fallback-$TASK_ID.json"
    exit 0
fi

echo "ID: $TASK_ID"
[[ -n "$REPO" ]]     && echo "repo: $REPO"
[[ -n "$PRIORITY" ]] && echo "priority: $PRIORITY"
echo "task: $TASK_TEXT"
echo "Task queued: $TASK_ID"
exit 0
