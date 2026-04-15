# Phase XX: {{PHASE_NAME}}
# Template: modify-bash-script
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, SCRIPT_NAME, CHANGE_DESCRIPTION, REGRESSION_CHECK

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Modify the existing bash script `{{SCRIPT_NAME}}` to {{CHANGE_DESCRIPTION}}, while preserving all existing behavior.

## Implementation Steps
1. **Read current `{{SCRIPT_NAME}}`** — Understand existing structure, arguments, and behavior
2. **Identify change points** — Locate the specific sections that need modification for: {{CHANGE_DESCRIPTION}}
3. **Implement changes** — Modify the script while preserving:
   - Existing argument interface (no breaking changes)
   - Existing exit codes and output format
   - All current functionality that is not being changed
4. **Verify old behavior preserved** — Run regression check: {{REGRESSION_CHECK}}
5. **Verify new behavior works** — Test the new functionality added by this change
6. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
None.

## Files to Modify
- `{{SCRIPT_NAME}}` — {{CHANGE_DESCRIPTION}}
- `ENHANCEMENT-ROADMAP.md` — Mark this phase as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Other scripts not referenced in this spec
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- `{{SCRIPT_NAME}}` (modify) — Script changes
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] `{{SCRIPT_NAME}}` is still executable after changes
- [ ] New behavior works: {{CHANGE_DESCRIPTION}}
- [ ] Old behavior preserved: {{REGRESSION_CHECK}}
- [ ] No new dependencies introduced without documentation
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: Script is still executable
test -x ~/awsc-new/awesome/orchestrator/{{SCRIPT_NAME}} && echo EXECUTABLE
# expect: EXECUTABLE

# Test 2: New behavior works
# [Fill in test for: {{CHANGE_DESCRIPTION}}]

# Test 3: OLD behavior regression check
# {{REGRESSION_CHECK}}
# expect: Same output/behavior as before this change
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
