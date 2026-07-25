#!/usr/bin/env bash
# smoke-tests.sh — hermetic tests for pm-daemon.js.
# Uses mock pm-iterate (never real claude). All state under mktemp -d.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

fresh_env() {
    # Sets T + all env for the caller shell.
    T="$(mktemp -d)"
    export ORCH_STATE_DIR="$T/state"
    export SUPER_AGENT_DIR="$T/sa"
    export PM_GRACE_PERIOD=1
    export PM_ITERATE_BIN="$ORCH_DIR/templates/test-fixtures/mock-pm-iterate.sh"
    export MOCK_PM_LOG="$T/mock.log"
    unset MOCK_PM_EXIT MOCK_PM_STDOUT MOCK_PM_SLEEP PM_MAX_ATTEMPTS PM_STALL_TIMEOUT || true
    mkdir -p "$ORCH_STATE_DIR" \
             "$SUPER_AGENT_DIR/tasks/responses/new" \
             "$T/projA/.planning" "$T/projB/.planning"
    : > "$MOCK_PM_LOG"
    echo '{"project":"projA","current_phase":"01-x"}' > "$T/projA/.planning/status.json"
    echo '{"project":"projB","current_phase":"01-y"}' > "$T/projB/.planning/status.json"
    : > "$T/projA/.planning/events.jsonl"
    : > "$T/projB/.planning/events.jsonl"

    # Register both projects
    "$ORCH_DIR/scripts/register-project.sh" add "$T/projA" >/dev/null
    "$ORCH_DIR/scripts/register-project.sh" add "$T/projB" >/dev/null

    # Seed ledger
    LEDGER="$ORCH_STATE_DIR/dispatch-ledger.jsonl"
    : > "$LEDGER"
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, task_id:"111", project:"projA", project_path:"'"$T/projA"'", phase:"01-x", worker:"hetzner"}' >> "$LEDGER"
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, task_id:"222", project:"projA", project_path:"'"$T/projA"'", phase:"01-x", worker:"hetzner"}' >> "$LEDGER"
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts, task_id:"333", project:"projB", project_path:"'"$T/projB"'", phase:"01-y", worker:"hetzner"}' >> "$LEDGER"
}

