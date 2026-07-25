#!/usr/bin/env bash
# test-sf15.sh — hermetic proof of the SF-15 fix in scripts/queue-phase.sh.
# A daemon-style runtime env (SUPER_AGENT_DIR set to a dir with NO scripts/add-task.sh)
# must resolve dispatch to the resident local dispatcher, so a laptop-closed headless PM
# can still spec/queue; the hermetic-test injection (a mock add-task.sh) must still be
# honored. No real worker queue is touched — the local dispatcher's queue-db.js is stubbed.
set -uo pipefail
ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QP="$ORCH_DIR/scripts/queue-phase.sh"
FAIL=0
pass(){ echo "✅ $1"; }
fail(){ echo "❌ $1"; FAIL=1; }

setup_common(){
  T="$(mktemp -d)"
  export ORCH_STATE_DIR="$T/state"; mkdir -p "$ORCH_STATE_DIR"
  echo '[]' > "$ORCH_STATE_DIR/active-projects.json"
  PROJ="$T/proj"; mkdir -p "$PROJ/.planning"
  echo '{"project":"projSF15"}' > "$PROJ/.planning/status.json"
  : > "$PROJ/.planning/events.jsonl"
  export ORCH_FORCE_HOST=hetzner   # force the resident-host branch deterministically
}

# ---- SF15-a: no add-task.sh under SUPER_AGENT_DIR -> resident local dispatcher ----
setup_common
SA_A="$T/sa_noaddtask"; mkdir -p "$SA_A"          # deliberately NO scripts/add-task.sh
STUB="$T/slackapp"; mkdir -p "$STUB"              # stub the local dispatcher's queue backend
echo '{"type":"module"}' > "$STUB/package.json"
export SF15_MARKER="$T/localdispatch.called"
cat > "$STUB/queue-db.js" <<'EOF'
import fs from 'node:fs';
export function addMessage(queue, task){ fs.writeFileSync(process.env.SF15_MARKER, 'local '+queue+' '+task.id); }
export function getMessage(id, queue){ return { id }; }
EOF
OUT_A="$( SUPER_AGENT_DIR="$SA_A" \
          ORCH_HETZNER_SLACK_APP="$STUB" \
          ORCH_HETZNER_QUEUE_DB="$T/fake-queue.db" \
          bash "$QP" "$PROJ" "phaseX" --worker hetzner "hello task" 2>&1 )"
RC_A=$?
if [ "$RC_A" = "0" ] && [ -f "$SF15_MARKER" ] && ! printf '%s' "$OUT_A" | grep -q 'add-task.sh'; then
  pass "SF15-a: daemon-env (no add-task.sh) resolved to resident local dispatcher, not add-task.sh"
else
  fail "SF15-a: rc=$RC_A marker=$([ -f "$SF15_MARKER" ] && echo yes || echo no); out: $(printf '%s' "$OUT_A" | tail -3 | tr '\n' ' ')"
fi
rm -rf "$T"

# ---- SF15-b: mock add-task.sh present -> injection preserved ----
setup_common
SA_B="$T/sa_withmock"; mkdir -p "$SA_B/scripts"
export SF15B_MARKER="$T/mockadd.called"
cat > "$SA_B/scripts/add-task.sh" <<'EOF'
#!/usr/bin/env bash
touch "$SF15B_MARKER"
echo "MOCK-ADDTASK"
echo "ID: 777000777"
echo "Task queued: 777000777"
EOF
chmod +x "$SA_B/scripts/add-task.sh"
OUT_B="$( SUPER_AGENT_DIR="$SA_B" bash "$QP" "$PROJ" "phaseX" --worker hetzner "hello task" 2>&1 )"
RC_B=$?
if [ "$RC_B" = "0" ] && [ -f "$SF15B_MARKER" ] && printf '%s' "$OUT_B" | grep -q 'MOCK-ADDTASK' \
   && ! printf '%s' "$OUT_B" | grep -q 'local dispatch'; then
  pass "SF15-b: injected mock add-task.sh still used (hermetic injection preserved)"
else
  fail "SF15-b: rc=$RC_B marker=$([ -f "$SF15B_MARKER" ] && echo yes || echo no); out: $(printf '%s' "$OUT_B" | tail -3 | tr '\n' ' ')"
fi
rm -rf "$T"

echo "---"
if [ "$FAIL" = "0" ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $FAIL
