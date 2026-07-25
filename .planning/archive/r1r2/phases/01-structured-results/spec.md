# Phase 01: Structured Results

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
This is Sprint 3 of the orchestrator enhancement roadmap. Sprint 2 (complete) added:
- `scripts/update-learnings.sh` — structured JSONL learnings with add/query/regenerate
- `templates/spec.md` — now has "Prior Work Summary", "Expected Files Changed" sections
- `templates/result.md` — now has "Files Actually Changed" section
- `scripts/check-spec.sh` — pre-queue spec validation
- `scripts/verify.sh` — now has diff-based scope check (Step 1.5)

Currently, DEV workers write only `result.md` (markdown). The orchestrator's verify.sh does basic checks (file exists, commit exists) but cannot programmatically parse what happened. Adding a structured `result.json` lets verify.sh make decisions based on machine-readable data.

## Objective
Add a structured `result.json` format that DEV workers write alongside result.md, and update verify.sh to read it when present. This replaces fragile markdown parsing with JSON parsing for verification decisions.

## Implementation Steps

1. **Create `templates/result-schema.md`** documenting the result.json schema:
   ```json
   {
     "status": "complete",
     "phase": "01-structured-results",
     "commit": "abc1234",
     "files_modified": ["scripts/verify.sh", "templates/result.md"],
     "files_created": ["templates/result-schema.md"],
     "tests_run": [
       {"name": "result.json exists", "passed": true},
       {"name": "schema validates", "passed": true}
     ],
     "blockers": [],
     "summary": "Added result.json schema and updated verify.sh to read it"
   }
   ```
   - `status`: "complete" | "partial" | "blocked"
   - `files_modified` + `files_created`: arrays of paths
   - `tests_run`: array of {name, passed} objects
   - `blockers`: array of strings (empty if none)
   - `summary`: one-line description

2. **Modify `templates/result.md`** — Add a note at the top: "Also write result.json alongside this file (see templates/result-schema.md)."

3. **Modify `templates/spec.md`** — Update the Completion Instructions section to include: "Write result.json alongside result.md (see templates/result-schema.md for schema)."

4. **Modify `scripts/verify.sh`** — In the Basic Checks step (Step 1), after checking result.md exists:
   - Check if `result.json` exists on remote
   - If yes: parse it with `jq`, extract status field, report files_modified count, tests_run pass rate
   - If no: print note "result.json not found (optional, falling back to result.md only)"
   - This does NOT replace the existing result.md check — both coexist
   - Add a summary line after basic checks: `"Result JSON: status=complete, 3 files changed, 4/4 tests passed"` (or "not present")

## Files to Create
- `templates/result-schema.md` — Schema documentation with examples

## Files to Modify
- `templates/result.md` — Add result.json reference note
- `templates/spec.md` — Update Completion Instructions
- `scripts/verify.sh` — Add result.json parsing in basic checks

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/check-spec.sh`
- `scripts/cancel-task.sh` (doesn't exist yet — Phase 03)

## Expected Files Changed
- `templates/result-schema.md` (create)
- `templates/result.md` (modify)
- `templates/spec.md` (modify)
- `scripts/verify.sh` (modify)
- `.planning/phases/01-structured-results/result.md` (create)

## Acceptance Criteria
- [ ] `templates/result-schema.md` exists with full JSON schema documentation and example
- [ ] `templates/result.md` references result.json
- [ ] `templates/spec.md` Completion Instructions mention result.json
- [ ] verify.sh checks for result.json on remote worker
- [ ] verify.sh parses result.json with jq when present (status, files count, tests count)
- [ ] verify.sh gracefully handles missing result.json (prints note, continues)
- [ ] Existing verify.sh functionality unchanged (smoke tests, scope check, regression)
- [ ] All JSON in result-schema.md is valid (parseable by jq)

## Smoke Tests
Run these AFTER implementing:

1. `test -f ~/awsc-new/awesome/orchestrator/templates/result-schema.md && echo EXISTS` → expect `EXISTS`
2. `grep -c "result.json" ~/awsc-new/awesome/orchestrator/templates/result.md` → expect at least `1`
3. `grep -c "result.json" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect at least `1`
4. `grep "result.json" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | head -1` → expect match
5. `grep "jq" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | head -1` → expect match
6. `cat ~/awsc-new/awesome/orchestrator/templates/result-schema.md | grep -A20 '"status"' | head -10 | jq . >/dev/null 2>&1 && echo VALID_JSON || echo INVALID_JSON` → expect `VALID_JSON`

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md:
   ```json
   {"status":"complete","phase":"01-structured-results","commit":"<hash>","files_modified":["templates/result.md","templates/spec.md","scripts/verify.sh"],"files_created":["templates/result-schema.md"],"tests_run":[{"name":"schema exists","passed":true},{"name":"result.md ref","passed":true},{"name":"spec.md ref","passed":true},{"name":"verify.sh json","passed":true},{"name":"verify.sh jq","passed":true},{"name":"valid json","passed":true}],"blockers":[],"summary":"Added result.json schema and verify.sh JSON parsing"}
   ```
3. Write result to: `.planning/phases/01-structured-results/result.md`
4. Commit with prefix: `[orchestrator-sprint3-01]`
5. Do NOT push
