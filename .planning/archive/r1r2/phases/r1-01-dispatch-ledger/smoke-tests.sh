#!/usr/bin/env bash
# smoke-tests.sh — hermetic tests for register-project.sh + queue-phase.sh.
# All state under mktemp dirs, cleaned via trap. Idempotent.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

fresh_env() {
    # Sets T, ORCH_STATE_DIR, SUPER_AGENT_DIR in the caller's shell.
    # Must be called as `fresh_env` (no command substitution) or the exports vanish.
    T="$(mktemp -d)"
    export ORCH_STATE_DIR="$T/state"
    export SUPER_AGENT_DIR="$T/sa"
    mkdir -p "$SUPER_AGENT_DIR/scripts" "$T/proj/.planning"
    echo '{"project":"demo-proj"}' > "$T/proj/.planning/status.json"
    cp "$ORCH_DIR/templates/test-fixtures/mock-add-task.sh" "$SUPER_AGENT_DIR/scripts/add-task.sh"
    cp "$ORCH_DIR/templates/test-fixtures/mock-add-task.sh" "$SUPER_AGENT_DIR/scripts/add-task-local.sh"
    chmod +x "$SUPER_AGENT_DIR/scripts/"*.sh
}

cleanup() { [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

cd "$ORCH_DIR"

# --- Test 1 ---
echo "Test 1: register + get round-trip"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
if ./scripts/register-project.sh get demo-proj | jq -e '.active == true and .worker == "hetzner"' >/dev/null; then
    pass "T1: register + get"
else
    fail "T1: register + get"
fi
cleanup

# --- Test 2 ---
echo "Test 2: idempotent re-add (still exactly 1 entry)"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
./scripts/register-project.sh add "$T/proj" >/dev/null
CNT="$(./scripts/register-project.sh list --json | jq 'length')"
if [[ "$CNT" == "1" ]]; then
    pass "T2: idempotent re-add"
else
    fail "T2: idempotent re-add (got count=$CNT)"
fi
cleanup

# --- Test 3 ---
echo "Test 3: successful dispatch writes ledger + event"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
./scripts/queue-phase.sh "$T/proj" 01-test "hello world task" >/dev/null 2>&1
if tail -1 "$ORCH_STATE_DIR/dispatch-ledger.jsonl" | jq -e '.project=="demo-proj" and .phase=="01-test" and (.task_id|type)=="string"' >/dev/null; then
    pass "T3a: ledger line valid"
else
    fail "T3a: ledger line invalid"
fi
if tail -1 "$T/proj/.planning/events.jsonl" | jq -e '.event=="phase_queued" and .data.task_id != null' >/dev/null; then
    pass "T3b: events.jsonl phase_queued event"
else
    fail "T3b: events.jsonl phase_queued event"
fi
cleanup

# --- Test 4 ---
echo "Test 4: ledger task_id matches the ID the dispatcher printed"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
OUT="$(./scripts/queue-phase.sh "$T/proj" 02-test "second task" 2>&1)"
PRINTED="$(echo "$OUT" | grep -oE 'ID: [0-9]+' | head -1 | awk '{print $2}')"
LEDGERED="$(tail -1 "$ORCH_STATE_DIR/dispatch-ledger.jsonl" | jq -r .task_id)"
if [[ -n "$PRINTED" && "$LEDGERED" == "$PRINTED" ]]; then
    pass "T4: ledger id == dispatcher id ($PRINTED)"
else
    fail "T4: mismatch (printed=$PRINTED, ledgered=$LEDGERED)"
fi
cleanup

# --- Test 5 ---
echo "Test 5: failed dispatch (exit 1) writes nothing"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
# Prime ledger with one line so we can measure delta safely.
./scripts/queue-phase.sh "$T/proj" 02-warmup "warmup" >/dev/null 2>&1
BEFORE="$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")"
if MOCK_ADDTASK_EXIT=1 ./scripts/queue-phase.sh "$T/proj" 03-test "will fail" >/dev/null 2>&1; then
    fail "T5a: queue-phase should have exited non-zero"
else
    pass "T5a: queue-phase exited non-zero on dispatcher exit=1"
fi
AFTER="$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")"
if [[ "$AFTER" == "$BEFORE" ]]; then
    pass "T5b: ledger unchanged on dispatcher exit=1"
else
    fail "T5b: ledger changed on dispatcher exit=1 (before=$BEFORE after=$AFTER)"
fi
cleanup

# --- Test 6 ---
echo "Test 6: local-fallback (Task saved locally) treated as failure"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
./scripts/queue-phase.sh "$T/proj" 02-warmup "warmup" >/dev/null 2>&1
BEFORE="$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")"
if MOCK_ADDTASK_FAIL=1 ./scripts/queue-phase.sh "$T/proj" 04-test "fallback" >/dev/null 2>&1; then
    fail "T6a: queue-phase should have exited non-zero on local-fallback"
else
    pass "T6a: queue-phase exited non-zero on local-fallback"
fi
AFTER="$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")"
if [[ "$AFTER" == "$BEFORE" ]]; then
    pass "T6b: ledger unchanged on local-fallback"
else
    fail "T6b: ledger changed on local-fallback (before=$BEFORE after=$AFTER)"
fi
cleanup

# --- Test 7 ---
echo "Test 7: deactivate flips flag"
fresh_env
./scripts/register-project.sh add "$T/proj" --worker hetzner >/dev/null
./scripts/register-project.sh deactivate demo-proj >/dev/null
if ./scripts/register-project.sh get demo-proj | jq -e '.active == false' >/dev/null; then
    pass "T7: deactivate flips active=false"
else
    fail "T7: deactivate did not flip active"
fi
cleanup

# --- Bonus: worker routing (--worker wsl2 invokes add-task-local.sh) ---
echo "Test 8: --worker wsl2 routing"
fresh_env
# Overwrite the local dispatcher with a marker mock that prints its identity.
cat > "$SUPER_AGENT_DIR/scripts/add-task-local.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
while [[ "${1:-}" == --* ]]; do shift 2; done
ID="$(printf '%018d' "$(date +%s%N)")"; ID="${ID: -18}"
echo "MOCK: local dispatcher"
echo "ID: $ID"
echo "Task queued: $ID"
MOCK
chmod +x "$SUPER_AGENT_DIR/scripts/add-task-local.sh"
OUT="$(./scripts/queue-phase.sh "$T/proj" 08-test --worker wsl2 "wsl2 task" 2>&1)"
if echo "$OUT" | grep -q "MOCK: local dispatcher" && tail -1 "$ORCH_STATE_DIR/dispatch-ledger.jsonl" | jq -e '.worker == "wsl2"' >/dev/null; then
    pass "T8: --worker wsl2 routes to add-task-local.sh"
else
    fail "T8: --worker wsl2 did not route to add-task-local.sh"
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
