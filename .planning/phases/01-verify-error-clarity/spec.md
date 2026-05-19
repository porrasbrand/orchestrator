# Phase 01: Verify.sh Error Clarity & Suggested Fixes
# Template: modify-bash-script
# REQUIRED_VARS: filled

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprints 1-6 complete (23 enhancements). The orchestrator has: worker registry, dependency DAG, parallel dispatch, merge orchestration, phase templates, structured results, executable smoke tests, and more.

`scripts/verify.sh` (240 lines) is the core verification engine. It runs smoke tests (script or markdown-based), checks scope via git diff, validates result.md/result.json, and logs events. Current problems:

1. **When a smoke test fails, the error message is minimal:** just `❌ (expected: X, got: Y)` — no context about WHAT went wrong or HOW to fix it.
2. **When scope check finds unexpected files, it just says** `⚠️ file (UNEXPECTED)` — doesn't suggest whether to add to spec or revert.
3. **When result.md is missing, it just says** `❌ result.md NOT FOUND` — doesn't remind the worker what path it should be at.
4. **No summary of suggested fixes at the end** — the PM has to interpret raw pass/fail and figure out the revision spec manually.
5. **Exit output is not machine-parseable** — other scripts can't easily extract what failed and why.

Gemini consultation (2026-04-15) identified this as the **#1 ROI improvement** over phase templates. The 6% failure rate costs 30+ minutes per revision cycle. Clearer errors + suggested fixes could cut revision time in half.

## Objective
Improve verify.sh to produce actionable error messages with context and a machine-readable failure summary. When verification fails, the output should tell the PM exactly what went wrong and suggest specific fixes for the revision spec.

## Implementation Steps

1. **Read the current `scripts/verify.sh`** (240 lines). Understand all verification steps.

2. **Add contextual error messages** — For each failure type, include:
   - What was expected
   - What was actually found
   - Suggested fix action

   Specific improvements:
   - **result.md missing:** `❌ result.md NOT FOUND at <full-path>. Worker must create this file. See templates/result.md for format.`
   - **Smoke test fail:** `❌ Test failed: <cmd>\n   Expected: <expected>\n   Got: <actual>\n   Suggestion: Check if <relevant-file> was modified correctly. Re-run: <cmd>`
   - **Scope warning:** `⚠️ <file> modified but NOT in Expected Files Changed.\n   Fix: Either add to spec's Expected Files Changed, or revert with: git checkout HEAD~1 -- <file>`
   - **result.json parse error:** `⚠️ result.json exists but is not valid JSON. Re-generate with: jq . < result.json`

3. **Add a failure summary block at the end** when FAIL > 0:
   ```
   --- Failure Summary ---
   FAILED: 2 of 8 tests
   
   1. [SMOKE_TEST] command-that-failed
      Fix: <suggested action>
   
   2. [SCOPE] unexpected-file.js  
      Fix: Add to Expected Files Changed or revert
   
   --- Suggested Revision Notes ---
   Include these in the revision spec's Context section:
   - Smoke test "command-that-failed" returned "actual" instead of "expected"
   - File unexpected-file.js was modified outside spec scope
   ```

4. **Write a machine-readable failure report** — When verification fails, write a JSON file:
   ```
   <phase-dir>/verification-report.json
   ```
   Schema:
   ```json
   {
     "phase": "01-phase-name",
     "verified": false,
     "timestamp": "2026-04-15T...",
     "pass": 6,
     "fail": 2,
     "total": 8,
     "failures": [
       {
         "type": "smoke_test",
         "test": "command that failed",
         "expected": "expected output",
         "actual": "actual output",
         "suggestion": "Check if file X was modified"
       },
       {
         "type": "scope",
         "file": "unexpected-file.js",
         "suggestion": "Add to Expected Files Changed or revert"
       }
     ],
     "revision_notes": "Include these in revision spec: ..."
   }
   ```
   Also write this on success (with `"verified": true, "failures": []`).

5. **Preserve ALL existing behavior.** Same exit codes (0=pass, 1=fail). Same events.jsonl logging. Same SSH retry logic. Same markdown/script test detection. This is purely additive — better messages, new report file.

6. **Update `ENHANCEMENT-ROADMAP.md`** — Add Sprint 7 section with 7.1 marked done.

## Files to Modify
- `scripts/verify.sh` — Add contextual errors, failure summary, verification-report.json output

## Files to Create
- None (verification-report.json is created at runtime in the phase dir)

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- All other scripts in scripts/ (get-worker.sh, dag.sh, branch.sh, etc.)
- `templates/`, `config/`
- `.planning/` (except events.jsonl which verify.sh already writes to)

## Expected Files Changed
- `scripts/verify.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/01-verify-error-clarity/result.md` (create)
- `.planning/phases/01-verify-error-clarity/result.json` (create)

## Acceptance Criteria
- [ ] verify.sh still exits 0 on all-pass, exits 1 on any failure (unchanged behavior)
- [ ] When result.md is missing, error message includes the full expected path
- [ ] When a smoke test fails, error includes expected value, actual value, and a suggestion
- [ ] When scope check finds unexpected files, suggestion includes specific revert command
- [ ] When FAIL > 0, a "Failure Summary" block is printed listing all failures with fix suggestions
- [ ] When FAIL > 0, a "Suggested Revision Notes" block provides copy-paste text for revision specs
- [ ] verification-report.json is written to phase dir (on both success and failure)
- [ ] verification-report.json is valid JSON (parseable by jq)
- [ ] All existing events.jsonl logging still works
- [ ] SSH retry logic still works (no regression)
- [ ] ENHANCEMENT-ROADMAP.md has Sprint 7 with 7.1 marked done

## Smoke Tests
```bash
# 1. verify.sh still executable
test -x ~/awsc-new/awesome/orchestrator/scripts/verify.sh && echo EXECUTABLE

# 2. "Failure Summary" string exists in verify.sh
grep -c "Failure Summary" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 1) ? "HAS_SUMMARY" : "MISSING"}'

# 3. "verification-report.json" string exists in verify.sh
grep -c "verification-report.json" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 1) ? "HAS_REPORT" : "MISSING"}'

# 4. "Suggested Revision Notes" string exists
grep -c "Suggested Revision Notes" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 1) ? "HAS_REVISION_NOTES" : "MISSING"}'

# 5. "suggestion" or "Suggestion" appears in error messages
grep -ci "suggest" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 3) ? "HAS_SUGGESTIONS" : "TOO_FEW"}'

# 6. JSON report uses jq for generation
grep -c "jq" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 3) ? "USES_JQ" : "TOO_FEW"}'

# 7. Still has ssh_retry function (regression check)
grep -c "ssh_retry" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 5) ? "SSH_RETRY_OK" : "REGRESSION"}'

# 8. Still has events.jsonl logging (regression check)
grep -c "events.jsonl\|EVENTS_FILE" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | awk '{print ($1 >= 4) ? "EVENTS_OK" : "REGRESSION"}'

# 9. Sprint 7 in roadmap
grep "Sprint 7" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md

# 10. 7.1 marked done
grep "7.1" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write result.json alongside result.md (see templates/result-schema.md for schema)
3. Write result to: `.planning/phases/01-verify-error-clarity/result.md`
4. Commit all changes with prefix: `[orchestrator-sprint7-01]`
5. Do NOT push
