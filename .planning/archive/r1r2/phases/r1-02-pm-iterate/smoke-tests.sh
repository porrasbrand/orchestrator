#!/usr/bin/env bash
# smoke-tests.sh — hermetic tests for pm-iterate.sh.
# NEVER invokes real claude; PM_ITERATE_MOCK is always set.
# All state under mktemp -d, cleaned via trap.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

fresh_env() {
    # Sets T, ORCH_STATE_DIR, PM_ITERATE_MOCK in the caller's shell.
    T="$(mktemp -d)"
    export ORCH_STATE_DIR="$T/state"
    export PM_ITERATE_MOCK="$T/mock.txt"
    unset PM_ITERATE_MOCK_EXIT PM_MAX_ITER_PER_HOUR || true
    mkdir -p "$ORCH_STATE_DIR" "$T/proj/.planning"
    echo '{"project":"demo","current_phase":"01-x"}' > "$T/proj/.planning/status.json"
    : > "$T/proj/.planning/events.jsonl"
    cp "$ORCH_DIR/templates/test-fixtures/mock-pm-transcript.txt" "$T/mock.txt"
}

cleanup() { [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

cd "$ORCH_DIR"

# --- Test 1: paused kill switch ---
echo "Test 1: paused kill switch"
fresh_env
touch "$ORCH_STATE_DIR/paused"
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: paused' && [[ ! -f "$ORCH_STATE_DIR/iterations.jsonl" ]]; then
    pass "T1: SKIP: paused; no transcript, no ledger"
else
    fail "T1: expected SKIP: paused (rc=$RC, out=$OUT)"
fi
cleanup

# --- Test 2: interrupt.json ---
echo "Test 2: interrupt.json"
fresh_env
echo '{}' > "$T/proj/.planning/interrupt.json"
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: interrupted' && [[ ! -f "$ORCH_STATE_DIR/iterations.jsonl" ]]; then
    pass "T2: SKIP: interrupted; no ledger"
else
    fail "T2: expected SKIP: interrupted (rc=$RC, out=$OUT)"
fi
cleanup

# --- Test 3: normal mock run ---
echo "Test 3: normal mock run"
fresh_env
OUT="$(./scripts/pm-iterate.sh "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" != "0" ]] || ! echo "$OUT" | grep -q '^RAN: exit=0'; then
    fail "T3a: expected RAN: exit=0 (rc=$RC, out=$OUT)"
else
    pass "T3a: RAN: exit=0"
fi
if tail -1 "$ORCH_STATE_DIR/iterations.jsonl" | jq -e '.project=="demo" and .trigger=="tick" and .exit_code==0' >/dev/null 2>&1; then
    pass "T3b: iterations.jsonl line valid"
else
    fail "T3b: iterations.jsonl line invalid"
fi
# transcript == mock content
TR="$(ls -t "$ORCH_STATE_DIR/runs/demo/"*-transcript.log | head -1)"
if diff -q "$TR" "$T/mock.txt" >/dev/null; then
    pass "T3c: transcript == mock content"
else
    fail "T3c: transcript != mock content"
fi
cleanup

# --- Test 4: response-file inlined into prompt ---
echo "Test 4: --response-file inlined into prompt"
fresh_env
echo '{"id":123,"response":"UNIQUE_MARKER_XYZ"}' > "$T/resp.json"
./scripts/pm-iterate.sh "$T/proj" --trigger response --response-file "$T/resp.json" >/dev/null 2>&1
PROMPT="$(ls -t "$ORCH_STATE_DIR/runs/demo/"*-prompt.md | head -1)"
if grep -q UNIQUE_MARKER_XYZ "$PROMPT"; then
    pass "T4a: prompt contains response-file JSON marker"
else
    fail "T4a: prompt missing UNIQUE_MARKER_XYZ"
fi
if grep -q "ONE state transition only" "$PROMPT" \
   && grep -q "queue-phase.sh" "$PROMPT" \
   && grep -q "trigger: response" "$PROMPT" \
   && grep -q "project name: demo" "$PROMPT"; then
    pass "T4b: prompt contains ONE-iter rule + queue-phase-only rule + name/trigger"
else
    fail "T4b: prompt missing required rule lines"
fi
cleanup

# --- Test 5: hourly cap ---
echo "Test 5: hourly cap"
fresh_env
export PM_MAX_ITER_PER_HOUR=2
./scripts/pm-iterate.sh "$T/proj" >/dev/null 2>&1
./scripts/pm-iterate.sh "$T/proj" >/dev/null 2>&1
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -qE '^SKIP: rate-capped'; then
    pass "T5a: 3rd call rate-capped after 2 iterations"
else
    fail "T5a: expected SKIP: rate-capped (out=$OUT)"
fi
# A 2h-old line for demo must NOT count.
OLD_TS="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
echo "{\"ts\":\"$OLD_TS\",\"project\":\"demo\",\"trigger\":\"tick\",\"exit_code\":0,\"duration_s\":0,\"prompt\":\"x\",\"transcript\":\"y\"}" >> "$ORCH_STATE_DIR/iterations.jsonl"
# Now delete the 2 recent lines: rebuild with only the old one.
grep -v "\"ts\":\"$(date -u +%Y-%m-%d)" "$ORCH_STATE_DIR/iterations.jsonl" > "$T/iter-clean.jsonl" || true
mv "$T/iter-clean.jsonl" "$ORCH_STATE_DIR/iterations.jsonl"
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T5b: old line does not count toward hourly cap"
else
    fail "T5b: expected RAN after purging recent lines (out=$OUT)"
fi
unset PM_MAX_ITER_PER_HOUR
cleanup

# --- Test 6: lock contention ---
echo "Test 6: lock contention (background slow mock)"
fresh_env
# Make the mock "slow" by wrapping it: PM_ITERATE_MOCK stays a small file, but we
# hold the lock by starting a background invocation with a mock that takes time.
# Simulate this via a wrapper mock file that we cp+sleep. Simplest: launch a
# background pm-iterate.sh + insert an artificial hold by racing.
# We'll use a background flock to hold the lock manually, then invoke pm-iterate.
LOCK_FILE="$ORCH_STATE_DIR/locks/demo.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
( flock -x 9; sleep 2 ) 9>"$LOCK_FILE" &
BGPID=$!
sleep 0.2
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
wait $BGPID
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: locked'; then
    pass "T6: SKIP: locked while another holder"
else
    fail "T6: expected SKIP: locked (rc=$RC, out=$OUT)"
fi
cleanup

# --- Test 7: escalation gate ---
echo "Test 7: escalation gate"
fresh_env
echo '{"ts":"2026-07-02T00:00:00Z","event":"ai_escalation_recommended","data":{"phase":"01-x"}}' >> "$T/proj/.planning/events.jsonl"
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: escalated-awaiting-human'; then
    pass "T7a: tick blocked by escalation"
else
    fail "T7a: expected SKIP: escalated-awaiting-human (rc=$RC, out=$OUT)"
fi
OUT="$(./scripts/pm-iterate.sh "$T/proj" --trigger resolution 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T7b: --trigger resolution bypasses escalation"
else
    fail "T7b: expected RAN with resolution trigger (rc=$RC, out=$OUT)"
fi
echo '{"ts":"2026-07-02T00:10:00Z","event":"escalation_resolved","data":{"phase":"01-x"}}' >> "$T/proj/.planning/events.jsonl"
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "T7c: escalation_resolved unblocks tick"
else
    fail "T7c: expected RAN after resolution event (rc=$RC, out=$OUT)"
fi
cleanup

# --- Test 8: mock exit propagation + dry-run ---
echo "Test 8: mock exit propagation + dry-run"
fresh_env
export PM_ITERATE_MOCK_EXIT=7
OUT="$(./scripts/pm-iterate.sh "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "7" ]] && echo "$OUT" | grep -q '^RAN: exit=7'; then
    pass "T8a: PM_ITERATE_MOCK_EXIT=7 propagates rc=7"
else
    fail "T8a: expected rc=7 with RAN: exit=7 (rc=$RC, out=$OUT)"
fi
if tail -1 "$ORCH_STATE_DIR/iterations.jsonl" | jq -e '.exit_code == 7' >/dev/null; then
    pass "T8b: ledger records exit_code:7"
else
    fail "T8b: ledger did not record exit_code:7"
fi
unset PM_ITERATE_MOCK_EXIT

# dry-run: writes prompt but no transcript and no iterations line for this run
BEFORE_LEDGER="$(wc -l < "$ORCH_STATE_DIR/iterations.jsonl")"
OUT="$(./scripts/pm-iterate.sh "$T/proj" --dry-run 2>&1)" && RC=0 || RC=$?
AFTER_LEDGER="$(wc -l < "$ORCH_STATE_DIR/iterations.jsonl")"
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^DRYRUN:' && [[ "$BEFORE_LEDGER" == "$AFTER_LEDGER" ]]; then
    pass "T8c: --dry-run prints DRYRUN, no ledger append"
else
    fail "T8c: dry-run expectations failed (rc=$RC, out=$OUT, before=$BEFORE_LEDGER after=$AFTER_LEDGER)"
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
