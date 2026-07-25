#!/usr/bin/env bash
# test-numenv.sh — focused hermetic regression for pm-daemon numEnv() (phase 05, finding F1).
# Proves PM_GRACE_PERIOD=0 is honored (both the startup string AND a real claim), invalid/
# negative values fall back to the default WITH a warning, and interval knobs keep the min=1
# floor. Hermetic: no real Slack, no real claude, no writes outside mktemp, never touches the
# live ~/.orchestrator or any pm2 process. Exit 0 only when N1–N5 all pass.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
pass(){ echo "✅ $1"; }
fail(){ echo "❌ $1"; FAIL=1; }

# probe VAR=VAL... -> run pm-daemon --once in a throwaway state dir; print startup line + warnings.
probe(){
  local T; T=$(mktemp -d)
  ( cd "$ORCH_DIR" && env ORCH_STATE_DIR="$T/state" SUPER_AGENT_DIR="$T/sa" \
      SLACK_BOT_TOKEN= SLACK_CHANNEL= "$@" \
      node services/pm-daemon.js --once 2>&1 | head -20 )
  rm -rf "$T"
}

# ---- N1: grace=0 honored in the startup line ----
OUT=$(probe PM_GRACE_PERIOD=0)
if echo "$OUT" | grep -q 'grace=0s'; then
  pass "N1: PM_GRACE_PERIOD=0 -> grace=0s (startup line)"
else
  fail "N1: grace=0 not honored — got $(echo "$OUT" | grep -o 'grace=[0-9]*s' | head -1)"
fi

# ---- N2: behavioural — grace=0 CLAIMS a fresh (age~0) response in one --once cycle ----
# Under the old bug (0 -> 600s) a fresh file would NOT be claimed; under the fix it is.
T=$(mktemp -d)
STATE="$T/state"; SA="$T/sa"; PROJ="$T/proj"
mkdir -p "$STATE" "$SA/tasks/responses/new" "$PROJ/.planning"
cat > "$PROJ/.planning/status.json" <<'JSON'
{ "project": "projN", "current_phase": "p1", "phases": { "p1": { "status": "complete" } } }
JSON
: > "$PROJ/.planning/events.jsonl"
jq -n --arg lp "$PROJ" '[
  {name:"projN", local_path:$lp, worker:"hetzner", remote_path:"", active:true, registered_at:"2026-07-02T00:00:00Z"}
]' > "$STATE/active-projects.json"
TID="222222222222222222"
jq -c -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg id "$TID" --arg pp "$PROJ" \
  '{ts:$ts, task_id:$id, project:"projN", project_path:$pp, phase:"p1", worker:"hetzner"}' \
  > "$STATE/dispatch-ledger.jsonl"
# Fresh response file (mtime ~ now) — the crux: no grace wait.
echo "{\"id\":$TID,\"response\":\"done\"}" > "$SA/tasks/responses/new/$TID.json"
# PM_ITERATE_MOCK: real pm-iterate copies this transcript instead of invoking claude.
echo "[mock] pm iteration ran" > "$T/mock-transcript.txt"
( cd "$ORCH_DIR" && env ORCH_STATE_DIR="$STATE" SUPER_AGENT_DIR="$SA" \
    SLACK_BOT_TOKEN= SLACK_CHANNEL= PM_GRACE_PERIOD=0 PM_ITERATE_MOCK="$T/mock-transcript.txt" \
    node services/pm-daemon.js --once >/dev/null 2>&1 )
if [ ! -f "$SA/tasks/responses/new/$TID.json" ]; then
  pass "N2: grace=0 claimed a fresh response in one --once cycle (file left new/)"
else
  fail "N2: fresh response still in new/ — grace=0 did NOT claim immediately"
fi
rm -rf "$T"

# ---- N3: invalid value -> default 600 + a warning naming the var ----
OUT=$(probe PM_GRACE_PERIOD=abc)
if echo "$OUT" | grep -q 'grace=600s' && echo "$OUT" | grep -qi 'ignoring invalid PM_GRACE_PERIOD'; then
  pass "N3: PM_GRACE_PERIOD=abc -> grace=600s WITH a warning naming the var"
else
  fail "N3: invalid not loudly rejected — grace=$(echo "$OUT" | grep -o 'grace=[0-9]*s' | head -1) warn=$(echo "$OUT" | grep -ci 'PM_GRACE_PERIOD')"
fi

# ---- N4: negative value -> default 600 + warning ----
OUT=$(probe PM_GRACE_PERIOD=-5)
if echo "$OUT" | grep -q 'grace=600s' && echo "$OUT" | grep -qi 'ignoring invalid PM_GRACE_PERIOD'; then
  pass "N4: PM_GRACE_PERIOD=-5 -> grace=600s WITH a warning"
else
  fail "N4: negative not loudly rejected — grace=$(echo "$OUT" | grep -o 'grace=[0-9]*s' | head -1) warn=$(echo "$OUT" | grep -ci 'PM_GRACE_PERIOD')"
fi

# ---- N5: interval knob keeps the min=1 floor (0 rejected, loudly) ----
OUT=$(probe PM_POLL_INTERVAL=0)
if echo "$OUT" | grep -q 'poll=60s' && echo "$OUT" | grep -qi 'ignoring invalid PM_POLL_INTERVAL'; then
  pass "N5: PM_POLL_INTERVAL=0 rejected (poll=60s, min=1 floor kept) WITH a warning"
else
  fail "N5: interval floor lost — poll=$(echo "$OUT" | grep -o 'poll=[0-9]*s' | head -1) warn=$(echo "$OUT" | grep -ci 'PM_POLL_INTERVAL')"
fi

echo "---"
if [ "$FAIL" = "0" ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $FAIL
