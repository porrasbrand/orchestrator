#!/usr/bin/env bash
# integration-test-pm.sh — r1r2-06 end-to-end chain tests for the Resident PM.
# Hermetic: no real network, no real claude, no real Slack.
# Every assertion spans ≥2 components (per-component behaviour is covered by
# the 5 phase suites; this suite exercises the SEAMS).
#
# Scenarios:
#   S1 — response → grace-claim → REAL pm-iterate → archived; non-ledgered untouched
#   S2 — escalation → notify → G5 SKIP → Slack continue → resolved + reopen
#   S3 — checkpoint → G6 SKIP → Slack continue → checkpoint_acknowledged + reopen
#   S4 — Slack abort → blocked + phase_aborted + notify; daemon then ignores project
#   S5 — kill switches (paused / interrupt.json) stop the loop; both reversible

set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()

pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

T="$(mktemp -d)"
cleanup() { [[ -d "$T" ]] && rm -rf "$T"; }
trap cleanup EXIT

# --- shared hermetic harness ---
export ORCH_STATE_DIR="$T/state"
export SUPER_AGENT_DIR="$T/super-agent"
export SLACK_MOCK="$T/slack-out.jsonl"
export SLACK_REPLIES_MOCK="$T/replies.json"
export SLACK_THREADS_FILE="$ORCH_STATE_DIR/slack-threads.json"
export RESOLUTIONS_STATE_FILE="$ORCH_STATE_DIR/slack-resolutions-state.json"
export PM_ITERATE_MOCK="$T/mock-transcript.txt"
# NOTE: PM_GRACE_PERIOD=0 is now honored post-fix (F1 fixed in phase 05: numEnv()
# takes a per-knob floor, min=0 for grace). This suite deliberately keeps grace=1 +
# a short sleep in S1 to exercise a fully-elapsed grace window (a non-zero wait), not
# because 0 is rejected.
export PM_GRACE_PERIOD=1
export PM_MAX_ATTEMPTS=2
export PATH="$T/bin:$PATH"

mkdir -p "$ORCH_STATE_DIR" "$SUPER_AGENT_DIR/tasks/responses/new" "$T/bin"

# Mock add-task.sh on PATH (used by queue-phase.sh if scenarios needed it; here
# it's optional but keeps the fixture faithful).
cat > "$T/bin/add-task.sh" <<'MOCK_ADDTASK'
#!/usr/bin/env bash
set -euo pipefail
ID="$(printf '%018d' "$(date +%s%N)")"; ID="${ID: -18}"
echo "ID: $ID"
echo "Task queued: $ID"
MOCK_ADDTASK
chmod +x "$T/bin/add-task.sh"

# Canned pm-iterate mock transcript.
echo "[mock transcript] PM iteration ran" > "$PM_ITERATE_MOCK"

# Empty slack outbound + inbound fixtures.
: > "$SLACK_MOCK"
echo '{}' > "$SLACK_REPLIES_MOCK"

# Recorder — used by scenarios that want to see if pm-iterate was invoked.
RECORDER="$T/recorder.sh"
cat > "$RECORDER" <<REC
#!/usr/bin/env bash
echo "\$@" >> "$T/recorder.log"
echo "RAN: exit=0 transcript=/dev/null"
exit 0
REC
chmod +x "$RECORDER"

# Reset the fake project to a known-good state.
reset_proj() {
    rm -rf "$T/proj"
    mkdir -p "$T/proj/.planning"
    cat > "$T/proj/.planning/status.json" <<JSON
{
  "project": "projA",
  "current_phase": "p1",
  "phases": { "p1": { "status": "verifying" } }
}
JSON
    : > "$T/proj/.planning/events.jsonl"
    rm -f "$T/proj/.planning/resolutions.jsonl" "$T/proj/.planning/notifications.md" \
          "$T/proj/.planning/latest-notification.json" "$T/proj/.planning/interrupt.json"
    # Registry — always active projA pointing at $T/proj.
    jq -n --arg lp "$T/proj" '[
        {name:"projA", local_path:$lp, worker:"hetzner", remote_path:"", active:true, registered_at:"2026-07-02T00:00:00Z"}
    ]' > "$ORCH_STATE_DIR/active-projects.json"
    # Threads file with an entry for projA
    jq -n '{ "projA": { "thread_ts": "1000000000.000001", "channel": "C0TEST" } }' > "$SLACK_THREADS_FILE"
    # Empty ledger, empty responses, empty cursor.
    : > "$ORCH_STATE_DIR/dispatch-ledger.jsonl"
    rm -rf "$SUPER_AGENT_DIR/tasks/responses"/{new,claimed,archive,failed}
    mkdir -p "$SUPER_AGENT_DIR/tasks/responses/new"
    rm -f "$RESOLUTIONS_STATE_FILE" "$ORCH_STATE_DIR/paused" "$T/recorder.log"
    : > "$SLACK_MOCK"
    echo '{}' > "$SLACK_REPLIES_MOCK"
    # Clear per-project pm-iterate ledger too — we treat pm-iterate as a fresh runner.
    rm -f "$ORCH_STATE_DIR/iterations.jsonl" "$ORCH_STATE_DIR/daemon-state.json"
    rm -rf "$ORCH_STATE_DIR/runs" "$ORCH_STATE_DIR/locks"
}

