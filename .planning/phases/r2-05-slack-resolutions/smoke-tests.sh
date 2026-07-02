#!/usr/bin/env bash
# smoke-tests.sh — hermetic tests for r2-05 Slack inbound polling.
# SLACK_REPLIES_MOCK for inbound, SLACK_MOCK for outbound, PM_ITERATE_BIN mock for pm-iterate.
# Never invokes real Slack or real claude.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

fresh_env() {
    T="$(mktemp -d)"
    export ORCH_STATE_DIR="$T/state"
    export SLACK_MOCK="$T/out.jsonl"
    export SLACK_REPLIES_MOCK="$T/replies.json"
    export SLACK_THREADS_FILE="$T/state/slack-threads.json"
    export RESOLUTIONS_STATE_FILE="$T/state/slack-resolutions-state.json"
    unset SLACK_BOT_TOKEN SLACK_CHANNEL SLACK_ENV_FILE || true
    mkdir -p "$ORCH_STATE_DIR" "$T/proj/.planning"
    : > "$SLACK_MOCK"
    echo '{}' > "$SLACK_REPLIES_MOCK"

    # Fake project status.json + events.jsonl
    cat > "$T/proj/.planning/status.json" <<'JSON'
{
  "project": "projA",
  "current_phase": "p1",
  "phases": { "p1": { "status": "verifying" } }
}
JSON
    : > "$T/proj/.planning/events.jsonl"

    # Registry
    jq -n --arg lp "$T/proj" '[
        {name:"projA", local_path:$lp, worker:"hetzner", remote_path:"", active:true, registered_at:"2026-07-02T00:00:00Z"}
    ]' > "$ORCH_STATE_DIR/active-projects.json"

    # Threads file with an entry for projA
    jq -n '{ "projA": { "thread_ts": "1000000000.000001", "channel": "C0TEST" } }' > "$SLACK_THREADS_FILE"

    # Mock pm-iterate
    cat > "$T/mock-iterate.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${T:-/tmp}/iterate-calls.log"
echo "RAN: exit=0 transcript=/dev/null"
exit 0
MOCK
    chmod +x "$T/mock-iterate.sh"
    export PM_ITERATE_BIN="$T/mock-iterate.sh"
    export T
    : > "$T/iterate-calls.log"
}

# Helper: append an ai_escalation_recommended event for phase p1
esc() {
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{ts:$ts, event:"ai_escalation_recommended", data:{phase:"p1"}}' \
        >> "$T/proj/.planning/events.jsonl"
}
# Helper: append a checkpoint event
cp_event() {
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{ts:$ts, event:"checkpoint", data:{phase:"p1"}}' \
        >> "$T/proj/.planning/events.jsonl"
}
# Helper: set replies fixture for the thread
reply_only() {
    # $1 = user, $2 = text (single reply)
    local user="$1" text="$2"
    jq -n --arg ts "1000000000.000010" --arg user "$user" --arg text "$text" '
        { "1000000000.000001": {
            ok: true,
            messages: [
                { ts: "1000000000.000001", type: "message", subtype: "root", text: "root" },
                { ts: $ts, user: $user, text: $text }
            ]
        }}
    ' > "$SLACK_REPLIES_MOCK"
}

