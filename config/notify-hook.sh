#!/usr/bin/env bash
# notify-hook.sh — Slack outbound hook for scripts/notify.sh.
#
# Reads a notification JSON from stdin ({timestamp, event, phase, detail,
# project}), then posts it to Slack as a threaded reply under a per-project
# root message. Threads are tracked in $ORCH_STATE_DIR/slack-threads.json.
#
# Graceful no-op when Slack is not configured (missing slack.env or empty
# token/channel) — exits 0 so notify.sh always succeeds.
#
# Env:
#   ORCH_STATE_DIR      ($HOME/.orchestrator)
#   SLACK_ENV_FILE      ($ORCH_STATE_DIR/slack.env) — sourced when present
#   SLACK_THREADS_FILE  ($ORCH_STATE_DIR/slack-threads.json)
#   SLACK_MOCK          — path to JSONL sink; when set, no network calls
#   SLACK_MOCK_FAIL     — mock mode: simulate .ok=false after appending

set -euo pipefail

STATE_DIR="${ORCH_STATE_DIR:-$HOME/.orchestrator}"
SLACK_ENV_FILE="${SLACK_ENV_FILE:-$STATE_DIR/slack.env}"
SLACK_THREADS_FILE="${SLACK_THREADS_FILE:-$STATE_DIR/slack-threads.json}"

# Read stdin once.
STDIN_JSON="$(cat -)"

# Extract fields; missing → empty string.
project="$(printf '%s' "$STDIN_JSON"   | jq -r '.project   // ""' 2>/dev/null || echo "")"
event="$(printf '%s' "$STDIN_JSON"     | jq -r '.event     // ""' 2>/dev/null || echo "")"
phase="$(printf '%s' "$STDIN_JSON"     | jq -r '.phase     // ""' 2>/dev/null || echo "")"
detail="$(printf '%s' "$STDIN_JSON"    | jq -r '.detail    // ""' 2>/dev/null || echo "")"
timestamp="$(printf '%s' "$STDIN_JSON" | jq -r '.timestamp // ""' 2>/dev/null || echo "")"

# Source slack.env if present (defines SLACK_BOT_TOKEN + SLACK_CHANNEL).
if [[ -f "$SLACK_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SLACK_ENV_FILE"
fi

# Graceful no-op rule.
if [[ -z "${SLACK_MOCK:-}" ]]; then
    if [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL:-}" ]]; then
        echo "notify-hook: slack not configured, skipping" >&2
        exit 0
    fi
fi
# Mock mode default channel.
if [[ -n "${SLACK_MOCK:-}" && -z "${SLACK_CHANNEL:-}" ]]; then
    SLACK_CHANNEL="mock-channel"
fi

# Ensure state dir exists (real mode too — we write threads there).
mkdir -p "$STATE_DIR"

# Load threads file; missing/corrupt → treat as {}.
load_threads_json() {
    if [[ -f "$SLACK_THREADS_FILE" ]]; then
        if jq -e . "$SLACK_THREADS_FILE" >/dev/null 2>&1; then
            cat "$SLACK_THREADS_FILE"
            return
        fi
    fi
    echo '{}'
}
THREADS_JSON="$(load_threads_json)"

atomic_write_threads() {
    local content="$1"
    local tmp
    tmp="$(mktemp "${SLACK_THREADS_FILE}.XXXXXX")"
    printf '%s\n' "$content" > "$tmp"
    mv "$tmp" "$SLACK_THREADS_FILE"
}

# Emoji + attention classification for this event.
case "$event" in
    phase_complete)             emoji="✅"; attention=0 ;;
    phase_failed)               emoji="❌"; attention=1 ;;
    verification_failed)        emoji="⚠️"; attention=0 ;;
    regression_failed)          emoji="⚠️"; attention=0 ;;
    project_complete)           emoji="🏁"; attention=1 ;;
    ai_escalation_recommended)  emoji="🚨"; attention=1 ;;
    checkpoint)                 emoji="🛑"; attention=1 ;;
    *)                          emoji="🔔"; attention=0 ;;