cleanup() { [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

cd "$ORCH_DIR"
DAEMON="node services/pm-daemon.js --once"

# --- Test 1: claim + iterate + archive ---
echo "Test 1: claim + iterate + archive"
fresh_env
echo '{"id":111,"response":"done"}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
sleep 2
$DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/archive/111.json" ]]; then
    pass "T1a: 111.json archived"
else
    fail "T1a: 111.json NOT archived"
fi
if grep -q '"--trigger","response"' "$MOCK_PM_LOG"; then
    pass "T1b: mock invoked with --trigger response"
else
    fail "T1b: mock not invoked with --trigger response"
fi
if grep -q "$T/projA" "$MOCK_PM_LOG"; then
    pass "T1c: mock invoked with projA path"
else
    fail "T1c: mock not invoked with projA path"
fi
cleanup

# --- Test 2: non-ledger response untouched ---
echo "Test 2: non-ledger response untouched"
fresh_env
echo '{}' > "$SUPER_AGENT_DIR/tasks/responses/new/999.json"
sleep 2
$DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/new/999.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/claimed/999.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/archive/999.json" ]]; then
    pass "T2: non-ledger 999.json left in new/"
else
    fail "T2: non-ledger 999.json was touched"
fi
if [[ ! -s "$MOCK_PM_LOG" ]]; then
    pass "T2: mock log empty"
else
    fail "T2: mock log not empty"
fi
cleanup

# --- Test 3: younger than grace untouched ---
echo "Test 3: younger than grace untouched"
fresh_env
export PM_GRACE_PERIOD=3600
echo '{"id":111}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
$DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/new/111.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/claimed/111.json" ]]; then
    pass "T3: fresh 111.json left in new/ (grace=3600)"
else
    fail "T3: fresh 111.json was claimed prematurely"
fi
cleanup

# --- Test 3b: deactivated project untouched ---
echo "Test 3b: deactivated project response untouched"
fresh_env
"$ORCH_DIR/scripts/register-project.sh" deactivate projA >/dev/null
echo '{"id":111}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
sleep 2
$DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/new/111.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/claimed/111.json" ]] \
    && [[ ! -s "$MOCK_PM_LOG" ]]; then
    pass "T3b: deactivated projA response left in new/"
else
    fail "T3b: deactivated projA response was touched"
fi
cleanup

# --- Test 4: retry then give-up ---
echo "Test 4: retry then give-up (PM_MAX_ATTEMPTS=2)"
fresh_env
export PM_MAX_ATTEMPTS=2
echo '{"id":222}' > "$SUPER_AGENT_DIR/tasks/responses/new/222.json"
sleep 2
MOCK_PM_EXIT=1 $DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/claimed/222.json" ]]; then
    pass "T4a: after attempt 1, 222.json still in claimed/"
else
    fail "T4a: 222.json missing after attempt 1"
fi
S1="$(jq -r '.claims["222"].attempts' "$ORCH_STATE_DIR/daemon-state.json" 2>/dev/null || echo missing)"
if [[ "$S1" == "1" ]]; then
    pass "T4b: attempts=1 in daemon-state.json"
else
    fail "T4b: expected attempts=1 got $S1"
fi
MOCK_PM_EXIT=1 $DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/failed/222.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/claimed/222.json" ]]; then
    pass "T4c: after attempt 2, 222.json moved to failed/"
else
    fail "T4c: 222.json not moved to failed/"
fi
if tail -1 "$T/projA/.planning/events.jsonl" | jq -e '.event=="pm_daemon_gave_up" and .data.task_id=="222" and .data.attempts==2' >/dev/null 2>&1; then
    pass "T4d: pm_daemon_gave_up event landed with task_id=222 attempts=2"
else
    fail "T4d: pm_daemon_gave_up event missing/wrong"
fi
cleanup

# --- Test 5: SKIP: leaves claim in place ---
echo "Test 5: SKIP stdout leaves claim in place"
fresh_env
echo '{"id":111}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
sleep 2
MOCK_PM_STDOUT='SKIP: rate-capped (6/6 in last hour)' $DAEMON >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/claimed/111.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/archive/111.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/failed/111.json" ]]; then
    pass "T5a: SKIP: leaves 111.json in claimed/"
else
    fail "T5a: SKIP: disposition wrong"
fi
if [[ ! -f "$ORCH_STATE_DIR/daemon-state.json" ]] \
    || [[ "$(jq -r '.claims["111"] // "absent"' "$ORCH_STATE_DIR/daemon-state.json" 2>/dev/null)" == "absent" ]]; then
    pass "T5b: no attempts recorded for SKIP"
else
    fail "T5b: attempts recorded for SKIP path"
fi
cleanup

# --- Test 6: tick actionability ---
echo "Test 6: tick actionability"
fresh_env
# projA: current phase specified → tick
echo '{"project":"projA","current_phase":"01-x","phases":{"01-x":{"status":"specified"}}}' > "$T/projA/.planning/status.json"
# projB: current phase queued, fresh phase_queued event → NOT tick
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo '{"project":"projB","current_phase":"01-y","phases":{"01-y":{"status":"queued"}}}' > "$T/projB/.planning/status.json"
echo "{\"ts\":\"$NOW\",\"event\":\"phase_queued\",\"data\":{\"phase\":\"01-y\",\"task_id\":\"333\"}}" > "$T/projB/.planning/events.jsonl"
export PM_STALL_TIMEOUT=14400
$DAEMON >/dev/null 2>&1
LOG1="$(cat "$MOCK_PM_LOG")"
POKED_A_TICK="$(echo "$LOG1" | grep -c '"--trigger","tick"' || true)"
POKED_A_PATH="$(echo "$LOG1" | grep -c "$T/projA" || true)"
POKED_B_PATH="$(echo "$LOG1" | grep -c "$T/projB" || true)"
if [[ "$POKED_A_TICK" -ge "1" && "$POKED_A_PATH" -ge "1" && "$POKED_B_PATH" == "0" ]]; then
    pass "T6a: only projA(specified) poked; projB(queued+fresh) not poked"
else
    fail "T6a: projA_ticks=$POKED_A_TICK projA_paths=$POKED_A_PATH projB_paths=$POKED_B_PATH"
fi
# Age projB's phase_queued event to 5h ago → tick fires
OLD_TS="$(date -u -d '5 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
echo "{\"ts\":\"$OLD_TS\",\"event\":\"phase_queued\",\"data\":{\"phase\":\"01-y\",\"task_id\":\"333\"}}" > "$T/projB/.planning/events.jsonl"
: > "$MOCK_PM_LOG"
$DAEMON >/dev/null 2>&1
POKED_B_PATH2="$(grep -c "$T/projB" "$MOCK_PM_LOG" || true)"
if [[ "$POKED_B_PATH2" -ge "1" ]]; then
    pass "T6b: projB(queued+stall) poked after aging event"
else
    fail "T6b: projB not poked despite stall"
fi
cleanup

# --- Test 7: paused kill switch ---
echo "Test 7: paused kill switch"
fresh_env
echo '{"project":"projA","current_phase":"01-x","phases":{"01-x":{"status":"specified"}}}' > "$T/projA/.planning/status.json"
touch "$ORCH_STATE_DIR/paused"
echo '{"id":111}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
sleep 2
OUT="$($DAEMON 2>&1)"
if echo "$OUT" | grep -q 'paused' \
    && [[ -f "$SUPER_AGENT_DIR/tasks/responses/new/111.json" ]] \
    && [[ ! -s "$MOCK_PM_LOG" ]]; then
    pass "T7: paused blocks scan + tick"
else
    fail "T7: paused did not block (out=$OUT)"
fi
cleanup

# --- Test 8: dry-run regression (r1-02 bugfix) ---
echo "Test 8: pm-iterate.sh --dry-run no longer appends event"
fresh_env
: > "$T/mock.txt"
B="$(wc -l < "$T/projA/.planning/events.jsonl")"
PM_ITERATE_MOCK="$T/mock.txt" "$ORCH_DIR/scripts/pm-iterate.sh" "$T/projA" --dry-run >/dev/null 2>&1
A="$(wc -l < "$T/projA/.planning/events.jsonl")"
if [[ "$A" == "$B" ]]; then
    pass "T8: events.jsonl line count unchanged after --dry-run (before=$B after=$A)"
else
    fail "T8: events.jsonl line count changed after --dry-run (before=$B after=$A)"
fi
cleanup

# --- Test 9: single-flight (two claims in one cycle → sequential) ---
echo "Test 9: single-flight enforcement (sequential pm-iterate calls)"
fresh_env
echo '{"id":111}' > "$SUPER_AGENT_DIR/tasks/responses/new/111.json"
echo '{"id":333}' > "$SUPER_AGENT_DIR/tasks/responses/new/333.json"
sleep 2
MOCK_PM_SLEEP=0.5 $DAEMON >/dev/null 2>&1
# Extract mock start ts + pid list; check that N invocations happened AND no two overlap.
N_INV="$(wc -l < "$MOCK_PM_LOG")"
# Read timestamps; ensure sequential by checking start-time monotonicity + gap >= sleep.
if [[ "$N_INV" -ge "2" ]]; then
    pass "T9a: two invocations recorded"
else
    fail "T9a: expected 2 invocations, got $N_INV"
fi
# Convert ISO ts to epoch seconds and verify monotonic increasing gap >= 0.4
OK_SEQ=1
prev=""
while IFS= read -r line; do
    ts="$(echo "$line" | jq -r .ts)"
    e="$(date -u -d "$ts" +%s.%3N 2>/dev/null || echo 0)"
    if [[ -n "$prev" ]]; then
        # awk numeric compare
        if awk -v a="$e" -v b="$prev" 'BEGIN{exit !(a >= b + 0.4)}'; then :; else OK_SEQ=0; fi
    fi
    prev="$e"
done < "$MOCK_PM_LOG"
if [[ "$OK_SEQ" == "1" ]]; then
    pass "T9b: pm-iterate invocations sequential (>= 0.4s apart)"
else
    fail "T9b: pm-iterate invocations overlapped or too close"
fi
cleanup

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
