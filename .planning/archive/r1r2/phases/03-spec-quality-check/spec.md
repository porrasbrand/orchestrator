# Phase 03: Spec Quality Check

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
This is Sprint 2 of the orchestrator enhancement roadmap. Prior phases in this sprint:

- **Phase 01 (structured-learnings):** Added `learnings.jsonl` as structured source of truth with schema (ts, phase, category, discovery, impact). Created `scripts/update-learnings.sh` for add/query/regenerate. Updated `init.sh` to scaffold JSONL file. All working.

- **Phase 02 (context-handoff):** Added two new sections to `templates/spec.md`: "Prior Work Summary" (max 500 words, for clean DEV context per phase) and "Expected Files Changed" (create/modify list for scope verification). Also added "Files Actually Changed" to `templates/result.md`. Updated ENHANCEMENT-ROADMAP.md.

The spec template now has these sections in order: Context, Prior Work Summary, Objective, Implementation Steps, Files to Create, Files to Modify, Do NOT Touch, Expected Files Changed, Acceptance Criteria, Smoke Tests, Completion Instructions.

## Objective
Create a new script `scripts/check-spec.sh` that validates a spec.md file before it gets queued to a DEV worker. The script catches vague or incomplete specs early — before they waste a full dispatch-implement-verify cycle.

## Implementation Steps

1. **Create `scripts/check-spec.sh`** that takes a spec.md path and validates it has:

   **Required sections (ERROR if missing — blocks queuing):**
   - `## Objective` — must exist and be non-empty (more than just placeholder text)
   - `## Acceptance Criteria` — must exist with at least 1 checkbox item (`- [ ]`)
   - `## Smoke Tests` — must exist with at least 1 test command

   **Recommended sections (WARNING if missing — doesn't block):**
   - `## Prior Work Summary` — warn if missing (new section from Phase 02)
   - `## Expected Files Changed` — warn if missing (new section from Phase 02)
   - `## Do NOT Touch` — warn if missing
   - `## Files to Create` or `## Files to Modify` — warn if neither exists

   **Quality checks (WARNING):**
   - Objective is less than 20 words → warn "Objective may be too vague"
   - Zero smoke test commands found → error (already covered above)
   - Acceptance criteria with no checkboxes → error

2. **Output format:**
   ```
   Checking: path/to/spec.md
   
   ✅ Objective: present (45 words)
   ✅ Acceptance Criteria: 5 items
   ✅ Smoke Tests: 3 tests found
   ⚠️  Prior Work Summary: MISSING (recommended)
   ⚠️  Expected Files Changed: MISSING (recommended)
   ✅ Do NOT Touch: present
   ✅ Files to Create/Modify: present
   
   Result: PASS (2 warnings)
   ```
   Or:
   ```
   Result: FAIL (1 error, 2 warnings)
   ```

3. **Exit codes:**
   - 0 = PASS (no errors, may have warnings)
   - 1 = FAIL (has errors)

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 2 item 2.3 (spec quality pre-check) as done.

## Files to Create
- `scripts/check-spec.sh` — Spec validation script

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 2.3 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `templates/` (no template changes this phase)
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`, `scripts/verify.sh`
- `scripts/update-learnings.sh`

## Expected Files Changed
- `scripts/check-spec.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/03-spec-quality-check/result.md` (create)

## Acceptance Criteria
- [ ] `scripts/check-spec.sh` is executable
- [ ] Detects missing Objective section (returns exit 1)
- [ ] Detects missing Acceptance Criteria (returns exit 1)
- [ ] Detects missing Smoke Tests (returns exit 1)
- [ ] Warns on missing Prior Work Summary (exit 0, prints warning)
- [ ] Warns on missing Expected Files Changed (exit 0, prints warning)
- [ ] Warns on short Objective (<20 words)
- [ ] Passes on a well-formed spec (like Phase 01 or 02 spec)
- [ ] Output shows clear PASS/FAIL with error/warning counts
- [ ] ENHANCEMENT-ROADMAP.md shows 2.3 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh ~/awsc-new/awesome/orchestrator/.planning/phases/01-structured-learnings/spec.md; echo "EXIT:$?"` → expect `EXIT:0` (well-formed spec should pass)
3. `echo "# Phase XX: Bad Spec" > /tmp/bad-spec.md && bash ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh /tmp/bad-spec.md; echo "EXIT:$?"` → expect `EXIT:1` (missing required sections)
4. `printf "# Phase\n## Objective\nDo stuff\n## Acceptance Criteria\n- [ ] Works\n## Smoke Tests\necho hi → expect hi\n" > /tmp/minimal-spec.md && bash ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh /tmp/minimal-spec.md; echo "EXIT:$?"` → expect `EXIT:0` (minimal but valid)
5. `bash ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh /tmp/minimal-spec.md 2>&1 | grep -c "⚠️"` → expect at least `2` (missing recommended sections)
6. `rm -f /tmp/bad-spec.md /tmp/minimal-spec.md` (cleanup)

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result to: `.planning/phases/03-spec-quality-check/result.md`
3. Commit with prefix: `[orchestrator-sprint2-03]`
4. Do NOT push
