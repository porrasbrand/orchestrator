#!/usr/bin/env bash
# smoke-tests.sh — thin wrapper for r1r2-06.
# The heavy lifting is scripts/integration-test-pm.sh; this suite verifies
# docs + regression coverage.
set -uo pipefail

ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=()
pass() { PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
fail() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  ❌ FAIL: $1"; }

cd "$ORCH_DIR"

# T1: bash -n + executable bit
echo "T1: bash -n + executable"
if bash -n scripts/integration-test-pm.sh 2>/dev/null && [[ -x scripts/integration-test-pm.sh ]]; then
    pass "T1: integration-test-pm.sh syntax clean + executable"
else
    fail "T1: syntax or executable bit missing"
fi

# T2: integration suite passes
echo "T2: integration suite runs green"
OUT="$(scripts/integration-test-pm.sh 2>&1)"
RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q 'scenarios=5' && echo "$OUT" | grep -q 'FAIL=0'; then
    pass "T2: exit 0 + scenarios=5 FAIL=0"
else
    fail "T2: rc=$RC or missing markers"
fi

# T3: idempotent re-run
echo "T3: integration suite re-run"
OUT="$(scripts/integration-test-pm.sh 2>&1)"
RC=$?
if [[ "$RC" == "0" ]] && echo "$OUT" | grep -q 'FAIL=0'; then
    pass "T3: idempotent — 2nd run still green"
else
    fail "T3: 2nd run failed"
fi

# T4: CLAUDE.md contains the new section + landmarks
echo "T4: CLAUDE.md landmarks"
if grep -q '## Resident PM' CLAUDE.md; then pass "T4a: 'Resident PM' section heading"; else fail "T4a: heading missing"; fi
if grep -q 'PM_GRACE_PERIOD' CLAUDE.md; then pass "T4b: PM_GRACE_PERIOD in env table"; else fail "T4b: PM_GRACE_PERIOD missing"; fi
if grep -q 'ONE phase advance' CLAUDE.md; then pass "T4c: iteration-semantics clarification"; else fail "T4c: iteration-semantics missing"; fi
if grep -q 'paused' CLAUDE.md && grep -q 'interrupt.json' CLAUDE.md && grep -q 'pm2 stop pm-daemon' CLAUDE.md; then
    pass "T4d: all three kill switches listed"
else
    fail "T4d: kill switches missing"
fi
if grep -q 'override' CLAUDE.md && grep -q 'resolutions.jsonl' CLAUDE.md; then
    pass "T4e: override-consumption instruction present"
else
    fail "T4e: override-consumption missing"
fi

# T5: runbook exists + landmarks
echo "T5: RESIDENT-PM-RUNBOOK.md landmarks"
if [[ -f docs/RESIDENT-PM-RUNBOOK.md ]]; then pass "T5a: file exists"; else fail "T5a: missing"; fi
for grep_target in 'pm2 restart pm-daemon' 'slack.env' 'register-project.sh' 'Deploy' 'Monitor' 'Failure playbook'; do
    if grep -q "$grep_target" docs/RESIDENT-PM-RUNBOOK.md 2>/dev/null; then
        pass "T5: contains '$grep_target'"
    else
        fail "T5: missing '$grep_target'"
    fi
done

# T6: notify-hook.sh.example header updated; below-header unchanged
echo "T6: notify-hook.sh.example header + code-unchanged"
if grep -q 'config/notify-hook.sh' config/notify-hook.sh.example; then
    pass "T6a: header references config/notify-hook.sh"
else
    fail "T6a: header missing reference"
fi
# Verify only comment lines changed (git diff --unified=0 grepping non-comment lines):
NON_COMMENT_DIFF="$(git diff -U0 config/notify-hook.sh.example \
    | grep -E '^[+-][^+-]' \
    | grep -Ev '^[+-]\s*#' \
    || true)"
if [[ -z "$NON_COMMENT_DIFF" ]]; then
    pass "T6b: only comment lines changed"
else
    fail "T6b: non-comment diff detected: $NON_COMMENT_DIFF"
fi

# T7: prior suites still green
echo "T7: prior suites"
for suite_line in \
    "r1-01-dispatch-ledger/smoke-tests.sh|11 passed" \
    "r1-02-pm-iterate/smoke-tests.sh|16 passed" \
    "r1-03-pm-daemon/smoke-tests.sh|19 passed" \
    "r2-04-slack-notify/smoke-tests.sh|18 passed" \
    "r2-05-slack-resolutions/smoke-tests.sh|32 passed"; do
    suite="${suite_line%%|*}"
    expected="${suite_line##*|}"
    label="${suite%%/*}"
    if bash ".planning/phases/$suite" 2>&1 | tail -1 | grep -q "$expected"; then
        pass "T7: $label still ${expected}"
    else
        fail "T7: $label regression"
    fi
done

echo ""
echo "=================================="
echo "Smoke test summary: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:"
    for n in "${FAILED_NAMES[@]}"; do echo "  - $n"; done
    exit 1
fi
exit 0