cleanup() { [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

cd "$ORCH_DIR"
POLL="scripts/slack-poll-resolutions.sh"

# --- T1: not configured → graceful no-op ---
echo "T1: not configured → graceful no-op"
fresh_env
env -u SLACK_REPLIES_MOCK -u SLACK_MOCK -u SLACK_BOT_TOKEN -u SLACK_CHANNEL \
    ORCH_STATE_DIR="$T/state" SLACK_THREADS_FILE="$T/state/slack-threads.json" \
    bash "$POLL" 2>/dev/null
RC=$?
if [[ "$RC" == "0" ]]; then
    pass "T1: exit 0 when unconfigured"
else
    fail "T1: rc=$RC"
fi
cleanup

# --- T2: no closed gate → not polled ---
echo "T2: no closed gate → not polled"
fresh_env
OUT="$(bash "$POLL" 2>&1)"
if echo "$OUT" | grep -q 'eligible=0'; then
    pass "T2a: eligible=0"
else
    fail "T2a: out=$OUT"
fi
if [[ ! -s "$SLACK_MOCK" ]]; then
    pass "T2b: no ACK posted"
else
    fail "T2b: ACK was posted"
fi
cleanup

# --- T3: escalation + continue → full resolution flow ---
echo "T3: escalation + continue → full flow"
fresh_env
esc
reply_only "U_HUMAN" "continue"
bash "$POLL" >/dev/null 2>&1
if grep -q '"event":"escalation_resolved"' "$T/proj/.planning/events.jsonl"; then
    pass "T3a: escalation_resolved event appended"
else
    fail "T3a: escalation_resolved event missing"
fi
if tail -1 "$T/proj/.planning/resolutions.jsonl" | jq -e '.kind=="continue" and .source=="slack" and .user=="U_HUMAN"' >/dev/null; then
    pass "T3b: resolutions.jsonl line correct"
else
    fail "T3b: resolutions line wrong: $(tail -1 "$T/proj/.planning/resolutions.jsonl")"
fi
if tail -1 "$SLACK_MOCK" | jq -e '.payload.thread_ts=="1000000000.000001" and (.payload.text|contains("▶️"))' >/dev/null; then
    pass "T3c: ▶️ ACK posted threaded"
else
    fail "T3c: ACK payload wrong"
fi
if grep -q -- '--trigger resolution' "$T/iterate-calls.log"; then
    pass "T3d: mock pm-iterate called with --trigger resolution"
else
    fail "T3d: mock pm-iterate not called with --trigger resolution"
fi
# --- T4: idempotent re-run (same $T) ---
echo "T4: idempotent re-run"
EV_BEFORE="$(wc -l < "$T/proj/.planning/events.jsonl")"
RES_BEFORE="$(wc -l < "$T/proj/.planning/resolutions.jsonl")"
OUT_BEFORE="$(wc -l < "$SLACK_MOCK")"
ITER_BEFORE="$(wc -l < "$T/iterate-calls.log")"
bash "$POLL" >/dev/null 2>&1
EV_AFTER="$(wc -l < "$T/proj/.planning/events.jsonl")"
RES_AFTER="$(wc -l < "$T/proj/.planning/resolutions.jsonl")"
OUT_AFTER="$(wc -l < "$SLACK_MOCK")"
ITER_AFTER="$(wc -l < "$T/iterate-calls.log")"
if [[ "$EV_BEFORE" == "$EV_AFTER" && "$RES_BEFORE" == "$RES_AFTER" \
      && "$OUT_BEFORE" == "$OUT_AFTER" && "$ITER_BEFORE" == "$ITER_AFTER" ]]; then
    pass "T4: idempotent (all counters stable)"
else
    fail "T4: counters moved (events $EV_BEFORE→$EV_AFTER, res $RES_BEFORE→$RES_AFTER, out $OUT_BEFORE→$OUT_AFTER, iter $ITER_BEFORE→$ITER_AFTER)"
fi
cleanup

# --- T5: override captured verbatim ---
echo "T5: override captured verbatim"
fresh_env
esc
reply_only "U_HUMAN" "override: use bearer auth"
bash "$POLL" >/dev/null 2>&1
if tail -1 "$T/proj/.planning/resolutions.jsonl" | jq -e '.kind=="override" and .text=="use bearer auth"' >/dev/null; then
    pass "T5a: override text captured verbatim"
else
    fail "T5a: override wrong: $(tail -1 "$T/proj/.planning/resolutions.jsonl")"
fi
if grep -q '"resolution":"override"' "$T/proj/.planning/events.jsonl"; then
    pass "T5b: gate-release event carries resolution=override"
else
    fail "T5b: resolution=override missing"
fi
cleanup

# --- T6: abort → blocked + notify, no pm-iterate ---
echo "T6: abort → blocked + phase_aborted + notify, NO pm-iterate"
fresh_env
esc
reply_only "U_HUMAN" "abort"
bash "$POLL" >/dev/null 2>&1
if jq -e '.phases.p1.status=="blocked" and .blocked==true and (.blocked_reason|contains("U_HUMAN"))' "$T/proj/.planning/status.json" >/dev/null; then
    pass "T6a: status.json blocked with user in reason"
else
    fail "T6a: status.json not blocked"
fi
if grep -q '"event":"phase_aborted"' "$T/proj/.planning/events.jsonl"; then
    pass "T6b: phase_aborted event appended"
else
    fail "T6b: phase_aborted event missing"
fi
if [[ -f "$T/proj/.planning/notifications.md" ]] && grep -q 'Phase aborted' "$T/proj/.planning/notifications.md"; then
    pass "T6c: notify.sh recorded Phase aborted"
else
    fail "T6c: notifications.md missing 'Phase aborted'"
fi
if [[ ! -s "$T/iterate-calls.log" ]]; then
    pass "T6d: pm-iterate NOT called on abort"
else
    fail "T6d: pm-iterate WAS called on abort"
fi
cleanup

# --- T7: unrecognized → help ACK only ---
echo "T7: unrecognized → help ACK only"
fresh_env
esc
reply_only "U_HUMAN" "sure why not"
bash "$POLL" >/dev/null 2>&1
if tail -1 "$SLACK_MOCK" | jq -e '.payload.text|contains("🤖") and contains("unrecognized")' >/dev/null; then
    pass "T7a: 🤖 help ACK posted"
else
    fail "T7a: help ACK wrong: $(tail -1 "$SLACK_MOCK")"
fi
if [[ ! -f "$T/proj/.planning/resolutions.jsonl" ]] || [[ "$(wc -l < "$T/proj/.planning/resolutions.jsonl")" == "0" ]]; then
    pass "T7b: no resolutions.jsonl line written"
else
    fail "T7b: resolutions.jsonl was written"
fi
if ! grep -q 'escalation_resolved\|phase_aborted' "$T/proj/.planning/events.jsonl"; then
    pass "T7c: no gate-release event written"
else
    fail "T7c: gate-release event was written"
fi
cleanup

# --- T8: parent + bot_id ignored, cursor still advances ---
echo "T8: parent + bot ignored, cursor advances"
fresh_env
esc
# Fixture: parent + bot messages only
jq -n '
{ "1000000000.000001": {
    ok: true,
    messages: [
        { ts: "1000000000.000001", type: "message", subtype: "root", text: "root" },
        { ts: "1000000000.000009", bot_id: "B123", user: "USLACKBOT", text: "▶️ resuming" }
    ]
}}' > "$SLACK_REPLIES_MOCK"
bash "$POLL" >/dev/null 2>&1
if [[ ! -f "$T/proj/.planning/resolutions.jsonl" ]] || [[ "$(wc -l < "$T/proj/.planning/resolutions.jsonl")" == "0" ]]; then
    pass "T8a: no actions taken"
else
    fail "T8a: actions were taken"
fi
CURSOR="$(jq -r '."projA".last_ts' "$RESOLUTIONS_STATE_FILE")"
if [[ "$CURSOR" == "1000000000.000009" ]]; then
    pass "T8b: cursor advanced to max seen ts"
else
    fail "T8b: cursor=$CURSOR (expected 1000000000.000009)"
fi
cleanup

# --- T9: G6 checkpoint gate on pm-iterate directly (hermetic) ---
echo "T9: G6 checkpoint gate"
fresh_env
: > "$T/mock.txt"
# checkpoint latest → tick prints SKIP
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, event:"checkpoint", data:{phase:"p1"}}' >> "$T/proj/.planning/events.jsonl"
export PM_ITERATE_MOCK="$T/mock.txt"
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: checkpoint-awaiting-human'; then
    pass "T9a: checkpoint gate closes tick"
else
    fail "T9a: expected SKIP: checkpoint-awaiting-human (rc=$RC, out=$OUT)"
fi
# --trigger resolution bypasses
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger resolution 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T9b: --trigger resolution bypasses G6"
else
    fail "T9b: expected RAN (rc=$RC, out=$OUT)"
fi
# checkpoint_acknowledged reopens
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, event:"checkpoint_acknowledged", data:{phase:"p1"}}' >> "$T/proj/.planning/events.jsonl"
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T9c: checkpoint_acknowledged reopens gate"
else
    fail "T9c: expected RAN after acknowledged (rc=$RC, out=$OUT)"
