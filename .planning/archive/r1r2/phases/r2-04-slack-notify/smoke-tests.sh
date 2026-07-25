#!/usr/bin/env bash
# smoke-tests.sh — hermetic tests for r2-04 Slack outbound hook.
# NO real Slack calls; SLACK_MOCK sink only. NO tokens leave the test.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

note() {
    # note <event> <phase> <detail> <project> — emits the JSON stdin format.
    jq -n --arg e "$1" --arg ph "$2" --arg d "$3" --arg p "$4" \
        '{timestamp:"2026-07-02T15:00:00Z",event:$e,phase:$ph,detail:$d,project:$p}'
}

fresh_env() {
    T="$(mktemp -d)"
    export ORCH_STATE_DIR="$T/state"
    export SLACK_MOCK="$T/calls.jsonl"
    unset SLACK_BOT_TOKEN SLACK_CHANNEL SLACK_ENV_FILE SLACK_THREADS_FILE SLACK_MOCK_FAIL || true
    mkdir -p "$ORCH_STATE_DIR" "$T/proj/.planning"
    : > "$SLACK_MOCK"
    P="$T/proj"
}

cleanup() { [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

cd "$ORCH_DIR"
HOOK="config/notify-hook.sh"

# --- Test 1: graceful no-op without config ---
echo "Test 1: graceful no-op without config"
fresh_env
env -u SLACK_MOCK ORCH_STATE_DIR="$T/state" bash "$HOOK" <<<"$(note phase_complete p1 ok projA)" 2>/dev/null
RC=$?
if [[ "$RC" == "0" ]] && [[ ! -f "$ORCH_STATE_DIR/slack-threads.json" ]]; then
    pass "T1: hook exit 0, no threads file"
else
    fail "T1: rc=$RC or threads file created"
fi
cleanup

# --- Test 2: first notification → root + threaded reply ---
echo "Test 2: first notification → root + reply"
fresh_env
note phase_complete r2-04 "16/16 passed" projA | bash "$HOOK" 2>/dev/null
LC="$(wc -l < "$SLACK_MOCK")"
if [[ "$LC" == "2" ]]; then
    pass "T2a: exactly 2 mock calls"
else
    fail "T2a: expected 2 lines, got $LC"
fi
if jq -es '.[0].payload | (has("thread_ts") | not)' "$SLACK_MOCK" >/dev/null 2>&1; then
    pass "T2b: line 1 (root) has NO thread_ts"
else
    fail "T2b: line 1 has thread_ts (should be root)"
fi
if jq -es '.[1].payload.thread_ts == "1000000000.000001"' "$SLACK_MOCK" >/dev/null 2>&1; then
    pass "T2c: line 2 threaded under synthesized ts"
else
    fail "T2c: line 2 thread_ts mismatch: $(jq -es '.[1].payload.thread_ts' "$SLACK_MOCK")"
fi
if jq -e '."projA".thread_ts' "$ORCH_STATE_DIR/slack-threads.json" >/dev/null; then
    pass "T2d: projA entry in slack-threads.json"
else
    fail "T2d: projA missing from slack-threads.json"
fi
# --- Test 3: second notification for same project → 1 new call, same thread ---
echo "Test 3: second notification → 1 new call, same thread"
note verification_failed r2-04 "2 failed" projA | bash "$HOOK" 2>/dev/null
LC="$(wc -l < "$SLACK_MOCK")"
LINE2_TS="$(jq -es '.[1].payload.thread_ts' "$SLACK_MOCK")"
LINE3_TS="$(jq -es '.[2].payload.thread_ts' "$SLACK_MOCK")"
if [[ "$LC" == "3" ]] && [[ "$LINE2_TS" == "$LINE3_TS" ]]; then
    pass "T3: line 3 threaded under same thread_ts as line 2"
else
    fail "T3: lc=$LC line2=$LINE2_TS line3=$LINE3_TS"
fi
cleanup

# --- Test 4: second project → separate thread ---
echo "Test 4: second project → separate thread"
fresh_env
note phase_complete r2-04 "one" projA | bash "$HOOK" 2>/dev/null
note phase_complete x1 done projB | bash "$HOOK" 2>/dev/null
LC="$(wc -l < "$SLACK_MOCK")"
A_TS="$(jq -r '."projA".thread_ts' "$ORCH_STATE_DIR/slack-threads.json")"
B_TS="$(jq -r '."projB".thread_ts' "$ORCH_STATE_DIR/slack-threads.json")"
if [[ "$LC" == "4" ]] && [[ -n "$A_TS" ]] && [[ -n "$B_TS" ]] && [[ "$A_TS" != "$B_TS" ]]; then
    pass "T4: both projects present, distinct thread_ts"
else
    fail "T4: lc=$LC A=$A_TS B=$B_TS"
fi
cleanup

# --- Test 5: escalation broadcast + emoji ---
echo "Test 5: escalation broadcast + emoji"
fresh_env
note ai_escalation_recommended r2-04 "both low confidence" projA | bash "$HOOK" 2>/dev/null
if tail -1 "$SLACK_MOCK" | jq -e '.payload.reply_broadcast == true and (.payload.text | contains("🚨"))' >/dev/null; then
    pass "T5a: 🚨 with reply_broadcast:true"
else
    fail "T5a: escalation reply_broadcast/text wrong"
fi
# phase_complete must NOT have reply_broadcast
note phase_complete r2-04 "ok" projA | bash "$HOOK" 2>/dev/null
if tail -1 "$SLACK_MOCK" | jq -e '.payload | has("reply_broadcast") | not' >/dev/null; then
    pass "T5b: phase_complete has no reply_broadcast"
else
    fail "T5b: phase_complete has reply_broadcast"
fi
cleanup

# --- Test 6: corrupt threads file recovered ---
echo "Test 6: corrupt threads file recovered"
fresh_env
echo 'garbage{{{' > "$ORCH_STATE_DIR/slack-threads.json"
note phase_complete p9 ok projC | bash "$HOOK" 2>/dev/null
RC=$?
if [[ "$RC" == "0" ]] && jq -e '."projC".thread_ts' "$ORCH_STATE_DIR/slack-threads.json" >/dev/null; then
    pass "T6: corrupt threads file rebuilt, projC entry present"
else
    fail "T6: rc=$RC or threads not rebuilt"
fi
cleanup

# --- Test 7: mock failure tolerated by notify.sh ---
echo "Test 7: SLACK_MOCK_FAIL tolerated by notify.sh"
fresh_env
export SLACK_MOCK_FAIL=1
"$ORCH_DIR/scripts/notify.sh" phase_failed "$P" --phase p1 --detail boom 2>/dev/null
RC=$?
if [[ "$RC" == "0" ]] && [[ -f "$P/.planning/notifications.md" ]] && [[ -f "$P/.planning/latest-notification.json" ]]; then
    pass "T7: notify.sh exit 0; notifications.md + latest-notification.json written"
else
    fail "T7: rc=$RC or notification files missing"
fi
unset SLACK_MOCK_FAIL
cleanup

# --- Test 8: checkpoint end-to-end through notify.sh ---
echo "Test 8: checkpoint end-to-end"
fresh_env
"$ORCH_DIR/scripts/notify.sh" checkpoint "$P" --phase r1-03-pm-daemon --detail "3/6 complete" 2>/dev/null
RC=$?
if [[ "$RC" == "0" ]] && grep -q "Checkpoint" "$P/.planning/notifications.md"; then
    pass "T8a: Checkpoint heading in notifications.md"
else
    fail "T8a: rc=$RC or no Checkpoint heading"
fi
if tail -1 "$SLACK_MOCK" | jq -e '.payload.text | contains("🛑")' >/dev/null; then
    pass "T8b: 🛑 in mock payload"
else
    fail "T8b: 🛑 missing"
fi
cleanup

# --- Test 9: token never leaked ---
echo "Test 9: token never leaked in stdout/stderr"
fresh_env
printf 'SLACK_BOT_TOKEN=xoxb-TESTSECRET123\nSLACK_CHANNEL=C0TEST\n' > "$ORCH_STATE_DIR/slack.env"
OUT="$(note phase_complete p1 ok projA | bash "$HOOK" 2>&1)"
if ! grep -q 'TESTSECRET123' <<<"$OUT"; then
    pass "T9: token string absent from hook output"
else
    fail "T9: TESTSECRET123 leaked"
fi
cleanup

# --- Test 10: prior suites still green ---
echo "Test 10: prior suites still green"
bash -n "$ORCH_DIR/config/notify-hook.sh" >/dev/null && bash -n "$ORCH_DIR/scripts/notify.sh" >/dev/null
if [[ $? -eq 0 ]]; then
    pass "T10a: bash -n clean on hook + notify.sh"
else
    fail "T10a: bash -n errors"
fi
if bash "$ORCH_DIR/.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh" 2>&1 | tail -1 | grep -q "11 passed, 0 failed"; then
    pass "T10b: r1-01 still 11/11"
else
    fail "T10b: r1-01 regression"
fi
if bash "$ORCH_DIR/.planning/phases/r1-02-pm-iterate/smoke-tests.sh" 2>&1 | tail -1 | grep -q "16 passed, 0 failed"; then
    pass "T10c: r1-02 still 16/16"
else
    fail "T10c: r1-02 regression"
fi
if bash "$ORCH_DIR/.planning/phases/r1-03-pm-daemon/smoke-tests.sh" 2>&1 | tail -1 | grep -q "19 passed, 0 failed"; then
    pass "T10d: r1-03 still 19/19"
else
    fail "T10d: r1-03 regression"
fi

# --- Summary ---
echo ""
echo "=================================="
echo "Smoke test summary: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:"
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
exit 0
