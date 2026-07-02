#!/usr/bin/env bash
# pm-iterate.sh — headless single-iteration PM runner for Resident PM (r1-r2).
#
# Runs ONE orchestration-loop iteration for the given project under strict
# guardrails (pause, interrupt, per-project flock, hourly cap, escalation gate),
# builds a bounded prompt, invokes `claude -p` (or a mock) with a hard timeout,
# and logs the transcript + a JSONL iterations-ledger line.
#
# Guard-skips print `SKIP: <reason>` and exit 0 (the r1-03 daemon treats
# exit 0 + SKIP as a benign no-op). Real invocation exits with claude's exit
# code (`timeout` propagates 124).
#
# Usage:
#   pm-iterate.sh <project-path> [--trigger response|tick|resolution]
#                                 [--response-file <path>] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCH_DIR="$(dirname "$SCRIPT_DIR")"

STATE_DIR="${ORCH_STATE_DIR:-$HOME/.orchestrator}"
REGISTRY="$STATE_DIR/active-projects.json"
LEDGER="$STATE_DIR/iterations.jsonl"
LOCK_DIR="$STATE_DIR/locks"
RUNS_DIR="$STATE_DIR/runs"

MAX_ITER_PER_HOUR="${PM_MAX_ITER_PER_HOUR:-6}"
MAX_TURNS="${PM_MAX_TURNS:-80}"
ITERATE_TIMEOUT="${PM_ITERATE_TIMEOUT:-1800}"
CLAUDE_MODEL="${PM_CLAUDE_MODEL:-}"
CLAUDE_BIN="${PM_CLAUDE_BIN:-claude}"
MOCK_FILE="${PM_ITERATE_MOCK:-}"
MOCK_EXIT="${PM_ITERATE_MOCK_EXIT:-0}"

usage() {
    cat >&2 <<'EOF'
Usage:
  pm-iterate.sh <project-path> [--trigger response|tick|resolution]
                                [--response-file <path>] [--dry-run]
EOF
    exit 1
}

[[ $# -lt 1 ]] && usage

PROJECT_PATH="$1"; shift
TRIGGER="tick"
RESPONSE_FILE=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --trigger)        TRIGGER="$2"; shift 2 ;;
        --response-file)  RESPONSE_FILE="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        -h|--help)        usage ;;
        *) echo "unknown flag: $1" >&2; usage ;;
    esac
done

case "$TRIGGER" in
    tick|response|resolution) : ;;
    *) echo "invalid --trigger: $TRIGGER" >&2; exit 1 ;;
esac

ABS_PROJECT_PATH="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
    echo "project path not found: $PROJECT_PATH" >&2
    exit 1
}
STATUS_JSON="$ABS_PROJECT_PATH/.planning/status.json"
EVENTS_JSONL="$ABS_PROJECT_PATH/.planning/events.jsonl"

# --- resolve project name: registry → status.json → basename ---
PROJECT_NAME=""
if [[ -f "$REGISTRY" ]]; then
    PROJECT_NAME="$(jq -r --arg p "$ABS_PROJECT_PATH" 'map(select(.local_path == $p)) | first.name // empty' "$REGISTRY" 2>/dev/null || true)"
fi
if [[ -z "$PROJECT_NAME" && -f "$STATUS_JSON" ]]; then
    PROJECT_NAME="$(jq -r '.project // empty' "$STATUS_JSON" 2>/dev/null || true)"