fi
# phase_queued-after ALSO opens (backward-compat)
fresh_env
: > "$T/mock.txt"
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, event:"checkpoint", data:{phase:"p1"}}' >> "$T/proj/.planning/events.jsonl"
sleep 1
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, event:"phase_queued", data:{phase:"p1"}}' >> "$T/proj/.planning/events.jsonl"
export PM_ITERATE_MOCK="$T/mock.txt"
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T9d: phase_queued after checkpoint reopens gate (backward-compat)"
else
    fail "T9d: expected RAN (rc=$RC, out=$OUT)"
fi
cleanup

# --- T10: checkpoint-gated + continue → checkpoint_acknowledged event ---
echo "T10: checkpoint-gated + continue → checkpoint_acknowledged"
fresh_env
cp_event
reply_only "U_HUMAN" "continue"
bash "$POLL" >/dev/null 2>&1
if grep -q '"event":"checkpoint_acknowledged"' "$T/proj/.planning/events.jsonl"; then
    pass "T10a: checkpoint_acknowledged event appended"
else
    fail "T10a: checkpoint_acknowledged event missing"
fi
if grep -q -- '--trigger resolution' "$T/iterate-calls.log"; then
    pass "T10b: pm-iterate invoked"
else
    fail "T10b: pm-iterate not invoked"
