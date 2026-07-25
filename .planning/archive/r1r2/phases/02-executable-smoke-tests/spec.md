# Phase 02: Executable Smoke Tests

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 3, Phase 01 just added structured result.json support:
- `templates/result-schema.md` — JSON schema for result.json (status, files, tests, blockers, summary)
- `templates/result.md` — now references result.json
- `templates/spec.md` — Completion Instructions mention result.json
- `scripts/verify.sh` — Step 1b parses result.json with jq when present; falls back gracefully

The current verify.sh runs smoke tests by parsing markdown in spec.md — extracting lines with `→ expect` patterns using regex. This is brittle (broke in Sprint 2 Phase 03 and required a revision). We want an alternative: executable `.sh` scripts that verify.sh can simply run.

## Objective
Add support for executable smoke test scripts (`.sh` files) in phase directories as an alternative to markdown-embedded tests. verify.sh detects and runs them when present, falling back to markdown parsing for phases that don't have scripts.

## Implementation Steps

1. **Create `templates/smoke-tests-template.sh`** — A template smoke test script:
   ```bash
   #!/bin/bash
   # Smoke tests for Phase XX: <Name>
   # Exit 0 = all pass, Exit 1 = failures
   
   PASS=0; FAIL=0
   
   # Test 1: description
   if <condition>; then echo "✅ Test 1"; PASS=$((PASS+1)); else echo "❌ Test 1"; FAIL=$((FAIL+1)); fi
   
   echo "Passed: $PASS Failed: $FAIL"
   [ $FAIL -eq 0 ] && exit 0 || exit 1
   ```

2. **Modify `scripts/verify.sh`** — After the existing Scope Check (Step 1.5) and before the markdown smoke test parsing (Step 2):
   - Add Step 1.7: Check if `<phase-dir>/smoke-tests.sh` exists on remote
   - If it exists and is executable: run it via SSH, capture exit code
   - Exit 0 → all smoke tests pass, count output lines with ✅ for PASS count
   - Exit 1 → some failed, count ❌ lines for FAIL count
   - If smoke-tests.sh exists: SKIP the markdown parsing entirely (Step 2)
   - If it doesn't exist: fall through to existing markdown parsing (backwards compatible)
   - Log to events.jsonl which method was used: `"method": "script"` or `"method": "markdown"`

3. **Modify `templates/spec.md`** — Add a note in the Smoke Tests section:
   ```
   Optional: Instead of inline tests, create an executable `smoke-tests.sh` in the phase 
   directory (see templates/smoke-tests-template.sh). verify.sh will run it automatically.
   ```

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 3 item 3.2 as done.

## Files to Create
- `templates/smoke-tests-template.sh` — Template for executable smoke tests (make it executable: chmod +x)

## Files to Modify
- `scripts/verify.sh` — Add Step 1.7: executable smoke test detection and execution
- `templates/spec.md` — Add note about optional smoke-tests.sh
- `ENHANCEMENT-ROADMAP.md` — Mark 3.2 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/check-spec.sh`
- `templates/result-schema.md`, `templates/result.md`

## Expected Files Changed
- `templates/smoke-tests-template.sh` (create)
- `scripts/verify.sh` (modify)
- `templates/spec.md` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-executable-smoke-tests/result.md` (create)
- `.planning/phases/02-executable-smoke-tests/result.json` (create)

## Acceptance Criteria
- [ ] `templates/smoke-tests-template.sh` exists and is executable
- [ ] Template has clear structure: setup, individual tests with pass/fail counting, summary, exit code
- [ ] verify.sh checks for `smoke-tests.sh` in phase directory on remote
- [ ] verify.sh runs smoke-tests.sh via SSH when found, uses exit code for verdict
- [ ] verify.sh skips markdown parsing when smoke-tests.sh exists
- [ ] verify.sh falls back to markdown parsing when no smoke-tests.sh (backwards compatible)
- [ ] templates/spec.md mentions optional smoke-tests.sh
- [ ] ENHANCEMENT-ROADMAP.md shows 3.2 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/templates/smoke-tests-template.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `grep "smoke-tests.sh" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | head -1` → expect match
3. `grep -c "smoke-tests.sh" ~/awsc-new/awesome/orchestrator/scripts/verify.sh` → expect at least `2`
4. `grep "smoke-tests.sh" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect match
5. `grep "3.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|complete\|✅"` → expect match
6. `bash ~/awsc-new/awesome/orchestrator/templates/smoke-tests-template.sh; echo "EXIT:$?"` → expect `EXIT:1` (template has placeholder tests that should fail)

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md (see templates/result-schema.md)
3. Write result to: `.planning/phases/02-executable-smoke-tests/result.md`
4. Commit with prefix: `[orchestrator-sprint3-02]`
5. Do NOT push