fi
[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$(basename "$ABS_PROJECT_PATH")"

# --- ensure state dirs ---
if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
fi
mkdir -p "$LOCK_DIR" "$RUNS_DIR/$PROJECT_NAME"

# ============================================================
# GUARDS (checked in order — first hit prints SKIP and exits 0)
# ============================================================

# G1: paused kill switch
if [[ -e "$STATE_DIR/paused" ]]; then
    echo "SKIP: paused"
    exit 0
fi

# G2: project interrupt
if [[ -e "$ABS_PROJECT_PATH/.planning/interrupt.json" ]]; then
    echo "SKIP: interrupted"
    exit 0
fi

# G3: non-blocking per-project flock. Must be held for the REST of the run.
LOCK_FILE="$LOCK_DIR/$PROJECT_NAME.lock"
exec {LOCKFD}>"$LOCK_FILE"
if ! flock -n "$LOCKFD"; then
    echo "SKIP: locked"
    exit 0
fi

# G4: hourly cap. Count iterations.jsonl lines for THIS project within last 3600s.
if [[ -f "$LEDGER" ]]; then
    NOW_EPOCH="$(date -u +%s)"
    CUTOFF=$((NOW_EPOCH - 3600))
    RECENT_COUNT=0
    while IFS= read -r ts; do
        [[ -z "$ts" ]] && continue
        e="$(date -u -d "$ts" +%s 2>/dev/null || echo 0)"
        if [[ "$e" -ge "$CUTOFF" ]]; then
            RECENT_COUNT=$((RECENT_COUNT + 1))
        fi
    done < <(jq -r --arg p "$PROJECT_NAME" 'select(.project == $p) | .ts' "$LEDGER" 2>/dev/null || true)
    if [[ "$RECENT_COUNT" -ge "$MAX_ITER_PER_HOUR" ]]; then
        echo "SKIP: rate-capped (${RECENT_COUNT}/${MAX_ITER_PER_HOUR} in last hour)"
        exit 0
    fi
fi

# G5: escalation gate — unresolved ai_escalation_recommended for current phase.
if [[ -f "$STATUS_JSON" && -f "$EVENTS_JSONL" ]]; then
    CURRENT_PHASE="$(jq -r '.current_phase // empty' "$STATUS_JSON" 2>/dev/null || true)"
    if [[ -n "$CURRENT_PHASE" ]]; then
        # Last event for this phase that is either ai_escalation_recommended or escalation_resolved.
        # If that latest one is ai_escalation_recommended, gate is CLOSED.
        LATEST="$(jq -rs --arg phase "$CURRENT_PHASE" '
            map(select((.event == "ai_escalation_recommended" or .event == "escalation_resolved")
                       and .data.phase == $phase))
            | last // empty
            | .event // ""
        ' "$EVENTS_JSONL" 2>/dev/null || true)"
        if [[ "$LATEST" == "ai_escalation_recommended" && "$TRIGGER" != "resolution" ]]; then
            echo "SKIP: escalated-awaiting-human"
            exit 0
        fi
    fi
fi

# G6: checkpoint gate — project-scoped (not per-phase). Rule: consider the
# latest of {checkpoint, checkpoint_acknowledged, phase_queued} in events.jsonl.
# If that latest event is `checkpoint` AND trigger != resolution → gate closed.
# A `phase_queued` AFTER a checkpoint keeps the gate OPEN (backward-compat with
# projects that resumed via an interactive session before r2-05 existed).
if [[ -f "$EVENTS_JSONL" ]]; then
    LATEST_CP="$(jq -rs '
        map(select(.event == "checkpoint" or .event == "checkpoint_acknowledged" or .event == "phase_queued"))
        | last // empty
        | .event // ""
    ' "$EVENTS_JSONL" 2>/dev/null || true)"
    if [[ "$LATEST_CP" == "checkpoint" && "$TRIGGER" != "resolution" ]]; then
        echo "SKIP: checkpoint-awaiting-human"
        exit 0
    fi
fi

# ============================================================
# PROMPT BUILD
# ============================================================
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS_SLUG="$(date -u +%Y%m%dT%H%M%SZ)"
PROMPT_FILE="$RUNS_DIR/$PROJECT_NAME/${TS_SLUG}-prompt.md"
TRANSCRIPT_FILE="$RUNS_DIR/$PROJECT_NAME/${TS_SLUG}-transcript.log"

{
    printf '# Headless PM iteration\n\n'
    printf 'You are the orchestrator PM (headless). Execute EXACTLY ONE iteration '
    printf 'of the orchestration loop for the project below, then STOP. Do not loop. '
    printf 'Do not start a second state transition.\n\n'
    printf '## Pointers\n\n'
    printf '%s\n' "- orchestrator repo dir: $ORCH_DIR"
    printf '%s\n' "- project path: $ABS_PROJECT_PATH"
    printf '%s\n' "- project name: $PROJECT_NAME"
    printf '%s\n' "- trigger: $TRIGGER"
    printf '%s\n\n' "- current UTC: $NOW_TS"
    printf '## Read first\n\n'
    printf '%s\n' "- \`$ORCH_DIR/CLAUDE.md\` — orchestration loop + verification + autonomy rules"
    printf '%s\n\n' "- \`$ABS_PROJECT_PATH/.planning/status.json\` — current state"
    if [[ -n "$RESPONSE_FILE" ]]; then
        printf '## Worker response (task awaiting verification)\n\n'
        printf 'Source file: `%s`\n\n' "$RESPONSE_FILE"
        printf '```json\n'
        cat "$RESPONSE_FILE" 2>/dev/null || echo '{}'
        printf '\n```\n\n'
    fi
    printf '## Hard rules (verbatim)\n\n'
    printf '%s\n' '- ONE state transition only (e.g. verify-and-complete OR verify-and-revise OR spec-and-queue next phase), then exit.'
    printf '%s\n' "- Dispatch ONLY via \`$ORCH_DIR/scripts/queue-phase.sh\` — never call add-task.sh directly (the ledger must stay consistent)."
    printf '%s\n' '- Never implement project code yourself; never skip verification; respect all CLAUDE.md NEVER rules including the escalation rule.'
    printf '%s\n' "- On checkpoint due, escalation, max-revisions, or project completion: call \`$ORCH_DIR/scripts/notify.sh <event> $ABS_PROJECT_PATH ...\` and STOP."
    printf '%s\n' "- Update \`.planning/status.json\` + \`events.jsonl\`, commit \`.planning/\` with prefix \`[$PROJECT_NAME-orchestrator]\`, and push, before exiting."
} > "$PROMPT_FILE"

# --- dry-run short-circuit (must be side-effect free beyond the prompt file) ---
if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRYRUN: prompt at $PROMPT_FILE"
    exit 0
fi

# --- iteration_started event (before invoking claude) ---
if [[ -d "$ABS_PROJECT_PATH/.planning" ]]; then
    EVENT_LINE="$(jq -c -n \
        --arg ts "$NOW_TS" \
        --arg trigger "$TRIGGER" \
        '{ts: $ts, event: "pm_iteration", data: {trigger: $trigger, runner: "pm-iterate"}}')"
    printf '%s\n' "$EVENT_LINE" >> "$EVENTS_JSONL"
fi

# ============================================================
# INVOCATION
# ============================================================
START_EPOCH="$(date -u +%s)"

if [[ -n "$MOCK_FILE" ]]; then
    if [[ -f "$MOCK_FILE" ]]; then
        cp "$MOCK_FILE" "$TRANSCRIPT_FILE"
    else
        : > "$TRANSCRIPT_FILE"
    fi
    EXIT_CODE="$MOCK_EXIT"
else
    CLAUDE_ARGS=(-p "$(cat "$PROMPT_FILE")"
                 --allowedTools Bash,Read,Write,Edit,Glob,Grep
                 --max-turns "$MAX_TURNS"
                 --output-format text)
    if [[ -n "$CLAUDE_MODEL" ]]; then
        CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
    fi
    set +e
    ( cd "$ABS_PROJECT_PATH" && timeout "$ITERATE_TIMEOUT" "$CLAUDE_BIN" "${CLAUDE_ARGS[@]}" ) \
        > "$TRANSCRIPT_FILE" 2>&1
    EXIT_CODE=$?
    set -e
fi

END_EPOCH="$(date -u +%s)"
DURATION=$((END_EPOCH - START_EPOCH))

LEDGER_LINE="$(jq -c -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg project "$PROJECT_NAME" \
    --arg trigger "$TRIGGER" \
    --argjson exit_code "$EXIT_CODE" \
    --argjson duration_s "$DURATION" \
    --arg prompt "$PROMPT_FILE" \
    --arg transcript "$TRANSCRIPT_FILE" \
    '{ts: $ts, project: $project, trigger: $trigger, exit_code: $exit_code, duration_s: $duration_s, prompt: $prompt, transcript: $transcript}')"
printf '%s\n' "$LEDGER_LINE" >> "$LEDGER"

echo "RAN: exit=$EXIT_CODE transcript=$TRANSCRIPT_FILE"
exit "$EXIT_CODE"
