#!/bin/bash
# Generate a self-contained HTML status dashboard
# Usage: generate-status-page.sh <project-path> [output-file]
# Default output: <project-path>/.planning/status.html

set -e

PROJECT_PATH="${1:?Usage: generate-status-page.sh <project-path> [output-file]}"
OUTPUT_FILE="${2:-$PROJECT_PATH/.planning/status.html}"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE" >&2
  exit 1
fi

# Read status.json values
PROJECT_NAME=$(jq -r '.project // "Unknown Project"' "$STATUS_FILE")
PROJECT_STATUS=$(jq -r '.status // "unknown"' "$STATUS_FILE")
CURRENT_PHASE=$(jq -r '.current_phase // ""' "$STATUS_FILE")
PHASES_COMPLETE=$(jq -r '.metrics.phases_complete // 0' "$STATUS_FILE")
PHASES_TOTAL=$(jq -r '.metrics.phases_total // 0' "$STATUS_FILE")
TOTAL_REVISIONS=$(jq -r '.metrics.total_revisions // 0' "$STATUS_FILE")
TOTAL_SMOKE_TESTS=$(jq -r '.metrics.total_smoke_tests // 0' "$STATUS_FILE")
STARTED_AT=$(jq -r '.metrics.started_at // ""' "$STATUS_FILE")
UPDATED_AT=$(jq -r '.updated // ""' "$STATUS_FILE")

# Calculate progress percentage
if [ "$PHASES_TOTAL" -gt 0 ]; then
  PROGRESS_PCT=$((PHASES_COMPLETE * 100 / PHASES_TOTAL))
else
  PROGRESS_PCT=0
fi

# Status badge color
case "$PROJECT_STATUS" in
  complete) STATUS_COLOR="#22c55e" ;;
  blocked) STATUS_COLOR="#ef4444" ;;
  *) STATUS_COLOR="#3b82f6" ;;
esac

# Convert ISO timestamp to epoch seconds
ts_to_epoch() {
  local ts="$1"
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

# Calculate phase duration from events
get_phase_duration() {
  local phase="$1"
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "-"
    return
  fi
  local queued_ts=$(grep "phase_queued" "$EVENTS_FILE" 2>/dev/null | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')
  local complete_ts=$(grep "phase_complete" "$EVENTS_FILE" 2>/dev/null | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')
  if [ -n "$queued_ts" ] && [ -n "$complete_ts" ]; then
    local queued_epoch=$(ts_to_epoch "$queued_ts")
    local complete_epoch=$(ts_to_epoch "$complete_ts")
    if [ "$queued_epoch" -gt 0 ] && [ "$complete_epoch" -gt 0 ]; then
      local duration=$((complete_epoch - queued_epoch))
      format_duration "$duration"
      return
    fi
  fi
  echo "-"
}

# Calculate total timing stats
calculate_timing_stats() {
  local total_secs=0
  local count=0
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "0|0"
    return
  fi
  while IFS= read -r phase; do
    local queued_ts=$(grep "phase_queued" "$EVENTS_FILE" 2>/dev/null | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')
    local complete_ts=$(grep "phase_complete" "$EVENTS_FILE" 2>/dev/null | grep "\"$phase\"" | head -1 | jq -r '.ts // ""')
    if [ -n "$queued_ts" ] && [ -n "$complete_ts" ]; then
      local queued_epoch=$(ts_to_epoch "$queued_ts")
      local complete_epoch=$(ts_to_epoch "$complete_ts")
      if [ "$queued_epoch" -gt 0 ] && [ "$complete_epoch" -gt 0 ]; then
        local duration=$((complete_epoch - queued_epoch))
        total_secs=$((total_secs + duration))
        count=$((count + 1))
      fi
    fi
  done <<< "$(jq -r '.phases | keys[]' "$STATUS_FILE")"
  echo "$total_secs|$count"
}

# Generate phase rows
generate_phase_rows() {
  jq -r '.phases | to_entries | sort_by(.key) | .[] |
    "\(.key)|\(.value.status // "pending")|\(.value.commit // "-")|\(.value.smoke_tests_passed // 0)/\(.value.smoke_tests_total // 0)|\(.value.revisions // 0)"' "$STATUS_FILE" | \
  while IFS='|' read -r name status commit tests revisions; do
    case "$status" in
      complete) color="#22c55e"; bg="#dcfce7" ;;
      queued) color="#eab308"; bg="#fef9c3" ;;
      pending) color="#6b7280"; bg="#f3f4f6" ;;
      failed|revision_failed) color="#ef4444"; bg="#fee2e2" ;;
      cancelled) color="#f97316"; bg="#ffedd5" ;;
      *) color="#6b7280"; bg="#f3f4f6" ;;
    esac

    highlight=""
    if [ "$name" = "$CURRENT_PHASE" ]; then
      highlight="border-left: 4px solid #3b82f6;"
    fi

    # Get timing for this phase
    timing=$(get_phase_duration "$name")

    echo "<tr style=\"$highlight\">"
    echo "  <td style=\"font-weight:500;\">$name</td>"
    echo "  <td><span style=\"background:$bg;color:$color;padding:2px 8px;border-radius:4px;font-size:12px;\">$status</span></td>"
    echo "  <td style=\"font-family:monospace;font-size:12px;\">$commit</td>"
    echo "  <td>$tests</td>"
    echo "  <td>$revisions</td>"
    echo "  <td style=\"font-family:monospace;font-size:12px;\">$timing</td>"
    echo "</tr>"
  done
}

