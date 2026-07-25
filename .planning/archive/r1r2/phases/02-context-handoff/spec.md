# Phase 02: Context Handoff

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

**Prior Work Summary:** Phase 01 added structured learnings — `learnings.jsonl` with schema, `scripts/update-learnings.sh` for add/query/regenerate, and updated `init.sh` to scaffold the JSONL file. All scripts working, 7/7 smoke tests passed.

The orchestrator's spec template (`templates/spec.md`) currently has no mechanism for:
1. Summarizing prior phase work for fresh DEV worker context
2. Declaring which files a phase expects to change (for scope verification)

This causes two problems: DEV workers in long projects operate with degraded context (no clean summary), and there's no way to verify a phase didn't touch files outside its scope.

## Objective
Add two new sections to the spec template:
1. **"Prior Work Summary"** — A concise (max 500 words) summary of what prior phases built, so DEV workers start with clean context instead of accumulating stale state
2. **"Expected Files Changed"** — An explicit list of files this phase should create/modify, enabling diff-based verification in Phase 04

## Implementation Steps

1. **Modify `templates/spec.md`** — Add these two sections:

   After "## Context", add:
   ```markdown
   ## Prior Work Summary
   [Concise summary of what prior phases built — max 500 words. Include: key files created,
   architecture decisions made, any learnings that affect this phase. This section ensures
   DEV workers have clean context without needing to read all prior specs.]
   ```

   After "## Do NOT Touch", add:
   ```markdown
   ## Expected Files Changed
   Files this phase should create or modify. Verification will warn if other files are touched.
   - `path/to/file.js` (create | modify) — [purpose]
   ```

2. **Modify `templates/result.md`** — Add a "Files Actually Changed" section so DEV workers self-report what they touched. Read the current result.md template first to understand its structure.

3. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 2 items 2.2 (context reset) as done.

## Files to Create
None.

## Files to Modify
- `templates/spec.md` — Add "Prior Work Summary" and "Expected Files Changed" sections
- `templates/result.md` — Add "Files Actually Changed" section
- `ENHANCEMENT-ROADMAP.md` — Mark 2.2 as done

## Do NOT Touch
- `CLAUDE.md`
- `PLAN.md`
- `scripts/` (no script changes in this phase)
- `templates/brief.md`
- `.planning/` (except result.md for this phase)

## Expected Files Changed
- `templates/spec.md` (modify)
- `templates/result.md` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-context-handoff/result.md` (create)

## Acceptance Criteria
- [ ] `templates/spec.md` contains "## Prior Work Summary" section with guidance (max 500 words note)
- [ ] `templates/spec.md` contains "## Expected Files Changed" section with create/modify notation
- [ ] `templates/result.md` contains "## Files Actually Changed" section
- [ ] Sections are in logical order within the templates
- [ ] No other template files modified
- [ ] ENHANCEMENT-ROADMAP.md shows 2.2 as done

## Smoke Tests
Run these AFTER implementing:

1. `grep -c "Prior Work Summary" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect `1`
2. `grep -c "Expected Files Changed" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect `1`
3. `grep -c "Files Actually Changed" ~/awsc-new/awesome/orchestrator/templates/result.md` → expect `1`
4. `grep "max 500 words" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect match
5. `grep "create | modify" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect match
6. `grep "2.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|complete\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result to: `.planning/phases/02-context-handoff/result.md`
3. Commit with prefix: `[orchestrator-sprint2-02]`
4. Do NOT push
