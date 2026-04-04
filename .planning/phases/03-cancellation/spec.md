# Phase 03: Cancellation Mechanism

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 3 progress so far:
- **Phase 01 (structured-results):** Added result.json schema + template. verify.sh reads JSON results with jq when present, falls back to result.md.
- **Phase 02 (executable-smoke-tests):** Added smoke-tests.sh support. verify.sh runs executable scripts when found in phase dir, falls back to markdown parsing. Template at templates/smoke-tests-template.sh.

The orchestrator currently has no way to cancel a phase once it's been queued. If you realize a spec is wrong after queuing, the DEV worker completes the entire phase with a bad spec before you can intervene. This wastes a full dispatch-implement-verify cycle.

## Objective
Create a `scripts/cancel-task.sh` script that marks a queued phase as CANCELLED in the local orchestration state (events.jsonl + status.json). This allows the orchestrator to skip verification when the response eventually arrives.

## Implementation Steps

1. **Create `scripts/cancel-task.sh`** that takes a project path and phase name:
   ```
   Usage: cancel-task.sh <project-path> <phase-name>
   Example: cancel-task.sh /home/mp/awesome/blog-publisher 03-images
   ```
   
   The script should:
   - Verify the phase exists in status.json
   - Verify the phase is currently in "queued" status (can't cancel pending/complete/etc.)
   - Update status.json: set phase status to "cancelled"
   - Append event to events.jsonl: `{"event":"phase_cancelled","data":{"phase":"03-images","reason":"manual"}}`
   - Print confirmation message
   - Exit 0 on success, 1 on error (phase not found, wrong status, etc.)

2. **The script should use `jq` for JSON manipulation** — read status.json, modify the phase status, write back. This avoids sed-based JSON editing.

3. **Add CANCELLED to the phase lifecycle documentation** — Update status.json to recognize "cancelled" as a valid terminal state (like "complete" or "revision_failed").

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 3 item 3.3 as done.

## Files to Create
- `scripts/cancel-task.sh` — Cancellation script (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 3.3 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/verify.sh` (no changes needed — cancelled phases won't reach verification)
- `scripts/init.sh`, `scripts/scan.sh`, `scripts/status.sh`
- `scripts/update-learnings.sh`, `scripts/check-spec.sh`
- `templates/` (no template changes)

## Expected Files Changed
- `scripts/cancel-task.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/03-cancellation/result.md` (create)
- `.planning/phases/03-cancellation/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/cancel-task.sh` is executable
- [ ] Cancels a phase in "queued" status (updates status.json + appends events.jsonl)
- [ ] Refuses to cancel a phase not in "queued" status (prints error, exits 1)
- [ ] Refuses to cancel a non-existent phase (prints error, exits 1)
- [ ] Uses jq for JSON read/modify/write (no sed on JSON)
- [ ] Events.jsonl gets `phase_cancelled` event with phase name
- [ ] ENHANCEMENT-ROADMAP.md shows 3.3 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/cancel-task.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. Set up a test: `bash ~/awsc-new/awesome/orchestrator/scripts/init.sh /tmp/test-cancel && echo '{"project":"test","phases":{"01-test":{"status":"queued"}},"execution_order":["01-test"],"metrics":{}}' > /tmp/test-cancel/.planning/status.json && bash ~/awsc-new/awesome/orchestrator/scripts/cancel-task.sh /tmp/test-cancel 01-test; echo "EXIT:$?"` → expect `EXIT:0`
3. `cat /tmp/test-cancel/.planning/status.json | jq -r '.phases["01-test"].status'` → expect `cancelled`
4. `cat /tmp/test-cancel/.planning/events.jsonl | grep phase_cancelled | jq -r '.event'` → expect `phase_cancelled`
5. `bash ~/awsc-new/awesome/orchestrator/scripts/cancel-task.sh /tmp/test-cancel 01-test 2>&1; echo "EXIT:$?"` → expect `EXIT:1` (already cancelled, not queued)
6. `bash ~/awsc-new/awesome/orchestrator/scripts/cancel-task.sh /tmp/test-cancel 99-nonexistent 2>&1; echo "EXIT:$?"` → expect `EXIT:1` (phase doesn't exist)
7. `rm -rf /tmp/test-cancel`

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/03-cancellation/result.md`
4. Commit with prefix: `[orchestrator-sprint3-03]`
5. Do NOT push
