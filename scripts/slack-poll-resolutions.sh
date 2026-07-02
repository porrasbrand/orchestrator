#!/usr/bin/env bash
# slack-poll-resolutions.sh — r2-05 inbound polling → resolutions pipeline.
#
# One pass over registry projects that are actually awaiting a human (escalation
# gate or checkpoint gate closed): fetch new thread replies via Slack
# conversations.replies (or SLACK_REPLIES_MOCK fixture), parse each reply,
# append to <project>/.planning/resolutions.jsonl + the appropriate gate-release
# event in events.jsonl, ACK in thread (via the r2-04 SLACK_MOCK convention),
# and kick pm-iterate.sh --trigger resolution. Cursor per project in
# $ORCH_STATE_DIR/slack-resolutions-state.json — a re-run with the same fixture
# is a complete no-op.
#
# Command grammar (first line of the reply text, trimmed, case-insensitive):
#   continue | retry           → kind=continue
#   abort                      → kind=abort
#   override: <text>           → kind=override (rest of message captured verbatim)
#   anything else              → kind=unrecognized
#
# Override consumption (for future reference — NOT this script's job):
# revision-spec authoring (headless PM) reads .planning/resolutions.jsonl and
# injects the newest override for the current phase into the next revision
# spec. That consumption lives in the prompt / CLAUDE.md.
#
# Usage:
#   slack-poll-resolutions.sh [--project <name>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

STATE_DIR="${ORCH_STATE_DIR:-$HOME/.orchestrator}"
SLACK_ENV_FILE="${SLACK_ENV_FILE:-$STATE_DIR/slack.env}"
SLACK_THREADS_FILE="${SLACK_THREADS_FILE:-$STATE_DIR/slack-threads.json}"
RESOLUTIONS_STATE_FILE="${RESOLUTIONS_STATE_FILE:-$STATE_DIR/slack-resolutions-state.json}"
REGISTRY_FILE="$STATE_DIR/active-projects.json"
PM_ITERATE_BIN="${PM_ITERATE_BIN:-$REPO_DIR/scripts/pm-iterate.sh}"

ONLY_PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) ONLY_PROJECT="$2"; shift 2 ;;
        -h|--help) echo "Usage: slack-poll-resolutions.sh [--project <name>]" >&2; exit 1 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

