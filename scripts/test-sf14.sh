#!/usr/bin/env bash
# test-sf14.sh — hermetic proof of the SF-14 fix in services/pm-daemon.js.
# A claimed shim already archived/removed by the interactive PM must NOT throw an escaping
# exception during scanCycle: the cycle completes and claims[taskId] is cleared. Hermetic —
# temp ORCH_STATE_DIR/SUPER_AGENT_DIR, a mock pm-iterate, no live ~/.orchestrator, no pm2.
set -uo pipefail
ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass(){ echo "✅ $1"; }
fail(){ echo "❌ $1"; FAIL=1; }

T="$(mktemp -d)"
STATE="$T/state"; SA="$T/sa"; PROJ="$T/proj"
mkdir -p "$STATE" "$SA/tasks/responses/new" "$SA/tasks/responses/claimed" "$PROJ/.planning"
cat > "$PROJ/.planning/status.json" <<'JSON'
{ "project": "projSF14", "current_phase": "p1", "phases": { "p1": { "status": "complete" } } }
JSON
: > "$PROJ/.planning/events.jsonl"
jq -n --arg lp "$PROJ" '[
  {name:"projSF14", local_path:$lp, worker:"hetzner", remote_path:"", active:true, registered_at:"2026-07-02T00:00:00Z"}
]' > "$STATE/active-projects.json"
TID="314314314314314314"
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$TID" --arg pp "$PROJ" \
  '{ts:$ts, task_id:$id, project:"projSF14", project_path:$pp, phase:"p1", worker:"hetzner"}' \
  > "$STATE/dispatch-ledger.jsonl"
# The shim is ALREADY claimed (in claimed/), and a stale claim entry exists in daemon-state.
echo "{\"id\":$TID,\"response\":\"done\"}" > "$SA/tasks/responses/claimed/$TID.json"
printf '{"claims":{"%s":{"attempts":0,"last_ts":"x"}}}\n' "$TID" > "$STATE/daemon-state.json"

# Mock pm-iterate: simulate the interactive PM archiving the shim mid-iteration by DELETING
# the --response-file, then return success. Without the SF-14 guard, the daemon's subsequent
# moveFile(claimedPath) throws ENOENT and escapes scanCycle (leaking the claim).
MOCK="$T/mock-iterate.sh"
cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
rf=""
while [ $# -gt 0 ]; do case "$1" in --response-file) rf="$2"; shift 2;; *) shift;; esac; done
[ -n "$rf" ] && rm -f "$rf"     # simulate the interactive PM having archived/removed the shim
echo "RAN: exit=0 transcript=/dev/null"
exit 0
EOF
chmod +x "$MOCK"

OUT="$( cd "$ORCH_DIR" && env ORCH_STATE_DIR="$STATE" SUPER_AGENT_DIR="$SA" \
  SLACK_BOT_TOKEN= SLACK_CHANNEL= PM_ITERATE_BIN="$MOCK" PM_RESOLUTIONS_BIN=/bin/true \
  node services/pm-daemon.js --once 2>&1 )"
RC=$?

# 1. cycle completed with no escaping exception (the old bug logs 'scan error:' + an ENOENT stack)
if [ "$RC" = "0" ] && ! printf '%s' "$OUT" | grep -qiE 'scan error|ENOENT'; then
  pass "SF14-1: --once completed, no escaping exception (no 'scan error'/ENOENT)"
else
  fail "SF14-1: rc=$RC; offending: $(printf '%s' "$OUT" | grep -iE 'scan error|ENOENT' | head -2 | tr '\n' ' ')"
fi

# 2. the guard path was actually exercised (moveFile saw the pre-archived source)
if printf '%s' "$OUT" | grep -q 'source already gone'; then
  pass "SF14-2: moveFile guard exercised (pre-archived source tolerated, no throw)"
else
  fail "SF14-2: guard log not observed — out: $(printf '%s' "$OUT" | tail -4 | tr '\n' ' ')"
fi

# 3. claims[taskId] cleared from daemon-state.json
LEFT="$(node -e "try{const s=JSON.parse(require('fs').readFileSync('$STATE/daemon-state.json','utf8'));process.stdout.write(String(!!(s.claims&&s.claims['$TID'])))}catch(e){process.stdout.write('err:'+e.message)}")"
if [ "$LEFT" = "false" ]; then
  pass "SF14-3: claims[$TID] cleared from daemon-state.json"
else
  fail "SF14-3: claim not cleared (present=$LEFT)"
fi

rm -rf "$T"
echo "---"
if [ "$FAIL" = "0" ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $FAIL
