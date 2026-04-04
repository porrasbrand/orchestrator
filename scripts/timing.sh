#!/bin/bash
# Calculate phase durations from events.jsonl timestamps
# Usage: timing.sh <project-path>

set -e

PROJECT_PATH="${1:?Usage: timing.sh <project-path>}"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"

if [ ! -f "$EVENTS_FILE" ]; then
  echo "❌ Error: events.jsonl not found at $EVENTS_FILE" >&2
  exit 1
fi

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE" >&2
  exit 1
fi

# Convert ISO timestamp to epoch seconds
ts_to_epoch() {
  local ts="$1"
  # Handle both formats: 2026-04-04T14:16:43Z and 2026-04-04T14:16:43.123Z
  date -d "${ts/Z/+0000}" +%s 2>/dev/null || echo "0"
}

# Format seconds to human readable
format_duration() {
  local secs="$1"
  if [ "$secs" -lt 60 ]; then
    echo "${secs}s"
  elif [ "$secs" -lt 3600 ]; then
    local mins=$((secs / 60))
    local remaining=$((secs % 60))
    printf "%dm %02ds" "$mins" "$remaining"
  else
    local hours=$((secs / 3600))
    local mins=$(((secs % 3600) / 60))
    printf "%dh %02dm" "$hours" "$mins"
  fi
}

echo "========================================"
echo "Phase Timing:"
echo "========================================"

# Get all phases from status.json
PHASES=$(jq -r '.phases | keys[]' "$STATUS_FILE" | sort)

TOTAL_SECS=0
COMPLETE_COUNT=0
LONGEST_PHASE=""
LONGEST_SECS=0

while IFS= read -r phase; do
  # Get queued timestamp
  queued_ts=$(grep "phase_queued" "$EVENTS_FILE" | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')

  # Get complete timestamp
  complete_ts=$(grep "phase_complete" "$EVENTS_FILE" | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')

  # Get current status
  status=$(jq -r --arg p "$phase" '.phases[$p].status // "unknown"' "$STATUS_FILE")

  if [ -n "$queued_ts" ] && [ -n "$complete_ts" ]; then
    # Calculate duration
    queued_epoch=$(ts_to_epoch "$queued_ts")
    complete_epoch=$(ts_to_epoch "$complete_ts")

    if [ "$queued_epoch" -gt 0 ] && [ "$complete_epoch" -gt 0 ]; then
      duration=$((complete_epoch - queued_epoch))
      duration_str=$(format_duration "$duration")

      TOTAL_SECS=$((TOTAL_SECS + duration))
      COMPLETE_COUNT=$((COMPLETE_COUNT + 1))

      # Track longest
      if [ "$duration" -gt "$LONGEST_SECS" ]; then
        LONGEST_SECS=$duration
        LONGEST_PHASE=$phase
      fi

      # Mark longest in output
      if [ "$phase" = "$LONGEST_PHASE" ] && [ "$COMPLETE_COUNT" -gt 1 ]; then
        printf "  %-25s %s (longest)\n" "$phase" "$duration_str"
      else
        printf "  %-25s %s\n" "$phase" "$duration_str"
      fi
    else
      printf "  %-25s %s\n" "$phase" "error"
    fi
  elif [ "$status" = "queued" ]; then
    printf "  %-25s %s\n" "$phase" "in progress"
  else
    printf "  %-25s %s\n" "$phase" "pending"
  fi
done <<< "$PHASES"

# Re-mark longest now that we know which one it is
echo ""
echo "========================================"
echo "Summary:"
echo "========================================"

if [ "$COMPLETE_COUNT" -gt 0 ]; then
  total_str=$(format_duration "$TOTAL_SECS")
  avg_secs=$((TOTAL_SECS / COMPLETE_COUNT))
  avg_str=$(format_duration "$avg_secs")
  longest_str=$(format_duration "$LONGEST_SECS")

  echo "  Total wall-clock: $total_str"
  echo "  Average per phase: $avg_str"
  echo "  Longest phase: $LONGEST_PHASE ($longest_str)"
  echo "  Phases timed: $COMPLETE_COUNT"
else
  echo "  No completed phases to analyze."
fi