# Generate event timeline
generate_event_timeline() {
  if [ ! -f "$EVENTS_FILE" ]; then
    echo "<p style=\"color:#6b7280;\">No events recorded yet.</p>"
    return
  fi

  echo "<div style=\"max-height:300px;overflow-y:auto;\">"
  tail -20 "$EVENTS_FILE" | tac | while IFS= read -r line; do
    ts=$(echo "$line" | jq -r '.ts // ""')
    event=$(echo "$line" | jq -r '.event // "unknown"')
    phase=$(echo "$line" | jq -r '.data.phase // .data.name // ""')

    case "$event" in
      phase_complete|phase_verified|smoke_test_pass) dot_color="#22c55e" ;;
      phase_started|phase_queued|smoke_tests_run) dot_color="#3b82f6" ;;
      phase_verification_failed|smoke_test_fail) dot_color="#ef4444" ;;
      phase_cancelled) dot_color="#f97316" ;;
      *) dot_color="#6b7280" ;;
    esac

    # Format timestamp
    time_short=$(echo "$ts" | sed 's/T/ /;s/Z$//' | cut -c1-16)

    echo "<div style=\"display:flex;align-items:center;gap:8px;padding:4px 0;border-bottom:1px solid #e5e7eb;\">"
    echo "  <span style=\"width:10px;height:10px;border-radius:50%;background:$dot_color;flex-shrink:0;\"></span>"
    echo "  <span style=\"font-family:monospace;font-size:11px;color:#6b7280;min-width:120px;\">$time_short</span>"
    echo "  <span style=\"font-size:13px;\"><strong>$event</strong>"
    [ -n "$phase" ] && echo " <span style=\"color:#6b7280;\">($phase)</span>"
    echo "</span></div>"
  done
  echo "</div>"
}

# Calculate timing stats
TIMING_STATS=$(calculate_timing_stats)
TOTAL_TIME_SECS=$(echo "$TIMING_STATS" | cut -d'|' -f1)
TIMED_PHASES=$(echo "$TIMING_STATS" | cut -d'|' -f2)
if [ "$TIMED_PHASES" -gt 0 ]; then
  TOTAL_TIME_STR=$(format_duration "$TOTAL_TIME_SECS")
  AVG_TIME_SECS=$((TOTAL_TIME_SECS / TIMED_PHASES))
  AVG_TIME_STR=$(format_duration "$AVG_TIME_SECS")
else
  TOTAL_TIME_STR="-"
  AVG_TIME_STR="-"
fi

