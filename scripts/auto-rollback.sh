#!/usr/bin/env bash
# auto-rollback.sh — Automatically revert last merged phase if regression tests fail
#
# Usage: auto-rollback.sh <worker> <project-path>
#
# Flow:
#   1. Read events.jsonl to find most recent phase_merged event
#   2. Run regression-test.sh to check current state
#   3. If regression passes → exit 0 (project healthy)
#   4. If regression fails → revert last merged phase via git revert
#      - Update status.json: set phase status to "rolled_back"
#      - Log "phase_rolled_back" event to events.jsonl
#      - Call notify.sh with regression_failed event
#      - Exit 1
#   5. If revert conflicts → exit 2 (escalate to PM, don't force)
#
# Exit codes:
#   0 — Regression tests pass, project is healthy
#   1 — Regression failed, phase was rolled back
#   2 — Revert conflict, manual intervention required

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Usage ---
usage() {
    cat >&2 <<'EOF'
Usage: auto-rollback.sh <worker> <project-path>

Runs regression tests and automatically reverts the last merged phase if tests fail.

Arguments:
  worker         Worker name from config/workers.json (e.g., hetzner, wsl2)
  project-path   Absolute path to the project directory

Exit codes:
  0 — Regression tests pass, project is healthy
  1 — Regression failed, phase was rolled back
  2 — Revert conflict, manual intervention required

Examples:
  auto-rollback.sh hetzner /home/mp/awesome/blog-publisher
  auto-rollback.sh wsl2 /home/user/projects/my-app
EOF
    exit 1
}

# --- Argument parsing ---
if [[ $# -lt 2 ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    usage
fi

WORKER="$1"
PROJECT_PATH="$2"

STATUS_FILE="$PROJECT_PATH/.planning/status.json"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Validate inputs ---
if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "❌ Error: Project path '$PROJECT_PATH' does not exist" >&2
    exit 1
fi

if [[ ! -f "$STATUS_FILE" ]]; then
    echo "❌ Error: status.json not found at $STATUS_FILE" >&2
    exit 1
fi

if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "❌ Error: events.jsonl not found at $EVENTS_FILE" >&2
    exit 1
fi

# --- Get worker config via get-worker.sh ---
SSH_CMD=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" ssh_cmd 2>&1) || {
    echo "❌ Failed to get worker config: $SSH_CMD" >&2
    exit 1
}
REMOTE_BASE=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" base_path 2>&1) || {
    echo "❌ Failed to get worker base_path: $REMOTE_BASE" >&2
    exit 1
}

PROJECT_NAME="$(basename "$PROJECT_PATH")"
REMOTE_PROJECT="$REMOTE_BASE/$PROJECT_NAME"

# --- SSH retry helper (from verify.sh pattern) ---
ssh_retry() {
    local max_retries=2
    local attempt=0
    local backoff=3
    local result=""
    local exit_code=0

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 0 ]]; then
            echo "  ↻ Retry $attempt/$max_retries (waiting ${backoff}s)..." >&2
            sleep $backoff
            backoff=$((backoff * 2))
        fi

        result=$($SSH_CMD "$@" 2>&1) && exit_code=0 || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "$result"
            return 0
        fi

        # Retry only on connection errors
        if echo "$result" | grep -qi "connection\|timeout\|refused\|reset\|network"; then
            attempt=$((attempt + 1))
        else
            echo "$result"
            return $exit_code
        fi
    done

    echo "SSH_RETRY_EXHAUSTED: $result"
    return 1
}

# --- Find last merged phase from events.jsonl ---
echo "========================================"
echo "Auto-Rollback Check"
echo "========================================"
echo ""
echo "Worker: $WORKER"
echo "Project: $PROJECT_PATH"
echo ""

# Find the most recent phase_merged event
LAST_MERGE=$(grep '"phase_merged"' "$EVENTS_FILE" | tail -1 || echo "")

if [[ -z "$LAST_MERGE" ]]; then
    echo "ℹ️  No phase_merged events found in events.jsonl — nothing to rollback."
    echo "   Project has no recent merges to test against."
    exit 0
fi

# Extract phase name and commit hash from the merge event
MERGED_PHASE=$(echo "$LAST_MERGE" | jq -r '.data.phase // empty' 2>/dev/null || echo "")
MERGE_COMMIT=$(echo "$LAST_MERGE" | jq -r '.data.commit // empty' 2>/dev/null || echo "")
MERGE_TS=$(echo "$LAST_MERGE" | jq -r '.ts // empty' 2>/dev/null || echo "")

if [[ -z "$MERGED_PHASE" ]]; then
    echo "❌ Error: Could not parse phase name from last phase_merged event" >&2
    echo "   Raw event: $LAST_MERGE" >&2
    exit 1
fi

echo "Last merged phase: $MERGED_PHASE"
echo "Merge commit: ${MERGE_COMMIT:-unknown}"
echo "Merged at: ${MERGE_TS:-unknown}"
echo ""

# --- Run regression tests ---
echo "Running regression tests..."
echo ""

REGRESSION_OUTPUT=""
REGRESSION_EXIT=0

REGRESSION_OUTPUT=$(bash "$SCRIPT_DIR/regression-test.sh" "$PROJECT_PATH" "$WORKER" 2>&1) || REGRESSION_EXIT=$?

echo "$REGRESSION_OUTPUT"
echo ""