# Source slack.env if present (real mode); mock mode skips network entirely.
if [[ -f "$SLACK_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SLACK_ENV_FILE"
fi

# Graceful no-op rule.
if [[ -z "${SLACK_REPLIES_MOCK:-}" ]]; then
    if [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL:-}" ]]; then
        echo "slack-poll: slack not configured, skipping" >&2
        exit 0
    fi
fi

mkdir -p "$STATE_DIR"

# ---- helpers ----
safe_json_or_empty() {
    # $1 = file. Prints JSON content (must be valid) or "{}" if missing/corrupt.
    local f="$1"
    if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
        cat "$f"
    else
        echo '{}'
    fi
}

safe_json_or_empty_arr() {
    local f="$1"
    if [[ -f "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
        cat "$f"
    else
        echo '[]'
    fi
}

atomic_write() {
    # $1 = target, stdin = content
    local target="$1"
    local tmp
    tmp="$(mktemp "${target}.XXXXXX")"
    cat > "$tmp"
    mv "$tmp" "$target"
}

# Given events.jsonl path + phase, is the escalation gate CLOSED?
escalation_gate_closed() {
    local ev="$1" phase="$2"
    [[ -f "$ev" ]] || return 1
    local latest
    latest="$(jq -rs --arg phase "$phase" '
        map(select((.event == "ai_escalation_recommended" or .event == "escalation_resolved")
                   and .data.phase == $phase))
        | last // empty
        | .event // ""
    ' "$ev" 2>/dev/null || true)"
    [[ "$latest" == "ai_escalation_recommended" ]]
}

# Is the project-scope checkpoint gate CLOSED?
checkpoint_gate_closed() {
    local ev="$1"
    [[ -f "$ev" ]] || return 1
    local latest
    latest="$(jq -rs '
        map(select(.event == "checkpoint" or .event == "checkpoint_acknowledged" or .event == "phase_queued"))
        | last // empty
        | .event // ""
    ' "$ev" 2>/dev/null || true)"
    [[ "$latest" == "checkpoint" ]]
}

# outbound Slack post — respects SLACK_MOCK (r2-04 convention).
slack_ack() {
    # $1 = channel, $2 = thread_ts, $3 = text
    local channel="$1" thread="$2" text="$3"
    local payload
    payload="$(jq -c -n --arg ch "$channel" --arg text "$text" --arg thread "$thread" \
        '{channel:$ch, text:$text, thread_ts:$thread}')"
    if [[ -n "${SLACK_MOCK:-}" ]]; then
        jq -c -n --argjson payload "$payload" '{api:"chat.postMessage", payload:$payload}' >> "$SLACK_MOCK"
        return 0
    fi
    # real mode
    local resp
    if ! resp="$(curl -sS -X POST https://slack.com/api/chat.postMessage \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            -H 'Content-type: application/json; charset=utf-8' \
            -d "$payload")"; then
        echo "slack-poll: ack curl failed" >&2
        return 1
    fi
    if [[ "$(printf '%s' "$resp" | jq -r '.ok // false')" != "true" ]]; then
        echo "slack-poll: ack slack error: $(printf '%s' "$resp" | jq -r '.error // "unknown"')" >&2
        return 1
    fi
    return 0
}

# fetch conversations.replies for a thread. Prints the JSON to stdout.
fetch_replies() {
    # $1 = channel, $2 = thread_ts, $3 = oldest_ts
    local channel="$1" thread="$2" oldest="$3"
    if [[ -n "${SLACK_REPLIES_MOCK:-}" ]]; then
        # Fixture form: { "<thread_ts>": { ok:true, messages:[...] }, ... }
        if [[ ! -f "$SLACK_REPLIES_MOCK" ]]; then
            echo '{"ok":true,"messages":[]}'
            return 0
        fi
        jq -c --arg t "$thread" '.[$t] // {ok:true, messages:[]}' "$SLACK_REPLIES_MOCK"
        return 0
    fi
    local resp
    if ! resp="$(curl -sS -G "https://slack.com/api/conversations.replies" \
            -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
            --data-urlencode "channel=$channel" \
            --data-urlencode "ts=$thread" \
            --data-urlencode "oldest=$oldest" \
            --data-urlencode "limit=200")"; then
        echo "slack-poll: fetch curl failed" >&2
        echo '{"ok":false}'
        return 0
    fi
    echo "$resp"
}

# ---- main loop over eligible projects ----
REGISTRY_JSON="$(safe_json_or_empty_arr "$REGISTRY_FILE")"
THREADS_JSON="$(safe_json_or_empty "$SLACK_THREADS_FILE")"
CURSORS_JSON="$(safe_json_or_empty "$RESOLUTIONS_STATE_FILE")"

# Ensure cursor file exists (for atomic later rewrites).
if [[ ! -f "$RESOLUTIONS_STATE_FILE" ]]; then
    printf '%s\n' "$CURSORS_JSON" | atomic_write "$RESOLUTIONS_STATE_FILE"
fi

eligible=0
processed=0

# jq stream of project objects.
# shellcheck disable=SC2016
projects_stream="$(printf '%s' "$REGISTRY_JSON" | jq -c '.[]?' 2>/dev/null || true)"

while IFS= read -r proj; do
    [[ -z "$proj" ]] && continue
    NAME="$(printf '%s' "$proj" | jq -r '.name // ""')"
    LOCAL_PATH="$(printf '%s' "$proj" | jq -r '.local_path // ""')"
    ACTIVE="$(printf '%s' "$proj" | jq -r '.active // true')"
    [[ "$ACTIVE" == "false" ]] && continue
    [[ -n "$ONLY_PROJECT" && "$NAME" != "$ONLY_PROJECT" ]] && continue

    # Skip projects without a Slack thread.
    THREAD_ENTRY="$(printf '%s' "$THREADS_JSON" | jq -c --arg n "$NAME" '.[$n] // null')"
    [[ "$THREAD_ENTRY" == "null" ]] && continue
    THREAD_TS="$(printf '%s' "$THREAD_ENTRY" | jq -r '.thread_ts // ""')"
    CHANNEL="$(printf '%s' "$THREAD_ENTRY" | jq -r '.channel // ""')"
    [[ -z "$THREAD_TS" || -z "$CHANNEL" ]] && continue

    STATUS_JSON="$LOCAL_PATH/.planning/status.json"
    EVENTS_JSONL="$LOCAL_PATH/.planning/events.jsonl"
    PHASE=""
    if [[ -f "$STATUS_JSON" ]]; then
        PHASE="$(jq -r '.current_phase // ""' "$STATUS_JSON" 2>/dev/null || true)"
    fi

    # Eligibility: at least one gate closed.
    esc_closed=0; cp_closed=0
    if escalation_gate_closed "$EVENTS_JSONL" "$PHASE"; then esc_closed=1; fi
    if checkpoint_gate_closed "$EVENTS_JSONL"; then cp_closed=1; fi
    if [[ "$esc_closed" == "0" && "$cp_closed" == "0" ]]; then
        continue
    fi
    eligible=$((eligible + 1))

    # Cursor lookup
    CURSOR="$(printf '%s' "$CURSORS_JSON" | jq -r --arg n "$NAME" '.[$n].last_ts // "0"')"

    REPLIES_JSON="$(fetch_replies "$CHANNEL" "$THREAD_TS" "$CURSOR")"
    OK="$(printf '%s' "$REPLIES_JSON" | jq -r '.ok // false' 2>/dev/null || echo false)"
    if [[ "$OK" != "true" ]]; then
        echo "slack-poll: replies fetch failed for $NAME (ok=false)" >&2
        continue
    fi

    # Max ts across ALL messages seen (parent + bots included) — advances cursor.
    MAX_TS_ALL="$(printf '%s' "$REPLIES_JSON" | jq -r '[.messages[]?.ts // "0"] | max // "0"')"

    # Filter: drop parent, drop bots, drop ts <= cursor, sort ascending.
    FILTERED_JSON="$(printf '%s' "$REPLIES_JSON" | jq -c --arg thread "$THREAD_TS" --arg cursor "$CURSOR" '
        [.messages[]?
          | select((.ts // "") != $thread)
          | select(has("bot_id") | not)
          | select((.ts // "0") > $cursor)
        ] | sort_by(.ts)
    ')"
    COUNT="$(printf '%s' "$FILTERED_JSON" | jq 'length')"
    [[ -z "$COUNT" ]] && COUNT=0

    processed=$((processed + COUNT))

    # Iterate each filtered reply.
    for i in $(seq 0 $((COUNT - 1))); do
        MSG="$(printf '%s' "$FILTERED_JSON" | jq -c ".[$i]")"
        REPLY_TS="$(printf '%s' "$MSG" | jq -r '.ts // ""')"
        USER="$(printf '%s' "$MSG" | jq -r '.user // ""')"
        TEXT="$(printf '%s' "$MSG" | jq -r '.text // ""')"

        # First line, trimmed, lowercased.
        FIRSTLINE="$(printf '%s' "$TEXT" | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        LOWER="$(printf '%s' "$FIRSTLINE" | tr '[:upper:]' '[:lower:]')"

        KIND=""
        OVERRIDE_TEXT=""
        if [[ "$LOWER" == "continue" || "$LOWER" == "retry" ]]; then
            KIND="continue"
        elif [[ "$LOWER" == "abort" ]]; then
            KIND="abort"
        elif [[ "$LOWER" =~ ^override:[[:space:]]*(.*)$ ]]; then
            KIND="override"
            # Strip "override:" (case-insensitive) + optional leading space from full text.
            OVERRIDE_TEXT="$(printf '%s' "$TEXT" | sed -E 's/^[Oo][Vv][Ee][Rr][Rr][Ii][Dd][Ee]:[[:space:]]*//')"
        else
            KIND="unrecognized"
        fi

        NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        GATE_NAME="escalation"
        [[ "$esc_closed" == "0" && "$cp_closed" == "1" ]] && GATE_NAME="checkpoint"

        case "$KIND" in
            continue|override)
                # Append resolutions.jsonl
                if [[ "$KIND" == "override" ]]; then
                    RES_LINE="$(jq -c -n \
                        --arg ts "$NOW_TS" --arg phase "$PHASE" --arg kind "$KIND" --arg text "$OVERRIDE_TEXT" \
                        --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" --arg gate "$GATE_NAME" \
                        '{ts:$ts, phase:$phase, kind:$kind, text:$text, source:$source, user:$user, reply_ts:$reply_ts, gate:$gate}')"
                else
                    RES_LINE="$(jq -c -n \
                        --arg ts "$NOW_TS" --arg phase "$PHASE" --arg kind "$KIND" \
                        --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" --arg gate "$GATE_NAME" \
                        '{ts:$ts, phase:$phase, kind:$kind, source:$source, user:$user, reply_ts:$reply_ts, gate:$gate}')"
                fi
                printf '%s\n' "$RES_LINE" >> "$LOCAL_PATH/.planning/resolutions.jsonl"

                # Gate-release event(s)
                RESOLUTION_LABEL="$KIND"
                if [[ "$esc_closed" == "1" ]]; then
                    EV="$(jq -c -n --arg ts "$NOW_TS" --arg name "escalation_resolved" \
                        --arg phase "$PHASE" --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" \
                        --arg resolution "$RESOLUTION_LABEL" \
                        '{ts:$ts, event:$name, data:{phase:$phase, source:$source, user:$user, reply_ts:$reply_ts, resolution:$resolution}}')"
                    printf '%s\n' "$EV" >> "$EVENTS_JSONL"
                fi
                if [[ "$cp_closed" == "1" ]]; then
                    EV="$(jq -c -n --arg ts "$NOW_TS" --arg name "checkpoint_acknowledged" \
                        --arg phase "$PHASE" --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" \
                        --arg resolution "$RESOLUTION_LABEL" \
                        '{ts:$ts, event:$name, data:{phase:$phase, source:$source, user:$user, reply_ts:$reply_ts, resolution:$resolution}}')"
                    printf '%s\n' "$EV" >> "$EVENTS_JSONL"
                fi

                # ACK
                if [[ "$KIND" == "continue" ]]; then
                    ACK_TEXT="▶️ [${NAME}] resuming — ${PHASE}"
                else
                    ACK_TEXT="✏️ [${NAME}] override applied — resuming ${PHASE}"
                fi
                slack_ack "$CHANNEL" "$THREAD_TS" "$ACK_TEXT" || true

                # Invoke pm-iterate best-effort
                if [[ -x "$PM_ITERATE_BIN" ]]; then
                    set +e
                    ITER_OUT="$("$PM_ITERATE_BIN" "$LOCAL_PATH" --trigger resolution 2>&1)"
                    ITER_RC=$?
                    set -e
                    echo "slack-poll: pm-iterate exit=$ITER_RC out=${ITER_OUT:0:200}"
                else
                    echo "slack-poll: PM_ITERATE_BIN missing/non-executable: $PM_ITERATE_BIN" >&2
                fi
                ;;

            abort)
                RES_LINE="$(jq -c -n \
                    --arg ts "$NOW_TS" --arg phase "$PHASE" --arg kind "abort" \
                    --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" --arg gate "$GATE_NAME" \
                    '{ts:$ts, phase:$phase, kind:$kind, source:$source, user:$user, reply_ts:$reply_ts, gate:$gate}')"
                printf '%s\n' "$RES_LINE" >> "$LOCAL_PATH/.planning/resolutions.jsonl"

                # status.json (atomic tmp+mv)
                if [[ -f "$STATUS_JSON" ]]; then
                    TODAY="$(date -u +%Y-%m-%d)"
                    NEW_STATUS_JSON="$(jq --arg phase "$PHASE" --arg user "$USER" --arg today "$TODAY" '
                        .phases[$phase].status = "blocked"
                        | .blocked = true
                        | .blocked_reason = ("aborted via Slack by " + $user)
                        | .updated = $today
                    ' "$STATUS_JSON")"
                    printf '%s\n' "$NEW_STATUS_JSON" | atomic_write "$STATUS_JSON"
                fi

                EV="$(jq -c -n --arg ts "$NOW_TS" --arg name "phase_aborted" \
                    --arg phase "$PHASE" --arg source slack --arg user "$USER" --arg reply_ts "$REPLY_TS" \
                    '{ts:$ts, event:$name, data:{phase:$phase, source:$source, user:$user, reply_ts:$reply_ts}}')"
                printf '%s\n' "$EV" >> "$EVENTS_JSONL"

                # notify.sh (this is the Slack confirmation — no separate ACK)
                "$REPO_DIR/scripts/notify.sh" phase_aborted "$LOCAL_PATH" \
                    --phase "$PHASE" --detail "aborted via Slack" || true

                # No pm-iterate for abort.
                ;;

            unrecognized)
                slack_ack "$CHANNEL" "$THREAD_TS" \
                    "🤖 [${NAME}] unrecognized — commands: continue | abort | override: <text>" || true
                ;;
        esac
    done

    # Advance cursor (max ts across ALL messages seen, incl. parent/bots).
    if [[ -n "$MAX_TS_ALL" && "$MAX_TS_ALL" != "0" && "$MAX_TS_ALL" != "null" ]]; then
        CURSORS_JSON="$(printf '%s' "$CURSORS_JSON" | jq --arg n "$NAME" --arg ts "$MAX_TS_ALL" '
            .[$n] = {last_ts: $ts}
        ')"
        printf '%s\n' "$CURSORS_JSON" | atomic_write "$RESOLUTIONS_STATE_FILE"
    fi
done <<< "$projects_stream"

echo "slack-poll: eligible=$eligible processed=$processed"
exit 0
