#!/usr/bin/env bash
# queue-phase.sh — ledger-recording dispatch wrapper.
#
# Runs the super-agent dispatch script for the given worker, teeing stdout,
# parses the printed task ID, and (on success) appends one line to the
# dispatch-ledger and a phase_queued event to the project events.
#
# Usage:
#   queue-phase.sh <project-path> <phase-name> [--worker hetzner|wsl2] [--repo <id>] [--priority <n>] <task-text>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${ORCH_STATE_DIR:-$HOME/.orchestrator}"
LEDGER="$STATE_DIR/dispatch-ledger.jsonl"
REGISTRY="$STATE_DIR/active-projects.json"
SUPER_AGENT_DIR="${SUPER_AGENT_DIR:-$HOME/awesome/super-agent}"

usage() {
    cat >&2 <<'EOF'
Usage:
  queue-phase.sh <project-path> <phase-name> [--worker hetzner|wsl2] [--repo <id>] [--priority <n>] <task-text>
EOF
    exit 1
}

[[ $# -lt 3 ]] && usage

PROJECT_PATH="$1"; shift
PHASE_NAME="$1"; shift

WORKER=""
REPO=""
PRIORITY=""
TASK_TEXT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --worker)   WORKER="$2"; shift 2 ;;
        --repo)     REPO="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --)         shift; TASK_TEXT="$*"; break ;;
        *)          TASK_TEXT="$1"; shift; break ;;
    esac
done
if [[ -z "$TASK_TEXT" ]]; then
    echo "task text required" >&2
    usage
fi

ABS_PROJECT_PATH="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
    echo "project path not found: $PROJECT_PATH" >&2
    exit 1
}

# --- Resolve project name ---
PROJECT_NAME=""
if [[ -f "$REGISTRY" ]]; then
    PROJECT_NAME="$(jq -r --arg p "$ABS_PROJECT_PATH" 'map(select(.local_path == $p)) | first.name // empty' "$REGISTRY" 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_NAME" ]]; then
    STATUS_JSON="$ABS_PROJECT_PATH/.planning/status.json"
    if [[ -f "$STATUS_JSON" ]]; then
        PROJECT_NAME="$(jq -r '.project // empty' "$STATUS_JSON" 2>/dev/null || true)"
    fi
fi
if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$(basename "$ABS_PROJECT_PATH")"
fi

# --- Resolve worker (registry default → 'hetzner') ---
if [[ -z "$WORKER" ]] && [[ -f "$REGISTRY" ]]; then
    WORKER="$(jq -r --arg n "$PROJECT_NAME" 'map(select(.name == $n)) | first.worker // empty' "$REGISTRY" 2>/dev/null || true)"
fi
WORKER="${WORKER:-hetzner}"
if [[ "$WORKER" != "hetzner" && "$WORKER" != "wsl2" ]]; then
    echo "worker must be hetzner or wsl2 (got: $WORKER)" >&2
    exit 1
fi

# --- Resolve dispatch script ---
case "$WORKER" in
    hetzner) DISPATCH="$SUPER_AGENT_DIR/scripts/add-task.sh" ;;
    wsl2)    DISPATCH="$SUPER_AGENT_DIR/scripts/add-task-local.sh" ;;
esac
if [[ ! -x "$DISPATCH" ]]; then
    echo "dispatch script not found or not executable: $DISPATCH" >&2
    exit 1
fi

# --- Ensure state dir ---
if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
fi

# --- Build dispatcher arg list (flags first, then task text) ---
dispatch_args=()
[[ -n "$REPO" ]]     && dispatch_args+=(--repo "$REPO")
[[ -n "$PRIORITY" ]] && dispatch_args+=(--priority "$PRIORITY")
dispatch_args+=("$TASK_TEXT")

# --- Run + capture ---
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

set +e
"$DISPATCH" "${dispatch_args[@]}" 2>&1 | tee "$TMP_OUT"
DISPATCH_EXIT="${PIPESTATUS[0]}"
set -e

# --- Detect failure modes ---
if [[ "$DISPATCH_EXIT" -ne 0 ]]; then
    echo "queue-phase: dispatch exited non-zero ($DISPATCH_EXIT); ledger NOT written" >&2
    exit 1
fi
if grep -q '^Task saved locally:' "$TMP_OUT"; then
    echo "queue-phase: dispatch fell back to local queue (Task saved locally); ledger NOT written" >&2
    exit 1
fi
if ! grep -q '^Task queued:' "$TMP_OUT"; then
    echo "queue-phase: dispatch did not print 'Task queued:'; ledger NOT written" >&2
    exit 1
fi

# --- Parse task_id from the earliest 'ID: <digits>' line ---
TASK_ID="$(grep -oE '^ID: [0-9]+' "$TMP_OUT" | head -1 | awk '{print $2}')"
if [[ -z "$TASK_ID" ]]; then
    echo "queue-phase: could not parse task id from dispatch output; ledger NOT written" >&2
    exit 1
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Append ledger line (task_id as string; jq -c) ---
LEDGER_LINE="$(jq -c -n \
    --arg ts "$NOW" \
    --arg task_id "$TASK_ID" \
    --arg project "$PROJECT_NAME" \
    --arg project_path "$ABS_PROJECT_PATH" \
    --arg phase "$PHASE_NAME" \
    --arg worker "$WORKER" \
    '{ts: $ts, task_id: $task_id, project: $project, project_path: $project_path, phase: $phase, worker: $worker}')"
printf '%s\n' "$LEDGER_LINE" >> "$LEDGER"

# --- Append project event (skip with warning if .planning/ missing) ---
PLANNING_DIR="$ABS_PROJECT_PATH/.planning"
if [[ -d "$PLANNING_DIR" ]]; then
    EVENT_LINE="$(jq -c -n \
        --arg ts "$NOW" \
        --arg phase "$PHASE_NAME" \
        --arg task_id "$TASK_ID" \
        --arg worker "$WORKER" \
        '{ts: $ts, event: "phase_queued", data: {phase: $phase, task_id: $task_id, worker: $worker}}')"
    printf '%s\n' "$EVENT_LINE" >> "$PLANNING_DIR/events.jsonl"
else
    echo "queue-phase: $PLANNING_DIR missing; skipped phase_queued event write" >&2
fi

echo "LEDGER: task $TASK_ID -> $PROJECT_NAME/$PHASE_NAME ($WORKER)"
