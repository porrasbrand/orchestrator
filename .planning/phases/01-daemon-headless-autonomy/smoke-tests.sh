#!/usr/bin/env bash
# PM-authored verification contract for Phase 01 (daemon-headless-autonomy, SF-15 + SF-14).
# CWD = orchestrator repo root when run by verify.sh (resident/local). One ✅/❌ per check.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"   # -> orchestrator repo root
cd "$REPO"
FAIL=0
pass(){ echo "✅ $1"; }
fail(){ echo "❌ $1"; FAIL=1; }

# --- syntax ---
node --check services/pm-daemon.js 2>/dev/null && pass "T1: node --check pm-daemon.js" || fail "T1: pm-daemon.js syntax"
bash -n scripts/queue-phase.sh 2>/dev/null && pass "T2: bash -n queue-phase.sh" || fail "T2: queue-phase.sh syntax"

# --- SF-15 fix marker: queue-phase.sh has a resident fallback keyed on add-task.sh absence ---
if grep -qiE "SF-15" scripts/queue-phase.sh && grep -qE "add-task\.sh" scripts/queue-phase.sh && grep -qE "dispatch-local-hetzner\.sh" scripts/queue-phase.sh; then
  pass "T3: SF-15 fallback present in queue-phase.sh"
else
  fail "T3: SF-15 fallback marker/logic not found in queue-phase.sh"
fi

# --- SF-14 fix marker: pm-daemon.js guards the move / clears claim ---
if grep -qiE "SF-14" services/pm-daemon.js && grep -qE "existsSync|catch" services/pm-daemon.js; then
  pass "T4: SF-14 guard present in pm-daemon.js"
else
  fail "T4: SF-14 guard marker not found in pm-daemon.js"
fi

# --- hermetic tests (worker-authored) ---
if [ -x scripts/test-sf15.sh ]; then
  if bash scripts/test-sf15.sh >/tmp/sf15.out 2>&1; then pass "T5: test-sf15.sh (SF-15 hermetic) PASS"; else fail "T5: test-sf15.sh FAILED"; tail -8 /tmp/sf15.out | sed 's/^/    /'; fi
else
  fail "T5: scripts/test-sf15.sh missing/not executable"
fi
if [ -x scripts/test-sf14.sh ]; then
  if bash scripts/test-sf14.sh >/tmp/sf14.out 2>&1; then pass "T6: test-sf14.sh (SF-14 hermetic) PASS"; else fail "T6: test-sf14.sh FAILED"; tail -8 /tmp/sf14.out | sed 's/^/    /'; fi
else
  fail "T6: scripts/test-sf14.sh missing/not executable"
fi

# --- regression suites (must stay green) ---
for suite in integration-test-pm.sh integration-test.sh test-numenv.sh; do
  if [ -x "scripts/$suite" ]; then
    if bash "scripts/$suite" >/tmp/$suite.out 2>&1; then
      pass "T-reg: $suite green"
    else
      fail "T-reg: $suite FAILED"; tail -12 /tmp/$suite.out | sed 's/^/    /'
    fi
  else
    echo "ℹ️  scripts/$suite not present — skipping"
  fi
done

# --- daemon online after deploy (pm2 restart is the worker's deploy step) ---
if command -v pm2 >/dev/null 2>&1; then
  ST="$(pm2 jlist 2>/dev/null | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const a=JSON.parse(d);const p=a.find(x=>x.name==='pm-daemon');console.log(p?p.pm2_env.status:'missing')}catch{console.log('parse-err')}})" 2>/dev/null)"
  [ "$ST" = "online" ] && pass "T-daemon: pm-daemon status=online" || fail "T-daemon: pm-daemon status=$ST"
else
  echo "ℹ️  pm2 not on PATH in this context — daemon-online check deferred to PM close"
fi

# --- findings resolved in learnings ---
if grep -qiE "SF-15.*(resolved|fixed)" .planning/learnings.md && grep -qiE "SF-14.*(resolved|fixed)" .planning/learnings.md; then
  pass "T-learn: SF-15 + SF-14 marked resolved in learnings.md"
else
  fail "T-learn: learnings.md missing SF-15/SF-14 resolution"
fi

echo "---"
if [ "$FAIL" = "0" ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $FAIL
