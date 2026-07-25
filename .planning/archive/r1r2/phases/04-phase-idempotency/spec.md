# Phase 04: Phase Idempotency

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 3 — three phases complete:
- **Phase 01 (structured-results):** Added result.json schema. verify.sh reads JSON results with jq, falls back to result.md.
- **Phase 02 (executable-smoke-tests):** Added smoke-tests.sh support in phase dirs. verify.sh runs scripts when found, falls back to markdown. Template at templates/smoke-tests-template.sh.
- **Phase 03 (cancellation):** Created scripts/cancel-task.sh. Cancels queued phases by updating status.json (via jq) and logging to events.jsonl. Validates phase exists and is in queued state.

Currently, if a phase partially completes (e.g., DEV worker crashes mid-implementation) and gets re-queued, the second run may create duplicate files, append duplicate data, or leave inconsistent state. There's no guidance in the spec template for making phases safe to re-run.

## Objective
Add an optional "Cleanup" section to the spec template that guides DEV workers on how to make their phase idempotent — safe to re-run without side effects. Also mark Sprint 3 as complete in the roadmap.

## Implementation Steps

1. **Modify `templates/spec.md`** — Add an optional "Cleanup" section between "Do NOT Touch" and "Expected Files Changed":
   ```markdown
   ## Cleanup (optional)
   Run these commands BEFORE implementation to ensure idempotent re-runs:
   - `rm -f path/to/file-this-phase-creates` — remove previous partial output
   - `git checkout -- path/to/file` — reset file to pre-phase state
   [If this phase is safe to re-run without cleanup, write "No cleanup needed."]
   ```

2. **Update `scripts/check-spec.sh`** — Add "Cleanup" to the list of recognized sections (not required, not warned if missing — purely optional). This prevents future check-spec versions from flagging it as unknown.

3. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 3 item 3.4 as done AND mark Sprint 3 overall as COMPLETE (all 4 items done).

## Files to Create
None.

## Files to Modify
- `templates/spec.md` — Add optional Cleanup section
- `scripts/check-spec.sh` — Recognize Cleanup as valid section
- `ENHANCEMENT-ROADMAP.md` — Mark 3.4 done + Sprint 3 complete

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/verify.sh`, `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/cancel-task.sh`
- `templates/result.md`, `templates/result-schema.md`, `templates/smoke-tests-template.sh`

## Expected Files Changed
- `templates/spec.md` (modify)
- `scripts/check-spec.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/04-phase-idempotency/result.md` (create)
- `.planning/phases/04-phase-idempotency/result.json` (create)

## Acceptance Criteria
- [ ] templates/spec.md contains "## Cleanup" section with guidance on idempotent re-runs
- [ ] Cleanup section is clearly marked as optional
- [ ] Cleanup section is positioned between "Do NOT Touch" and "Expected Files Changed"
- [ ] check-spec.sh recognizes "Cleanup" (doesn't warn about unknown section)
- [ ] check-spec.sh still passes on specs without Cleanup (optional, no warning)
- [ ] ENHANCEMENT-ROADMAP.md shows 3.4 done and Sprint 3 COMPLETE
- [ ] Existing check-spec.sh functionality unchanged (required/recommended section checks)

## Smoke Tests
Run these AFTER implementing:

1. `grep -c "## Cleanup" ~/awsc-new/awesome/orchestrator/templates/spec.md` → expect `1`
2. `grep -i "optional" ~/awsc-new/awesome/orchestrator/templates/spec.md | grep -i cleanup | head -1` → expect match
3. `grep "Cleanup" ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh | head -1` → expect match
4. `bash ~/awsc-new/awesome/orchestrator/scripts/check-spec.sh ~/awsc-new/awesome/orchestrator/.planning/phases/01-structured-results/spec.md >/dev/null 2>&1; echo "EXIT:$?"` → expect `EXIT:0` (spec without Cleanup still passes)
5. `grep "3.4" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|complete\|✅"` → expect match
6. `grep -i "sprint 3.*complete\|sprint 3.*done\|sprint 3.*✅" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/04-phase-idempotency/result.md`
4. Commit with prefix: `[orchestrator-sprint3-04]`
5. Do NOT push