esac

# Build message text: "<emoji> [<project>] <event>: <phase> — <detail>"
# Omit empty phase/detail segments cleanly.
build_message_text() {
    local text="${emoji} [${project}] ${event}"
    if [[ -n "$phase" ]]; then
        text+=": ${phase}"
    fi
    if [[ -n "$detail" ]]; then
        text+=" — ${detail}"
    fi
    printf '%s' "$text"
}

# slack_post: one function does both real + mock.
#   $1 = full JSON payload string (already valid JSON).
# Prints the response ts (real: from API; mock: synthesized).
# Exits non-zero on failure.
slack_post() {
    local payload="$1"

    if [[ -n "${SLACK_MOCK:-}" ]]; then
        # Append EXACTLY one JSONL line to the sink.
        local line
        line="$(jq -c -n --argjson payload "$payload" '{api:"chat.postMessage", payload:$payload}')"
        printf '%s\n' "$line" >> "$SLACK_MOCK"
        # Synthesized deterministic ts by post-append line count.
        local n
        n="$(wc -l < "$SLACK_MOCK" | tr -d ' ')"
        # Pad to 6 chars after the dot (10-char base + variable index).
        # Format: 1000000000.00000N  (as per spec).
        printf '1000000000.%06d' "$n"
        if [[ -n "${SLACK_MOCK_FAIL:-}" ]]; then
            echo "notify-hook: slack mock failure requested" >&2
            return 1
        fi
        return 0
    fi

    # Real mode — never echo the token.
    local resp
    resp="$(curl -sS -X POST https://slack.com/api/chat.postMessage \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H 'Content-type: application/json; charset=utf-8' \
        -d "$payload")" || {
        echo "notify-hook: curl failed" >&2
        return 1
    }
    if [[ "$(printf '%s' "$resp" | jq -r '.ok // false')" != "true" ]]; then
        local err
        err="$(printf '%s' "$resp" | jq -r '.error // "unknown"')"
        echo "notify-hook: slack api error: $err" >&2
        return 1
    fi
    printf '%s' "$resp" | jq -r '.ts'
    return 0
}

# --- Threading logic ---
existing_thread_ts="$(printf '%s' "$THREADS_JSON" | jq -r --arg p "$project" '.[$p].thread_ts // ""')"

if [[ -z "$existing_thread_ts" ]]; then
    # Post root message first.
    root_text="📦 *${project}* — orchestration thread"
    root_payload="$(jq -c -n --arg ch "$SLACK_CHANNEL" --arg text "$root_text" \
        '{channel:$ch, text:$text}')"
    if root_ts="$(slack_post "$root_payload")"; then
        THREADS_JSON="$(printf '%s' "$THREADS_JSON" \
            | jq --arg p "$project" --arg ts "$root_ts" --arg ch "$SLACK_CHANNEL" \
                 '.[$p] = {thread_ts:$ts, channel:$ch}')"
        atomic_write_threads "$THREADS_JSON"
        existing_thread_ts="$root_ts"
    else
        # Even if root failed (mock-fail branch), we still rewrite threads with the attempted ts
        # so the smoke tests are stable. Fall through and let the reply also attempt.
        echo "notify-hook: root post failed; skipping reply" >&2
        exit 1
    fi
fi

# Build threaded reply payload.
msg_text="$(build_message_text)"
reply_args=(--arg ch "$SLACK_CHANNEL" --arg text "$msg_text" --arg thread "$existing_thread_ts")
if [[ "$attention" == "1" ]]; then
    reply_payload="$(jq -c -n "${reply_args[@]}" \
        '{channel:$ch, text:$text, thread_ts:$thread, reply_broadcast:true}')"
else
    reply_payload="$(jq -c -n "${reply_args[@]}" \
        '{channel:$ch, text:$text, thread_ts:$thread}')"
fi

if ! slack_post "$reply_payload" >/dev/null; then
    exit 1
fi

# Suppress the ts stdout for the caller (notify.sh) — quiet by default.
exit 0