fi
cleanup

# --- T11: daemon wiring ---
echo "T11: daemon wiring"
fresh_env
# Recorder script
cat > "$T/recorder.sh" <<'REC'
#!/usr/bin/env bash
echo "$@" > "${T}/recorder-ran.txt"
REC
chmod +x "$T/recorder.sh"
PM_RESOLUTIONS_BIN="$T/recorder.sh" node "$ORCH_DIR/services/pm-daemon.js" --once >/dev/null 2>&1
if [[ -f "$T/recorder-ran.txt" ]]; then
    pass "T11a: PM_RESOLUTIONS_BIN executed once"
else
    fail "T11a: recorder did not run"
fi
# Missing bin → no error
if PM_RESOLUTIONS_BIN="$T/does-not-exist" node "$ORCH_DIR/services/pm-daemon.js" --once >/dev/null 2>&1; then
    pass "T11b: --once completes clean with missing bin"
else
    fail "T11b: --once errored with missing bin"
fi
cleanup

# --- T12: token never leaked ---
echo "T12: token never leaked"
fresh_env
esc
reply_only "U_HUMAN" "continue"
export SLACK_ENV_FILE="$T/state/slack.env"
printf 'SLACK_BOT_TOKEN=xoxb-TESTSECRET789\nSLACK_CHANNEL=C0TEST\n' > "$SLACK_ENV_FILE"
OUT="$(bash "$POLL" 2>&1 || true)"
if ! grep -q 'TESTSECRET789' <<<"$OUT"; then
    pass "T12: token string absent from all poller output"
else
    fail "T12: TESTSECRET789 leaked"
fi
cleanup

# --- Regressions ---
echo "Regressions: r1-01/r1-02/r1-03/r2-04"
if bash "$ORCH_DIR/.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh" 2>&1 | tail -1 | grep -q "11 passed, 0 failed"; then
    pass "R1-01 still 11/11"
else
    fail "R1-01 regression"
fi
if bash "$ORCH_DIR/.planning/phases/r1-02-pm-iterate/smoke-tests.sh" 2>&1 | tail -1 | grep -q "16 passed, 0 failed"; then
    pass "R1-02 still 16/16"
else
    fail "R1-02 regression"
fi
if bash "$ORCH_DIR/.planning/phases/r1-03-pm-daemon/smoke-tests.sh" 2>&1 | tail -1 | grep -q "19 passed, 0 failed"; then
    pass "R1-03 still 19/19"
else
    fail "R1-03 regression"
fi
if bash "$ORCH_DIR/.planning/phases/r2-04-slack-notify/smoke-tests.sh" 2>&1 | tail -1 | grep -q "18 passed, 0 failed"; then
    pass "R2-04 still 18/18"
else
    fail "R2-04 regression"
fi

echo ""
echo "=================================="
echo "Smoke test summary: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:"
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
exit 0
