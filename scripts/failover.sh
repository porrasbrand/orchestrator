#!/usr/bin/env bash
# failover.sh — Worker failover engine
# Monitors a queued/in-progress phase and re-queues to another worker if the
# current worker becomes unreachable or the phase has gone stale.
#
# Usage: failover.sh <project-path> <phase-name> [--timeout <minutes>] [--check-only]
#
# Exit codes:
#   0  Healthy (no failover needed) OR failover completed successfully
#   1  Failover needed but no alternative workers available
#   2  Error (can't read status.json, can't parse events, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Usage ---
usage() {
    cat >&2 <<'EOF'
Usage: failover.sh <project-path> <phase-name> [--timeout <minutes>] [--check-only]

Monitors a queued/in-progress phase and automatically re-queues to another
worker if the current worker becomes unreachable or the phase has gone stale.

Options:
  --timeout <minutes>   Max time before phase is considered stale (default: 30)
  --check-only          Just check health, don't failover. Outputs:
                        HEALTHY, WORKER_DOWN, or PHASE_STALE

Exit codes:
  0  Healthy (no failover needed) OR failover completed successfully
  1  Failover needed but no alternative workers available
  2  Error (can't read status.json, can't parse events, etc.)

Examples:
  failover.sh /path/to/project 01-setup
  failover.sh /path/to/project 03-auth --timeout 60
  failover.sh /path/to/project 02-api --check-only
EOF
    exit 2
}