# Generate HTML
cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$PROJECT_NAME - Orchestration Status</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f9fafb;
      color: #111827;
      padding: 20px;
      max-width: 900px;
      margin: 0 auto;
    }
    .card {
      background: white;
      border-radius: 8px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
      padding: 20px;
      margin-bottom: 20px;
    }
    h1 { font-size: 24px; margin-bottom: 8px; }
    h2 { font-size: 16px; color: #6b7280; margin-bottom: 16px; font-weight: 500; }
    .badge {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
    }
    .progress-bar {
      background: #e5e7eb;
      border-radius: 4px;
      height: 8px;
      margin: 16px 0;
      overflow: hidden;
    }
    .progress-fill {
      height: 100%;
      background: #3b82f6;
      transition: width 0.3s;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
      gap: 16px;
      margin-top: 16px;
    }
    .stat {
      text-align: center;
    }
    .stat-value {
      font-size: 28px;
      font-weight: 700;
      color: #111827;
    }
    .stat-label {
      font-size: 12px;
      color: #6b7280;
      text-transform: uppercase;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th {
      text-align: left;
      padding: 12px 8px;
      border-bottom: 2px solid #e5e7eb;
      font-weight: 600;
      color: #6b7280;
      font-size: 12px;
      text-transform: uppercase;
    }
    td {
      padding: 12px 8px;
      border-bottom: 1px solid #e5e7eb;
    }
    .meta {
      font-size: 12px;
      color: #6b7280;
      margin-top: 8px;
    }
    @media (max-width: 600px) {
      body { padding: 10px; }
      .card { padding: 15px; }
      table { font-size: 12px; }
      th, td { padding: 8px 4px; }
    }
  </style>
</head>
<body>
  <div class="card">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;">
      <h1>$PROJECT_NAME</h1>
      <span class="badge" style="background:$STATUS_COLOR;color:white;">$PROJECT_STATUS</span>
    </div>
    <div class="progress-bar">
      <div class="progress-fill" style="width:${PROGRESS_PCT}%;"></div>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:14px;">
      <span>$PHASES_COMPLETE / $PHASES_TOTAL phases complete</span>
      <span>${PROGRESS_PCT}%</span>
    </div>
    <div class="meta">
      Started: $STARTED_AT | Updated: $UPDATED_AT
    </div>
  </div>

  <div class="card">
    <h2>Phases</h2>
    <div style="overflow-x:auto;">
      <table>
        <thead>
          <tr>
            <th>Phase</th>
            <th>Status</th>
            <th>Commit</th>
            <th>Tests</th>
            <th>Revisions</th>
            <th>Timing</th>
          </tr>
        </thead>
        <tbody>
$(generate_phase_rows)
        </tbody>
      </table>
    </div>
  </div>

  <div class="card">
    <h2>Recent Events</h2>
$(generate_event_timeline)
  </div>

  <div class="card">
    <h2>Summary</h2>
    <div class="stats">
      <div class="stat">
        <div class="stat-value">$PHASES_TOTAL</div>
        <div class="stat-label">Total Phases</div>
      </div>
      <div class="stat">
        <div class="stat-value">$PHASES_COMPLETE</div>
        <div class="stat-label">Complete</div>
      </div>
      <div class="stat">
        <div class="stat-value">$TOTAL_REVISIONS</div>
        <div class="stat-label">Revisions</div>
      </div>
      <div class="stat">
        <div class="stat-value">$TOTAL_SMOKE_TESTS</div>
        <div class="stat-label">Smoke Tests</div>
      </div>
      <div class="stat">
        <div class="stat-value">$TOTAL_TIME_STR</div>
        <div class="stat-label">Total Time</div>
      </div>
      <div class="stat">
        <div class="stat-value">$AVG_TIME_STR</div>
        <div class="stat-label">Avg/Phase</div>
      </div>
    </div>
  </div>

  <p style="text-align:center;font-size:12px;color:#9ca3af;margin-top:20px;">
    Generated by orchestrator at $(date -u +%Y-%m-%dT%H:%M:%SZ)
  </p>
</body>
</html>
EOF

echo "✅ Generated status page: $OUTPUT_FILE"