seed_ledger() {
    # $1 = task_id, $2 = phase
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg id "$1" --arg pp "$T/proj" --arg phase "$2" \
        '{ts:$ts, task_id:$id, project:"projA", project_path:$pp, phase:$phase, worker:"hetzner"}' \
        >> "$ORCH_STATE_DIR/dispatch-ledger.jsonl"
}

append_event() {
    # $1 = event name, $2 = data JSON string
    jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg name "$1" --argjson data "$2" \
        '{ts:$ts, event:$name, data:$data}' \
        >> "$T/proj/.planning/events.jsonl"
}

reply_only() {
    # $1 = user, $2 = text (single reply after root)
    jq -n --arg user "$1" --arg text "$2" '
        { "1000000000.000001": {
            ok: true,
            messages: [
                { ts: "1000000000.000001", type: "message", subtype: "root", text: "root" },
                { ts: "1000000000.000010", user: $user, text: $text }
            ]
        }}
    ' > "$SLACK_REPLIES_MOCK"
}

# ============================================================
# S1 — response → grace-claim → iterate → archive
# Assertions cross: pm-daemon.js × pm-iterate.sh × ledger × archive layout
# ============================================================
echo "S1: response → grace-claim → REAL pm-iterate → archived"
reset_proj
seed_ledger "111111111111111111" "p1"
echo '{"id":111111111111111111,"response":"done"}' > "$SUPER_AGENT_DIR/tasks/responses/new/111111111111111111.json"
echo '{"id":999999999999999999,"response":"noise"}' > "$SUPER_AGENT_DIR/tasks/responses/new/999999999999999999.json"
# Force the current phase to a NON-actionable status so the tick cycle skips it
# (isolate the scan-cycle assertion from the tick cycle).
cat > "$T/proj/.planning/status.json" <<'JSON'
{
  "project": "projA",
  "current_phase": "p1",
  "phases": { "p1": { "status": "complete" } }
}
JSON
# grace=1s + brief sleep so mtime is fully outside the window at scan time.
sleep 2
# NOTE: use the REAL pm-iterate via default PM_ITERATE_BIN. PM_ITERATE_MOCK is set,
# so pm-iterate does NOT invoke real claude — it copies the mock transcript.
node "$ORCH_DIR/services/pm-daemon.js" --once >/dev/null 2>&1
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/archive/111111111111111111.json" ]]; then
    pass "S1.1: ledgered response archived after --once"
else
    fail "S1.1: ledgered response not archived"
fi
if [[ -f "$SUPER_AGENT_DIR/tasks/responses/new/999999999999999999.json" ]] \
    && [[ ! -f "$SUPER_AGENT_DIR/tasks/responses/claimed/999999999999999999.json" ]]; then
    pass "S1.2: non-ledger response untouched"
else
    fail "S1.2: non-ledger response was touched"
fi
if [[ -f "$ORCH_STATE_DIR/iterations.jsonl" ]] \
    && grep -q '"trigger":"response"' "$ORCH_STATE_DIR/iterations.jsonl" \
    && grep -q '"project":"projA"' "$ORCH_STATE_DIR/iterations.jsonl"; then
    pass "S1.3: iterations.jsonl records the response iteration"
else
    fail "S1.3: iterations.jsonl missing/wrong: $(cat "$ORCH_STATE_DIR/iterations.jsonl" 2>&1 | head -3)"
