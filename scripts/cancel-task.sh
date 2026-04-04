#!/bin/bash
# Cancel a queued phase
# Usage: cancel-task.sh <project-path> <phase-name>
# Example: cancel-task.sh /home/mp/awesome/blog-publisher 03-images
#
# - Only cancels phases in "queued" status
# - Updates status.json and appends to events.jsonl
# - Exit 0 on success, 1 on error

set -e

PROJECT_PATH="${1:?Usage: cancel-task.sh <project-path> <phase-name>}"
PHASE_NAME="${2:?Missing phase name}"

STATUS_FILE="$PROJECT_PATH/.planning/status.json"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Check status.json exists
if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE"
  exit 1
fi

# Check phase exists in status.json
PHASE_EXISTS=$(jq -r --arg phase "$PHASE_NAME" 'has("phases") and (.phases | has($phase))' "$STATUS_FILE")
if [ "$PHASE_EXISTS" != "true" ]; then
  echo "❌ Error: Phase '$PHASE_NAME' not found in status.json"
  exit 1
fi

# Check current phase status
CURRENT_STATUS=$(jq -r --arg phase "$PHASE_NAME" '.phases[$phase].status // "unknown"' "$STATUS_FILE")
if [ "$CURRENT_STATUS" != "queued" ]; then
  echo "❌ Error: Phase '$PHASE_NAME' is in '$CURRENT_STATUS' status, not 'queued'"
  echo "   Only phases in 'queued' status can be cancelled."
  exit 1
fi

# Update status.json: set phase status to "cancelled"
jq --arg phase "$PHASE_NAME" \
   '.phases[$phase].status = "cancelled"' \
   "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"

# Append cancellation event to events.jsonl
echo "{\"ts\":\"$NOW\",\"event\":\"phase_cancelled\",\"data\":{\"phase\":\"$PHASE_NAME\",\"reason\":\"manual\"}}" >> "$EVENTS_FILE"

echo "✅ Phase '$PHASE_NAME' cancelled"
echo "   Status: queued → cancelled"
echo "   Event logged to events.jsonl"
exit 0