# --- Parse arguments ---
if [ $# -lt 2 ]; then
    usage
fi

PROJECT_PATH="$1"
PHASE_NAME="$2"
shift 2

TIMEOUT_MINUTES=30
CHECK_ONLY=false

while [ $# -gt 0 ]; do
    case "$1" in
        --timeout)
            TIMEOUT_MINUTES="${2:?--timeout requires a value}"
            shift 2
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# --- Validate inputs ---
STATUS_FILE="$PROJECT_PATH/status.json"
EVENTS_FILE="$PROJECT_PATH/events.jsonl"

if [ ! -f "$STATUS_FILE" ]; then
    echo "Error: status.json not found at $STATUS_FILE" >&2
    exit 2
fi

if [ ! -f "$EVENTS_FILE" ]; then
    echo "Error: events.jsonl not found at $EVENTS_FILE" >&2
    exit 2
fi

# --- Read worker assignment from status.json ---
# Look for target_worker on the specific phase
TARGET_WORKER=$(jq -r --arg phase "$PHASE_NAME" '
    .phases[]
    | select(.name == $phase or .id == $phase)
    | .target_worker // empty
' "$STATUS_FILE" 2>/dev/null)

if [ -z "$TARGET_WORKER" ]; then
    # Fallback: check top-level target_worker
    TARGET_WORKER=$(jq -r '.target_worker // empty' "$STATUS_FILE" 2>/dev/null)
fi

if [ -z "$TARGET_WORKER" ]; then
    echo "Error: No target_worker found for phase '$PHASE_NAME' in status.json" >&2
    exit 2
fi

echo "Phase '$PHASE_NAME' assigned to worker: $TARGET_WORKER"

# --- Worker health check (3 retries, 10-second gaps) ---
check_worker_health() {
    local worker="$1"
    local max_retries=3
    local retry_delay=10

    for attempt in $(seq 1 $max_retries); do
        echo "  Health check attempt $attempt/$max_retries for worker '$worker'..."

        # Use get-worker.sh to build SSH command
        local ssh_cmd
        ssh_cmd=$(bash "$SCRIPT_DIR/get-worker.sh" "$worker" ssh_cmd 2>/dev/null) || {
            echo "  Warning: Could not get SSH command for worker '$worker'" >&2
            if [ "$attempt" -lt "$max_retries" ]; then
                sleep "$retry_delay"
            fi
            continue
        }

        # Override ConnectTimeout to 5 seconds for health check
        local health_cmd="${ssh_cmd/ConnectTimeout=10/ConnectTimeout=5}"

        if $health_cmd 'echo alive' >/dev/null 2>&1; then
            return 0  # Worker is alive
        fi

        echo "  Attempt $attempt failed."
        if [ "$attempt" -lt "$max_retries" ]; then
            echo "  Retrying in ${retry_delay}s..."
            sleep "$retry_delay"
        fi
    done

    return 1  # All retries exhausted — worker is down
}

# --- Timeout check from events.jsonl ---
check_phase_timeout() {
    local phase="$1"
    local timeout_min="$2"

    # Find the most recent phase_queued event for this phase
    local queued_ts
    queued_ts=$(grep "phase_queued" "$EVENTS_FILE" | grep "\"$phase\"" | tail -1 | jq -r '.timestamp // .time // empty' 2>/dev/null)

    if [ -z "$queued_ts" ]; then
        echo "  No phase_queued event found for '$phase' — skipping timeout check."
        return 1  # Can't determine, treat as not stale
    fi

    # Convert queued timestamp to epoch
    local queued_epoch
    queued_epoch=$(date -d "$queued_ts" +%s 2>/dev/null) || {
        echo "  Warning: Could not parse timestamp '$queued_ts'" >&2
        return 1
    }

    local now_epoch
    now_epoch=$(date +%s)
    local elapsed_seconds=$(( now_epoch - queued_epoch ))
    local timeout_seconds=$(( timeout_min * 60 ))
    local elapsed_minutes=$(( elapsed_seconds / 60 ))

    echo "  Phase queued ${elapsed_minutes}m ago (timeout: ${timeout_min}m)"

    if [ "$elapsed_seconds" -gt "$timeout_seconds" ]; then
        return 0  # Stale
    fi

    return 1  # Not stale
}

# --- Run checks ---
WORKER_STATUS="HEALTHY"
FAILOVER_REASON=""

echo ""
echo "=== Checking worker health ==="
if ! check_worker_health "$TARGET_WORKER"; then
    WORKER_STATUS="WORKER_DOWN"
    FAILOVER_REASON="down"
    echo "  Result: WORKER_DOWN (all $max_retries retries failed)"
else
    echo "  Result: Worker '$TARGET_WORKER' is alive"
fi

# Only check timeout if worker is healthy (stale check)
if [ "$WORKER_STATUS" = "HEALTHY" ]; then
    echo ""
    echo "=== Checking phase timeout ==="
    if check_phase_timeout "$PHASE_NAME" "$TIMEOUT_MINUTES"; then
        WORKER_STATUS="PHASE_STALE"
        FAILOVER_REASON="stale"
        echo "  Result: PHASE_STALE (exceeded ${TIMEOUT_MINUTES}m timeout)"
    else
        echo "  Result: Phase is within timeout window"
    fi
fi

# --- check-only mode: just report status ---
if [ "$CHECK_ONLY" = true ]; then
    echo ""
    echo "$WORKER_STATUS"
    exit 0
fi

# --- If healthy, nothing to do ---
if [ "$WORKER_STATUS" = "HEALTHY" ]; then
    echo ""
    echo "No failover needed. Worker '$TARGET_WORKER' is healthy and phase is within timeout."
    exit 0
fi

# --- Failover logic ---
echo ""
echo "=== Initiating failover ==="
echo "Reason: $FAILOVER_REASON"

# Select a new worker (excludes unreachable ones naturally via select-worker.sh)
NEW_WORKER=$(bash "$SCRIPT_DIR/select-worker.sh" 2>/dev/null) || {
    echo "Error: select-worker.sh failed" >&2
    exit 1
}

# If select-worker.sh returns the same failed worker, there are no alternatives
if [ "$NEW_WORKER" = "$TARGET_WORKER" ]; then
    echo "Error: No alternative workers available (select-worker.sh returned same worker: $TARGET_WORKER)" >&2
    exit 1
fi

echo "Selected new worker: $NEW_WORKER (was: $TARGET_WORKER)"

# Update status.json: set new target_worker, add failover metadata
FAILOVER_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq --arg phase "$PHASE_NAME" \
   --arg new_worker "$NEW_WORKER" \
   --arg old_worker "$TARGET_WORKER" \
   --arg failover_at "$FAILOVER_TS" \
   '
   .phases = [.phases[] |
       if (.name == $phase or .id == $phase) then
           .target_worker = $new_worker |
           .failover_from = $old_worker |
           .failover_at = $failover_at
       else . end
   ]
   ' "$STATUS_FILE" > "${STATUS_FILE}.tmp" && mv "${STATUS_FILE}.tmp" "$STATUS_FILE"

echo "Updated status.json with new worker assignment"

# Log phase_failover event to events.jsonl
EVENT_JSON=$(jq -n \
    --arg event "phase_failover" \
    --arg phase "$PHASE_NAME" \
    --arg old_worker "$TARGET_WORKER" \
    --arg new_worker "$NEW_WORKER" \
    --arg reason "$FAILOVER_REASON" \
    --arg timestamp "$FAILOVER_TS" \
    '{
        event: $event,
        phase: $phase,
        old_worker: $old_worker,
        new_worker: $new_worker,
        reason: $reason,
        timestamp: $timestamp
    }')

echo "$EVENT_JSON" >> "$EVENTS_FILE"
echo "Logged phase_failover event to events.jsonl"

# Notify via notify.sh
bash "$SCRIPT_DIR/notify.sh" phase_failed "$PROJECT_PATH" \
    --phase "$PHASE_NAME" \
    --detail "Failover: worker '$TARGET_WORKER' is $FAILOVER_REASON. Re-assigned to '$NEW_WORKER'." 2>/dev/null || {
    echo "Warning: notify.sh call failed (non-fatal)" >&2
}

echo ""
echo "Failover complete. New worker: $NEW_WORKER"
echo "$NEW_WORKER"
