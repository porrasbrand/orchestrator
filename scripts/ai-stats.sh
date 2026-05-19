#!/usr/bin/env bash
# scripts/ai-stats.sh — orchestrator P2 Phase C.
# Aggregates AI diagnostic telemetry from .planning/events.jsonl.
#
# Usage:
#   scripts/ai-stats.sh [--project <project-path>] [--since <ISO-date>]
#                       [--format text|json] [--phase <phase-name>]
#
# Defaults: --project=.  --format=text  --since=<beginning of time>
#
# Reads from <project>/.planning/events.jsonl (append-only JSONL). Skips
# malformed lines and counts them in the warnings section.
#
# Metrics emitted:
#   - diagnostics_run, diagnostics_used, adoption_rate (used / run)
#   - ai_assisted_success_rate (used followed by phase_complete BEFORE next
#     phase_verification_failed on same phase, %)
#   - cost {total, avg, max} from ai_diagnostic_run.data.cost
#   - confidence_distribution {high, medium, low}
#   - escalation_rate (escalate_now=true / run, %)
#   - top_phases (top 5 by diagnostic count, sorted desc)
#   - time_range {first, last}
#   - warnings (malformed JSONL count, missing-cost count)
#
# Performance: for events.jsonl > 10K lines, processes only the tail to bound
# memory/runtime. The "since" filter is applied during the jq pass either way.
#
# Exit codes: 0 always (graceful on empty / missing input); jq parse failures
# are counted as warnings, not exit-killing.

set -uo pipefail

PROJECT="."
SINCE=""
FORMAT="text"
PHASE_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --since)   SINCE="$2"; shift 2 ;;
    --format)  FORMAT="$2"; shift 2 ;;
    --phase)   PHASE_FILTER="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,30p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
  echo "Invalid --format: $FORMAT (expected text|json)" >&2
  exit 2
fi

EVENTS_FILE="$PROJECT/.planning/events.jsonl"

emit_empty() {
  local reason="$1"
  if [[ "$FORMAT" == "json" ]]; then
    printf '{"diagnostics_run":0,"diagnostics_used":0,"adoption_rate":0,"ai_assisted_success_rate":null,"cost":{"total":0,"avg":0,"max":0},"confidence_distribution":{"high":0,"medium":0,"low":0},"escalation_rate":0,"top_phases":[],"time_range":{"first":null,"last":null},"warnings":{"reason":"%s"}}\n' "$reason"
  else
    echo "AI Diagnostic Stats"
    echo "==================="
    echo "$reason"
  fi
  exit 0
}

if [[ ! -f "$EVENTS_FILE" ]]; then emit_empty "No events.jsonl at $EVENTS_FILE"; fi

# Tail bound: if > 10K lines, only process the most recent 10K to bound work.
LINE_COUNT=$(wc -l < "$EVENTS_FILE" 2>/dev/null || echo 0)
if [[ "$LINE_COUNT" -gt 10000 ]]; then
  RAW=$(tail -n 10000 "$EVENTS_FILE")
else
  RAW=$(cat "$EVENTS_FILE")
fi

if [[ -z "$RAW" ]]; then emit_empty "events.jsonl empty"; fi

# Use a single jq pass to compute everything. Malformed lines are filtered by
# `fromjson?` which returns empty on parse failure. Warnings are computed
# separately by counting parse failures.
MALFORMED=$(printf '%s\n' "$RAW" | awk 'NF > 0' | while IFS= read -r line; do
  echo "$line" | jq -e . >/dev/null 2>&1 || echo bad
done | wc -l)

# Build the jq filter. Apply --since and --phase as gate filters early.
JQ_SINCE=""
if [[ -n "$SINCE" ]]; then
  JQ_SINCE=" | select(.ts >= \"$SINCE\")"
fi
JQ_PHASE=""
if [[ -n "$PHASE_FILTER" ]]; then
  JQ_PHASE=" | select(.data.phase == \"$PHASE_FILTER\")"
fi