fi
if [[ -d "$ORCH_STATE_DIR/runs/projA" ]] && ls "$ORCH_STATE_DIR/runs/projA"/*-transcript.log >/dev/null 2>&1; then
    pass "S1.4: real pm-iterate wrote transcript log"
else
    fail "S1.4: no transcript log under runs/projA"
fi

# ============================================================
# S2 — escalation → notify → G5 SKIP → Slack continue → resolved + reopen
# ============================================================
echo "S2: escalation → notify → G5 SKIP → continue → G5 reopened"
reset_proj
# Escalation event
append_event "ai_escalation_recommended" '{"phase":"p1"}'
# notify.sh (uses r2-04 hook via SLACK_MOCK convention)
"$ORCH_DIR/scripts/notify.sh" ai_escalation_recommended "$T/proj" \
    --phase p1 --detail "low confidence" >/dev/null 2>&1
if grep -q "AI escalation recommended" "$T/proj/.planning/notifications.md" 2>/dev/null; then
    pass "S2.1: notify.sh wrote AI-escalation heading"
else
    fail "S2.1: notifications.md missing escalation heading"
fi
if tail -1 "$SLACK_MOCK" | jq -e '.payload.text | contains("🚨")' >/dev/null 2>&1; then
    pass "S2.2: 🚨 posted to SLACK_MOCK (r2-04 hook end-to-end)"
else
    fail "S2.2: 🚨 not in SLACK_MOCK"
fi
# pm-iterate --trigger tick should SKIP: escalated-awaiting-human
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: escalated-awaiting-human'; then
    pass "S2.3: pm-iterate G5 gate closed by escalation event"
else
    fail "S2.3: expected G5 SKIP (rc=$RC out=$OUT)"
fi
# Fixture the human "continue" reply
reply_only "U_HUMAN" "continue"
# Run poller with PM_ITERATE_BIN = recorder so we can prove it fired.
PM_ITERATE_BIN="$RECORDER" bash "$ORCH_DIR/scripts/slack-poll-resolutions.sh" >/dev/null 2>&1
if grep -q '"event":"escalation_resolved"' "$T/proj/.planning/events.jsonl"; then
    pass "S2.4: escalation_resolved event appended"
else
    fail "S2.4: escalation_resolved missing"
fi
if [[ -f "$T/proj/.planning/resolutions.jsonl" ]] && \
    tail -1 "$T/proj/.planning/resolutions.jsonl" | jq -e '.kind=="continue" and .source=="slack"' >/dev/null; then
    pass "S2.5: resolutions.jsonl continue line written"
else
    fail "S2.5: resolutions line wrong"
fi
if tail -1 "$SLACK_MOCK" | jq -e '.payload.thread_ts=="1000000000.000001" and (.payload.text|contains("▶️"))' >/dev/null 2>&1; then
    pass "S2.6: ▶️ ACK posted threaded"
else
    fail "S2.6: ▶️ ACK missing"
fi
if [[ -f "$T/recorder.log" ]] && grep -q -- '--trigger resolution' "$T/recorder.log"; then
    pass "S2.7: pm-iterate recorder invoked with --trigger resolution"
else
    fail "S2.7: recorder not invoked"
fi
# Now a real tick should proceed past G5 (gate reopened).
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "S2.8: G5 reopened — subsequent tick runs (RAN:)"
else
    fail "S2.8: G5 not reopened (rc=$RC out=$OUT)"
fi

# ============================================================
# S3 — checkpoint → G6 pause → acknowledge → proceed
# ============================================================
echo "S3: checkpoint → G6 SKIP → continue → checkpoint_acknowledged → G6 reopened"
reset_proj
append_event "checkpoint" '{"phase":"p1"}'
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: checkpoint-awaiting-human'; then
    pass "S3.1: pm-iterate G6 gate closed by checkpoint event"
else
    fail "S3.1: expected G6 SKIP (rc=$RC out=$OUT)"
fi
reply_only "U_HUMAN" "continue"
PM_ITERATE_BIN="$RECORDER" bash "$ORCH_DIR/scripts/slack-poll-resolutions.sh" >/dev/null 2>&1
if grep -q '"event":"checkpoint_acknowledged"' "$T/proj/.planning/events.jsonl"; then
    pass "S3.2: checkpoint_acknowledged event appended (NOT escalation_resolved)"
else
    fail "S3.2: checkpoint_acknowledged missing"
fi
if ! grep -q '"event":"escalation_resolved"' "$T/proj/.planning/events.jsonl"; then
    pass "S3.3: escalation_resolved NOT appended (checkpoint-only path)"
else
    fail "S3.3: escalation_resolved leaked into checkpoint path"
fi
if tail -1 "$SLACK_MOCK" | jq -e '.payload.text | contains("▶️")' >/dev/null 2>&1; then
    pass "S3.4: ▶️ ACK posted"
else
    fail "S3.4: ACK missing"
fi
if [[ -f "$T/recorder.log" ]] && grep -q -- '--trigger resolution' "$T/recorder.log"; then
    pass "S3.5: recorder invoked with --trigger resolution"
else
    fail "S3.5: recorder not invoked"
fi
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" --trigger tick 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "S3.6: G6 reopened — subsequent tick runs (RAN:)"
else
    fail "S3.6: G6 not reopened (rc=$RC out=$OUT)"
fi

# ============================================================
# S4 — abort → blocked → daemon subsequently ignores project
# ============================================================
echo "S4: abort → blocked + phase_aborted + notify; daemon then ignores"
reset_proj
append_event "ai_escalation_recommended" '{"phase":"p1"}'
reply_only "U_HUMAN" "abort"
PM_ITERATE_BIN="$RECORDER" bash "$ORCH_DIR/scripts/slack-poll-resolutions.sh" >/dev/null 2>&1
if jq -e '.phases.p1.status=="blocked" and .blocked==true and (.blocked_reason|contains("U_HUMAN"))' "$T/proj/.planning/status.json" >/dev/null; then
    pass "S4.1: status.json blocked with U_HUMAN in reason"
else
    fail "S4.1: status.json not blocked"
fi
if grep -q '"event":"phase_aborted"' "$T/proj/.planning/events.jsonl"; then
    pass "S4.2: phase_aborted event appended"
else
    fail "S4.2: phase_aborted missing"
fi
if grep -q 'Phase aborted' "$T/proj/.planning/notifications.md" 2>/dev/null; then
    pass "S4.3: notifications.md gained 'Phase aborted'"
else
    fail "S4.3: notifications.md missing Phase aborted"
fi
if [[ ! -f "$T/recorder.log" ]] || ! grep -q . "$T/recorder.log"; then
    pass "S4.4: recorder NOT invoked on abort"
else
    fail "S4.4: recorder was invoked"
fi
# Now run pm-daemon --once tick and confirm it does NOT spawn pm-iterate for blocked project.
# Prep: replace PM_ITERATE_BIN with a recorder to see if daemon calls anything.
: > "$T/recorder.log"
PM_ITERATE_BIN="$RECORDER" node "$ORCH_DIR/services/pm-daemon.js" --once >/dev/null 2>&1
# The blocked project has status "blocked" — tick cycle should skip it.
if ! grep -q "$T/proj" "$T/recorder.log" 2>/dev/null; then
    pass "S4.5: daemon --once tick did NOT spawn pm-iterate for blocked project"
else
    fail "S4.5: daemon spawned pm-iterate for blocked project"
fi

# ============================================================
# S5 — kill switches (paused, interrupt.json), reversible
# ============================================================
echo "S5: kill switches (paused / interrupt.json), reversible"
reset_proj
# a) global paused
touch "$ORCH_STATE_DIR/paused"
: > "$T/recorder.log"
PM_ITERATE_BIN="$RECORDER" node "$ORCH_DIR/services/pm-daemon.js" --once >/dev/null 2>&1
if [[ ! -s "$T/recorder.log" ]]; then
    pass "S5.1: paused → daemon spawns nothing"
else
    fail "S5.1: daemon spawned despite paused"
fi
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: paused'; then
    pass "S5.2: pm-iterate SKIP: paused (kill switch honored)"
else
    fail "S5.2: expected SKIP: paused (rc=$RC out=$OUT)"
fi
# b) remove paused, create interrupt.json
rm -f "$ORCH_STATE_DIR/paused"
echo '{}' > "$T/proj/.planning/interrupt.json"
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^SKIP: interrupted'; then
    pass "S5.3: interrupt.json → SKIP: interrupted"
else
    fail "S5.3: expected SKIP: interrupted (rc=$RC out=$OUT)"
fi
# c) reversibility: remove interrupt, iterate proceeds
rm -f "$T/proj/.planning/interrupt.json"
OUT="$("$ORCH_DIR/scripts/pm-iterate.sh" "$T/proj" 2>&1)" && RC=0 || RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q '^RAN:'; then
    pass "S5.4: kill switches reversible — iterate now proceeds"
else
    fail "S5.4: expected RAN after clearing switches (rc=$RC out=$OUT)"
fi

# --- Summary ---
echo ""
echo "=================================="
echo "integration-test-pm: PASS=$PASS FAIL=$FAIL scenarios=5"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed assertions:"
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
exit 0