# --- If regression passes, project is healthy ---
if [[ $REGRESSION_EXIT -eq 0 ]]; then
    echo "========================================"
    echo "✅ Project healthy — all regression tests pass"
    echo "========================================"

    # Log healthy check event
    echo "{\"ts\":\"$NOW\",\"event\":\"regression_check_passed\",\"data\":{\"last_merged_phase\":\"$MERGED_PHASE\"}}" >> "$EVENTS_FILE"

    exit 0
fi

# --- Regression failed — initiate rollback ---
echo "========================================"
echo "❌ Regression tests FAILED after merging: $MERGED_PHASE"
echo "   Initiating auto-rollback..."
echo "========================================"
echo ""

# Determine the commit to revert
if [[ -z "$MERGE_COMMIT" ]]; then
    # If no commit hash in event, try to find it via git log
    echo "No commit hash in merge event, looking up from git log..."
    MERGE_COMMIT=$(ssh_retry "cd $REMOTE_PROJECT && git log --oneline --grep='Merge phase/$MERGED_PHASE' -1 --format='%H'" 2>/dev/null || echo "")

    if [[ -z "$MERGE_COMMIT" ]]; then
        echo "❌ Error: Cannot find merge commit for phase $MERGED_PHASE" >&2
        echo "   Manual intervention required." >&2

        # Log failed rollback
        echo "{\"ts\":\"$NOW\",\"event\":\"rollback_failed\",\"data\":{\"phase\":\"$MERGED_PHASE\",\"reason\":\"merge_commit_not_found\"}}" >> "$EVENTS_FILE"

        # Notify
        bash "$SCRIPT_DIR/notify.sh" regression_failed "$PROJECT_PATH" \
            --phase "$MERGED_PHASE" \
            --detail "Regression failed but merge commit not found. Manual rollback required."

        exit 2
    fi
fi

echo "Reverting commit: $MERGE_COMMIT"

# --- Attempt git revert ---
REVERT_OUTPUT=""
REVERT_EXIT=0

REVERT_OUTPUT=$(ssh_retry "cd $REMOTE_PROJECT && git revert --no-commit $MERGE_COMMIT && git commit -m 'Auto-rollback: $MERGED_PHASE broke regression tests'" 2>&1) || REVERT_EXIT=$?

if [[ $REVERT_EXIT -ne 0 ]]; then
    # Revert failed — likely a conflict
    echo ""
    echo "❌ REVERT CONFLICT — Cannot auto-rollback cleanly"
    echo "   Output: $REVERT_OUTPUT"
    echo ""
    echo "   Manual intervention required:"
    echo "   1. SSH into >>$WORKER"
    echo "   2. cd $REMOTE_PROJECT"
    echo "   3. git revert --abort  (cancel the failed revert)"
    echo "   4. Manually fix the merge or reset to pre-merge state"
    echo ""

    # Abort the failed revert to leave repo clean
    ssh_retry "cd $REMOTE_PROJECT && git revert --abort" 2>/dev/null || true

    # Log conflict event
    echo "{\"ts\":\"$NOW\",\"event\":\"rollback_conflict\",\"data\":{\"phase\":\"$MERGED_PHASE\",\"commit\":\"$MERGE_COMMIT\"}}" >> "$EVENTS_FILE"

    # Notify
    bash "$SCRIPT_DIR/notify.sh" regression_failed "$PROJECT_PATH" \
        --phase "$MERGED_PHASE" \
        --detail "Regression failed and auto-revert had conflicts. Manual intervention required."

    exit 2
fi

# --- Revert succeeded ---
echo "✅ Revert successful"
echo ""

# Get the rollback commit hash
ROLLBACK_COMMIT=$(ssh_retry "cd $REMOTE_PROJECT && git rev-parse --short HEAD" 2>/dev/null || echo "unknown")

# --- Update status.json: set phase to "rolled_back" ---
echo "Updating status.json..."

jq --arg phase "$MERGED_PHASE" \
   --arg ts "$NOW" \
   --arg commit "$ROLLBACK_COMMIT" \
   '.phases[$phase].status = "rolled_back" |
    .phases[$phase].rolled_back_at = $ts |
    .phases[$phase].rollback_commit = $commit' \
   "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"

echo "  Phase '$MERGED_PHASE' status → rolled_back"

# --- Log event to events.jsonl ---
echo "{\"ts\":\"$NOW\",\"event\":\"phase_rolled_back\",\"data\":{\"phase\":\"$MERGED_PHASE\",\"merge_commit\":\"$MERGE_COMMIT\",\"rollback_commit\":\"$ROLLBACK_COMMIT\",\"reason\":\"regression_tests_failed\"}}" >> "$EVENTS_FILE"

echo "  Event logged to events.jsonl"

# --- Notify via notify.sh ---
bash "$SCRIPT_DIR/notify.sh" regression_failed "$PROJECT_PATH" \
    --phase "$MERGED_PHASE" \
    --detail "Phase $MERGED_PHASE was auto-rolled-back (commit $ROLLBACK_COMMIT). Regression tests failed after merge. Phase reset to rolled_back status — revision spec required."

echo ""
echo "========================================"
echo "Auto-Rollback Complete"
echo "========================================"
echo ""
echo "Phase:           $MERGED_PHASE"
echo "Merge commit:    $MERGE_COMMIT"
echo "Rollback commit: $ROLLBACK_COMMIT"
echo "Status:          rolled_back"
echo ""
echo "Next steps:"
echo "  1. Review regression test output above"
echo "  2. Write a revision spec for phase $MERGED_PHASE"
echo "  3. Re-dispatch the phase to fix the regression"
echo ""

exit 1