# Stream events; aggregate via jq. The reducer walks the stream in order and
# tracks per-phase last-ai-used + next-outcome (complete vs. verification_failed)
# to compute AI-assisted success rate.
STATS_JSON=$(printf '%s\n' "$RAW" | awk 'NF > 0' \
  | jq -cR "fromjson? ${JQ_SINCE}${JQ_PHASE}" \
  | jq -s '
    def round_pct: . * 1000 | round / 10;

    # Walk events in order and compute correlated success rate.
    # For each ai_diagnostic_used, find the same-phase event AFTER it that is
    # either phase_complete (success) or phase_verification_failed (failure).
    # If neither appears later, that used event is "pending" and excluded.
    . as $events |
    [ range(0; $events | length) ] as $idxs |
    [
      $idxs[] | . as $i |
      $events[$i] | select(.event == "ai_diagnostic_used") |
      . as $used |
      ($used.data.phase // "") as $ph |
      [ $events[$i+1:][] | select(.data.phase == $ph) |
        select(.event == "phase_complete" or .event == "phase_verification_failed") |
        .event ] as $followups |
      ($followups[0] // null) as $first_outcome |
      { phase: $ph, outcome: $first_outcome }
    ] as $used_outcomes |
    ($used_outcomes | map(select(.outcome != null)) | length) as $resolved_used |
    ($used_outcomes | map(select(.outcome == "phase_complete")) | length) as $resolved_success |

    {
      diagnostics_run: ([.[] | select(.event == "ai_diagnostic_run")] | length),
      diagnostics_used: ([.[] | select(.event == "ai_diagnostic_used")] | length),
      cost: {
        total: ([.[] | select(.event == "ai_diagnostic_run") | .data.cost // 0] | add // 0),
        avg:   (if ([.[] | select(.event == "ai_diagnostic_run")] | length) == 0 then 0
                else (([.[] | select(.event == "ai_diagnostic_run") | .data.cost // 0] | add // 0)
                      / ([.[] | select(.event == "ai_diagnostic_run")] | length)) end),
        max:   ([.[] | select(.event == "ai_diagnostic_run") | .data.cost // 0] | max // 0)
      },
      confidence_distribution: {
        high:   ([.[] | select(.event == "ai_diagnostic_run") | select(.data.confidence == "high")] | length),
        medium: ([.[] | select(.event == "ai_diagnostic_run") | select(.data.confidence == "medium")] | length),
        low:    ([.[] | select(.event == "ai_diagnostic_run") | select(.data.confidence == "low")] | length)
      },
      escalations: ([.[] | select(.event == "ai_diagnostic_run") | select(.data.escalate_now == true)] | length),
      top_phases: ([.[] | select(.event == "ai_diagnostic_run") | .data.phase]
                   | group_by(.) | map({phase: .[0], count: length})
                   | sort_by(-.count) | .[0:5]),
      time_range: {
        first: (.[0].ts // null),
        last:  (.[-1].ts // null)
      },
      _resolved_used: $resolved_used,
      _resolved_success: $resolved_success
    }
    | .adoption_rate = (if .diagnostics_run == 0 then 0
                        else (.diagnostics_used / .diagnostics_run | round_pct) end)
    | .escalation_rate = (if .diagnostics_run == 0 then 0
                          else (.escalations / .diagnostics_run | round_pct) end)
    | .ai_assisted_success_rate = (if ._resolved_used == 0 then null
                                   else (._resolved_success / ._resolved_used | round_pct) end)
    | .missing_cost = ([.[]] | length) * 0    # placeholder; computed below from raw
  ' 2>/dev/null)

# Count missing-cost (cost field absent on ai_diagnostic_run events).
MISSING_COST=$(printf '%s\n' "$RAW" | awk 'NF > 0' \
  | jq -cR "fromjson? | select(.event == \"ai_diagnostic_run\") | select(.data.cost == null)" 2>/dev/null \
  | wc -l)

if [[ -z "$STATS_JSON" || "$STATS_JSON" == "null" ]]; then emit_empty "no valid events parsed"; fi

# Inject warnings + scrub internal helper fields.
FINAL_JSON=$(echo "$STATS_JSON" | jq --argjson m "$MALFORMED" --argjson mc "$MISSING_COST" '
  del(._resolved_used, ._resolved_success, .missing_cost) |
  .warnings = { malformed_lines: $m, missing_cost_events: $mc }
')

if [[ "$FORMAT" == "json" ]]; then
  echo "$FINAL_JSON"
  exit 0
fi

# Text format.
echo "AI Diagnostic Stats"
echo "==================="
if [[ -n "$SINCE" ]]; then echo "Since: $SINCE"; fi
if [[ -n "$PHASE_FILTER" ]]; then echo "Phase filter: $PHASE_FILTER"; fi
echo "Time range: $(echo "$FINAL_JSON" | jq -r '.time_range.first // "(none)"') → $(echo "$FINAL_JSON" | jq -r '.time_range.last // "(none)"')"
echo ""
echo "-- Usage --"
echo "Diagnostics run:   $(echo "$FINAL_JSON" | jq -r '.diagnostics_run')"
echo "Diagnostics used:  $(echo "$FINAL_JSON" | jq -r '.diagnostics_used')"
echo "Adoption rate:     $(echo "$FINAL_JSON" | jq -r '.adoption_rate')%"
echo ""
echo "-- Outcomes --"
SUCCESS_RATE=$(echo "$FINAL_JSON" | jq -r '.ai_assisted_success_rate')
if [[ "$SUCCESS_RATE" == "null" ]]; then
  echo "AI-assisted revision success rate: n/a (no resolved 'used' events yet)"
else
  echo "AI-assisted revision success rate: ${SUCCESS_RATE}%"
fi
echo "Escalation rate:   $(echo "$FINAL_JSON" | jq -r '.escalation_rate')%"
echo ""
echo "-- Cost --"
printf "Total:  \$%.4f\n" "$(echo "$FINAL_JSON" | jq -r '.cost.total')"
printf "Avg:    \$%.4f\n" "$(echo "$FINAL_JSON" | jq -r '.cost.avg')"
printf "Max:    \$%.4f\n" "$(echo "$FINAL_JSON" | jq -r '.cost.max')"
echo ""
echo "-- Confidence distribution --"
echo "high:   $(echo "$FINAL_JSON" | jq -r '.confidence_distribution.high')"
echo "medium: $(echo "$FINAL_JSON" | jq -r '.confidence_distribution.medium')"
echo "low:    $(echo "$FINAL_JSON" | jq -r '.confidence_distribution.low')"
echo ""
echo "-- Top diagnosed phases --"
echo "$FINAL_JSON" | jq -r '.top_phases[] | "\(.phase): \(.count)"' | head -5
echo ""
WARN_MALFORMED=$(echo "$FINAL_JSON" | jq -r '.warnings.malformed_lines')
WARN_MISSING_COST=$(echo "$FINAL_JSON" | jq -r '.warnings.missing_cost_events')
if [[ "$WARN_MALFORMED" -gt 0 || "$WARN_MISSING_COST" -gt 0 ]]; then
  echo "-- Warnings --"
  [[ "$WARN_MALFORMED" -gt 0 ]] && echo "malformed JSONL lines:  $WARN_MALFORMED"
  [[ "$WARN_MISSING_COST" -gt 0 ]] && echo "ai_diagnostic_run events without cost field: $WARN_MISSING_COST"
fi
