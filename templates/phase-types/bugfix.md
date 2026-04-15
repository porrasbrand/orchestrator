# Phase XX: {{PHASE_NAME}}
# Template: bugfix
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, BUG_DESCRIPTION, REPRODUCE_STEPS, AFFECTED_FILES

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Fix the bug: {{BUG_DESCRIPTION}}. Affected files: {{AFFECTED_FILES}}.

## Implementation Steps
1. **Reproduce the bug** — Run the following steps to confirm the bug exists:
   {{REPRODUCE_STEPS}}
2. **Root cause analysis** — Read the affected files and identify why the bug occurs
3. **Implement the fix** — Modify the affected files to resolve the root cause
4. **Verify the fix** — Re-run the reproduce steps and confirm the bug is gone
5. **Regression test** — Verify existing functionality in affected files still works correctly
6. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
None.

## Files to Modify
- {{AFFECTED_FILES}} — Bug fix changes

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Files not related to the bug
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- {{AFFECTED_FILES}} (modify) — Bug fix
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] Bug is no longer reproducible: {{BUG_DESCRIPTION}}
- [ ] Reproduce steps now produce correct behavior
- [ ] Fix is minimal — only changes what is necessary
- [ ] Existing tests/smoke tests for affected files still pass
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: Bug is gone — reproduce steps now succeed
# {{REPRODUCE_STEPS}}
# expect: Correct behavior (no bug)

# Test 2: Fix verified — specific assertion
# [Fill in assertion that the fix works]

# Test 3: Existing tests still pass
# [Fill in existing smoke tests for {{AFFECTED_FILES}}]
# expect: Same pass/fail as before the fix
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
