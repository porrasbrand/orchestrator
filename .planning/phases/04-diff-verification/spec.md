# Phase 04: Diff-Based Verification

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 2 of the orchestrator enhancement roadmap. Three prior phases complete:

- **Phase 01 (structured-learnings):** Added `learnings.jsonl` as queryable source of truth + `scripts/update-learnings.sh` for add/query/regenerate. `init.sh` scaffolds JSONL file.

- **Phase 02 (context-handoff):** Added "Prior Work Summary" and "Expected Files Changed" sections to `templates/spec.md`. Added "Files Actually Changed" to `templates/result.md`.

- **Phase 03 (spec-quality-check):** Created `scripts/check-spec.sh` that validates specs before queuing. Checks for required sections (Objective, Acceptance Criteria, Smoke Tests) and warns on missing recommended sections. Had 1 revision to fix smoke test detection regex.

The spec template now includes an "Expected Files Changed" section where the orchestrator lists which files a phase should create or modify. The current `scripts/verify.sh` runs smoke tests and regression tests but does NOT check whether the DEV worker touched files outside the expected scope.

## Objective
Add a diff-based verification step to `scripts/verify.sh` that compares the actual git diff against the "Expected Files Changed" section from the spec. This catches scope creep — DEV workers modifying files they shouldn't have touched. The check should WARN (not fail) on unexpected files, since DEV may have legitimate reasons.

## Implementation Steps

1. **Read the current `scripts/verify.sh`** to understand its structure. It currently has:
   - Step 1: Basic checks (result.md exists, commit exists)
   - Step 2: Smoke test extraction and execution
   - Results summary with PASS/FAIL

2. **Add Step 1.5: Diff-Based Scope Check** between basic checks and smoke tests:
   - Extract the "Expected Files Changed" section from spec.md
   - Parse file paths from lines matching `- \`path/to/file\`` pattern
   - Get actual changed files via `git diff --name-only HEAD~1` on the DEV worker
   - Compare: any file in actual diff that's NOT in expected list → print WARNING
   - Ignore `.planning/` files in the diff (result.md, etc. are always expected)
   - This step produces WARNINGS only — does not increment FAIL count

3. **Output format for the diff check:**
   ```
   --- Scope Check ---
   Expected: 3 files
   Actual: 4 files changed
   ✅ scripts/check-spec.sh (expected)
   ✅ ENHANCEMENT-ROADMAP.md (expected)
   ✅ .planning/phases/03-spec-quality-check/result.md (ignored - .planning/)
   ⚠️  scripts/init.sh (UNEXPECTED - not in expected files list)
   
   Scope warnings: 1
   ```

4. **Handle missing "Expected Files Changed" section gracefully** — if spec doesn't have the section (older specs), skip the diff check entirely with a note: `--- Scope Check: skipped (no Expected Files Changed in spec) ---`

5. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 2 item 2.4 (diff-based verification) as done. Also mark Sprint 2 overall as COMPLETE.

## Files to Create
None.

## Files to Modify
- `scripts/verify.sh` — Add diff-based scope check step
- `ENHANCEMENT-ROADMAP.md` — Mark 2.4 and Sprint 2 as complete

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `templates/` (no changes)
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/check-spec.sh`

## Expected Files Changed
- `scripts/verify.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/04-diff-verification/result.md` (create)

## Acceptance Criteria
- [ ] verify.sh has a "Scope Check" step between basic checks and smoke tests
- [ ] Scope check extracts expected files from spec's "Expected Files Changed" section
- [ ] Scope check runs `git diff --name-only HEAD~1` on DEV worker
- [ ] Unexpected files produce WARNING (not error)
- [ ] `.planning/` files in diff are ignored (always expected)
- [ ] Missing "Expected Files Changed" section → scope check skipped gracefully
- [ ] Existing smoke test and basic check functionality unchanged
- [ ] ENHANCEMENT-ROADMAP.md shows 2.4 done and Sprint 2 complete

## Smoke Tests
Run these AFTER implementing:

1. `grep -c "Scope Check" ~/awsc-new/awesome/orchestrator/scripts/verify.sh` → expect at least `1`
2. `grep -c "Expected Files Changed" ~/awsc-new/awesome/orchestrator/scripts/verify.sh` → expect at least `1`
3. `grep "git diff --name-only" ~/awsc-new/awesome/orchestrator/scripts/verify.sh` → expect match
4. `grep ".planning/" ~/awsc-new/awesome/orchestrator/scripts/verify.sh | grep -i "skip\|ignore"` → expect match
5. `grep "2.4" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|complete\|✅"` → expect match
6. `grep -i "sprint 2.*complete\|sprint 2.*done\|sprint 2.*✅" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result to: `.planning/phases/04-diff-verification/result.md`
3. Commit with prefix: `[orchestrator-sprint2-04]`
4. Do NOT push
