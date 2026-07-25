# Phase 03: Spec Quality Check — Revision 1

## What Failed
The smoke test detection logic in `check-spec.sh` fails to find smoke tests in well-formed specs.

**Test that failed:**
```
bash scripts/check-spec.sh .planning/phases/01-structured-learnings/spec.md
```
**Output:**
```
❌ Smoke Tests: no test commands found (required)
Result: FAIL (1 error(s), 1 warning(s))
```
**Expected:** PASS — Phase 01's spec has 7 clearly defined smoke tests.

**Root cause:** The smoke test section extraction (`awk` + `sed` pattern) doesn't correctly capture the content. Phase 01's spec has smoke tests formatted as:
```
1. `cd ~/awsc-new/awesome/orchestrator && bash scripts/init.sh /tmp/test-orch-s2` → expect "scaffolded"
2. `test -f /tmp/test-orch-s2/.planning/learnings.jsonl && echo EXISTS` → expect `EXISTS`
```

The awk pattern `/^## Smoke Tests$/,/^## [^S]|^$/{if(!/^## /)print}` is likely failing because:
- The alternation `|^$` in the range end makes it stop at first blank line
- The actual section has blank lines between test entries

**Fix needed:** Simpler extraction — capture everything from `## Smoke Tests` to the next `## ` heading (or EOF). Then count lines containing backticks, `→`, `expect`, or numbered items with commands.

## Full Original Spec
Read `.planning/phases/03-spec-quality-check/spec.md` for the complete original spec.

## Additional Guidance
- Test against REAL specs in `.planning/phases/01-structured-learnings/spec.md` and `.planning/phases/02-context-handoff/spec.md` — both should PASS
- The smoke tests in real specs use format: `1. \`command\` → expect \`output\``
- Blank lines between smoke test entries are normal — don't stop parsing on blank lines
- Keep the fix simple: `sed -n '/^## Smoke Tests/,/^## /p'` then count meaningful lines
