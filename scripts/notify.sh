#!/usr/bin/env bash
# notify.sh — Notification engine for orchestrator events
# Writes notifications to project files and optionally calls a user-defined hook.
#
# Usage: notify.sh <event-type> <project-path> [--phase <name>] [--detail <message>]
#
# Event types:
#   phase_complete        Phase finished successfully
#   phase_failed          Phase failed after max revisions
#   verification_failed   Smoke test verification failed
#   regression_failed     Regression tests broke after merge
#   project_complete      All phases in project completed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR_DIR="$(dirname "$SCRIPT_DIR")"

# --- Usage ---
usage() {
    cat >&2 <<'EOF'
Usage: notify.sh <event-type> <project-path> [--phase <name>] [--detail <message>]

Event types:
  phase_complete        Phase finished successfully
  phase_failed          Phase failed after max revisions
  verification_failed   Smoke test verification failed
  regression_failed     Regression tests broke after merge
  project_complete      All phases in project completed

Options:
  --phase <name>      Phase name (e.g., 01-verify-error-clarity)
  --detail <message>  Detail message (e.g., "5 tests passed. Commit: abc1234.")

Examples:
  notify.sh phase_complete /path/to/project --phase 01-setup --detail "All 5 tests passed."
  notify.sh project_complete /path/to/project --detail "10 phases, 3 revisions total."
EOF
    exit 1
}

# --- Argument parsing ---
if [[ $# -lt 2 ]]; then
    usage
fi

EVENT_TYPE="$1"
PROJECT_PATH="$2"
shift 2

PHASE=""
DETAIL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --detail)
            DETAIL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# --- Validate event type ---
VALID_EVENTS="phase_complete phase_failed verification_failed regression_failed project_complete"
if ! echo "$VALID_EVENTS" | grep -qw "$EVENT_TYPE"; then
    echo "Error: Invalid event type '$EVENT_TYPE'" >&2
    echo "Valid types: $VALID_EVENTS" >&2
    exit 1
fi

# --- Validate project path ---
if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: Project path '$PROJECT_PATH' does not exist" >&2
    exit 1
fi

PLANNING_DIR="$PROJECT_PATH/.planning"
if [[ ! -d "$PLANNING_DIR" ]]; then
    mkdir -p "$PLANNING_DIR"
fi

# --- Timestamp ---
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M:%S')"
TIMESTAMP_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- Format notification message ---
format_message() {
    local event="$1"
    local phase="$2"
    local detail="$3"

    case "$event" in
        phase_complete)
            echo "Phase Complete: ${phase}"
            ;;
        phase_failed)
            echo "Phase Failed: ${phase}"
            ;;
        verification_failed)
            echo "Verification Failed: ${phase}"
            ;;
        regression_failed)
            echo "Regression Failed: ${phase}"
            ;;
        project_complete)
            echo "Project Complete"
            ;;
    esac
}

# --- Format title for markdown heading ---
HEADING="$(format_message "$EVENT_TYPE" "$PHASE" "$DETAIL")"

# --- Derive project name from path ---
PROJECT_NAME="$(basename "$PROJECT_PATH")"

# --- Write notifications.md ---
NOTIFICATIONS_FILE="$PLANNING_DIR/notifications.md"
if [[ ! -f "$NOTIFICATIONS_FILE" ]]; then
    echo "# Notifications" > "$NOTIFICATIONS_FILE"
    echo "" >> "$NOTIFICATIONS_FILE"
fi

{
    echo "## [${TIMESTAMP}] ${HEADING}"
    if [[ -n "$DETAIL" ]]; then
        echo "${DETAIL}"
    fi
    echo ""
} >> "$NOTIFICATIONS_FILE"

# --- Write latest-notification.json ---
LATEST_FILE="$PLANNING_DIR/latest-notification.json"
cat > "$LATEST_FILE" <<ENDJSON
{
  "timestamp": "${TIMESTAMP_ISO}",
  "event": "${EVENT_TYPE}",
  "phase": "${PHASE}",
  "detail": "${DETAIL}",
  "project": "${PROJECT_NAME}"
}
ENDJSON

# --- Call hook if present ---
HOOK_PATH="$ORCHESTRATOR_DIR/config/notify-hook.sh"
if [[ -x "$HOOK_PATH" ]]; then
    if ! cat "$LATEST_FILE" | "$HOOK_PATH"; then
        echo "Warning: notify hook exited non-zero (ignored)" >&2
    fi
fi

echo "Notification sent: ${EVENT_TYPE} ${PHASE:+($PHASE)}"
