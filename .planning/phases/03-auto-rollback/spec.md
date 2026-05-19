# Phase 03: Auto-Rollback on Regression Failure
# Template: new-bash-script
# REQUIRED_VARS: filled

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 7 Phase 01 improved verify.sh with:
- Contextual error messages (expected/actual/suggestion for every failure type)
- Failure summary block listing all failures with fix suggestions
- Suggested revision notes (copy-paste for revision specs)
- verification-report.json written to phase dir (machine-readable)

Sprint 7 Phase 02 added notify.sh:
- Notification engine for phase events (complete, failed, verification_failed, regression_failed, project_complete)
- Writes to notifications.md + latest-notification.json
- Optional hook command via config/notify-hook.sh

Sprint 5 added parallel execution: phases run on branches, merge-phases.sh merges in dependency order, regression-test.sh runs all prior smoke tests after merge. **BUT: if regression tests fail after a merge, the current behavior is just to exit 1.** The merged code stays on main — broken. The PM must manually investigate and revert.

Current `scripts/merge-phases.sh` (159 lines): merges phase branches in topological order, fails fast on merge conflict, but has NO rollback capability.

Current `scripts/regression-test.sh` (140 lines): runs ALL smoke tests from ALL completed phases, counts pass/fail, exits 0 or 1. No rollback.

## Objective
Create `scripts/auto-rollback.sh` that integrates with merge-phases.sh and regression-test.sh. When regression tests fail after a merge, it automatically reverts the last merged branch, sends a notification, and updates status.json.

## Implementation Steps

1. **Create `scripts/auto-rollback.sh`:**
   ```
   Usage: auto-rollback.sh <worker> <project-path>
   
   Flow:
   1. Read .planning/status.json to find recently merged phases
   2. Run regression-test.sh
   3. If regression passes → exit 0, notify project healthy
   4. If regression fails → identify last merged phase, revert it:
      a. git revert --no-commit <merge-commit>
      b. git commit -m "Auto-rollback: <phase-name> broke regression tests"
      c. Update status.json: set phase status to "rolled_back"
      d. Log event to events.jsonl: "phase_rolled_back"
      e. Call notify.sh regression_failed with details
      f. Exit 1
   ```

2. **Key design decisions:**
   - Revert only the LAST merged phase (not all — that would be catastrophic)
   - Use `git revert` (not `git reset`) — preserves history, safe on shared branches
   - The rolled-back phase goes back to "specified" status so the PM can write a revision spec
   - If the revert itself fails (conflict), DON'T force it — exit 2 and escalate to PM
   - Always notify via notify.sh (Phase 02 output)
   - Always write events to events.jsonl

3. **Detect last merged phase:**
   - Read events.jsonl, find the most recent `phase_merged` event
   - Extract commit hash and phase name from that event
   - If no recent merge found, exit with "nothing to rollback"

4. **Integration with existing scripts:**
   - auto-rollback.sh calls `regression-test.sh` internally (don't duplicate logic)
   - auto-rollback.sh calls `notify.sh` for notifications (don't duplicate)
   - auto-rollback.sh reads `config/workers.json` via `get-worker.sh` for SSH
   - All SSH commands use the existing ssh_retry pattern (copy from verify.sh or source it)

5. **Status.json updates:**
   - New phase status value: `"rolled_back"`
   - Add `rolled_back_at` timestamp to the phase
   - Add `rollback_commit` to the phase

6. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 7 item 7.3 as done.

## Files to Create
- `scripts/auto-rollback.sh` — Auto-rollback engine (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 7.3 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/verify.sh` (Phase 01 already modified it)
- `scripts/notify.sh` (Phase 02 already created it)
- `scripts/merge-phases.sh` (auto-rollback.sh calls it, doesn't modify it)
- `scripts/regression-test.sh` (auto-rollback.sh calls it, doesn't modify it)
- `templates/`, `config/workers.json`

## Expected Files Changed
- `scripts/auto-rollback.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/03-auto-rollback/result.md` (create)
- `.planning/phases/03-auto-rollback/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/auto-rollback.sh` exists and is executable
- [ ] Prints usage when called with no args or --help
- [ ] Calls regression-test.sh to check current state
- [ ] If regression passes, exits 0 with "healthy" message
- [ ] If regression fails, identifies last merged phase from events.jsonl
- [ ] Uses `git revert` (not `git reset`) for safe rollback
- [ ] Updates status.json with "rolled_back" status + timestamp + commit
- [ ] Logs "phase_rolled_back" event to events.jsonl
- [ ] Calls notify.sh with regression_failed event
- [ ] If revert conflicts, exits 2 with escalation message (doesn't force)
- [ ] If no recent merge found, exits with clear "nothing to rollback" message
- [ ] ENHANCEMENT-ROADMAP.md has Sprint 7 with 7.3 marked done

## Smoke Tests
```bash
# 1. File exists and is executable
test -x ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo EXECUTABLE

# 2. Usage on no args
bash ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh 2>&1 | grep -i "usage" && echo USAGE_OK

# 3. References regression-test.sh (doesn't duplicate)
grep "regression-test.sh" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo CALLS_REGRESSION

# 4. References notify.sh (uses notification system)
grep "notify.sh" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo CALLS_NOTIFY

# 5. Uses git revert (not git reset)
grep "git revert" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo USES_REVERT

# 6. Handles "rolled_back" status
grep "rolled_back" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo HAS_STATUS

# 7. References events.jsonl for reading merge history
grep "events.jsonl\|EVENTS_FILE" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh | head -1 && echo READS_EVENTS

# 8. Has escalation path (exit 2 for revert conflicts)
grep "exit 2" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo HAS_ESCALATION

# 9. Sprint 7.3 in roadmap marked done
grep "7.3" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"

# 10. get-worker.sh referenced (uses worker registry)
grep "get-worker" ~/awsc-new/awesome/orchestrator/scripts/auto-rollback.sh && echo USES_REGISTRY
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write result.json alongside result.md (see templates/result-schema.md for schema)
3. Write result to: `.planning/phases/03-auto-rollback/result.md`
4. Commit all changes with prefix: `[orchestrator-sprint7-03]`
5. Do NOT push
