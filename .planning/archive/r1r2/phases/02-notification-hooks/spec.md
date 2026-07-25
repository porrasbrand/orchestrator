# Phase 02: Notification Hooks
# Template: new-bash-script
# REQUIRED_VARS: filled

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprints 1-6 complete (23 enhancements). The orchestrator runs autonomously — phases are queued, workers execute, verify.sh checks results. But the PM (orchestrator on lipo-360) has NO way to know when something completes or fails except by manually checking. There are no notifications.

Currently:
- Phase completes → PM must SSH or check response manually
- Verification fails → PM discovers it next time they look
- Regression test breaks → no alert until PM checks

The orchestrator already logs events to `.planning/events.jsonl`. What's missing is a **notification layer** that reacts to events and alerts the PM.

## Objective
Create `scripts/notify.sh` — a notification script that the orchestrator calls after significant events (phase complete, verification failed, regression failed, project complete). It writes notifications to a file and optionally executes a user-configurable hook command.

## Implementation Steps

1. **Create `scripts/notify.sh`:**
   ```
   Usage: notify.sh <event-type> <project-path> [--phase <name>] [--detail <message>]
   
   Event types: phase_complete, phase_failed, verification_failed, regression_failed, project_complete
   ```

2. **Notification output (always):**
   - Append a timestamped line to `<project-path>/.planning/notifications.md`:
     ```
     ## [2026-04-15 07:30:00] Phase Complete: 01-verify-error-clarity
     All 10 smoke tests passed. Commit: abc1234.
     ```
   - Write latest notification to `<project-path>/.planning/latest-notification.json`:
     ```json
     {
       "timestamp": "2026-04-15T07:30:00Z",
       "event": "phase_complete",
       "phase": "01-verify-error-clarity",
       "detail": "All 10 smoke tests passed. Commit: abc1234.",
       "project": "orchestrator-sprint7"
     }
     ```

3. **Hook command (optional):**
   - If `config/notify-hook.sh` exists and is executable, run it with the event JSON piped to stdin.
   - This lets users plug in Slack webhooks, email alerts, desktop notifications, etc. without modifying notify.sh.
   - If hook doesn't exist, just skip silently (no error).
   - If hook fails (non-zero exit), log warning but don't block.

4. **Create `config/notify-hook.sh.example`:**
   - Example hook that prints to terminal and writes to a log file
   - Comments showing how to add Slack webhook, email, etc.
   - NOT executable by default (it's a template)

5. **Notification formatting per event type:**
   - `phase_complete`: "✅ Phase <name> complete. <tests_passed> tests passed. Commit: <hash>."
   - `phase_failed`: "❌ Phase <name> failed after <revisions> revisions. Escalating to user."
   - `verification_failed`: "⚠️ Phase <name> verification failed. <fail_count> of <total> tests failed. See verification-report.json."
   - `regression_failed`: "🔴 Regression failure after merging <name>. <fail_count> previous tests broken."
   - `project_complete`: "🎉 Project <name> complete! <phases_total> phases, <total_revisions> total revisions."

6. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 7 item 7.2 as done.

## Files to Create
- `scripts/notify.sh` — Notification engine (make executable)
- `config/notify-hook.sh.example` — Example hook template (NOT executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 7.2 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- `scripts/verify.sh`, `scripts/init.sh`, `scripts/dag.sh`, and all other existing scripts
- `templates/`
- `.planning/` (except notifications.md which is the output target)
- `config/workers.json`

## Expected Files Changed
- `scripts/notify.sh` (create)
- `config/notify-hook.sh.example` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-notification-hooks/result.md` (create)
- `.planning/phases/02-notification-hooks/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/notify.sh` exists and is executable
- [ ] Prints usage when called with no args
- [ ] Appends formatted notification to `<project>/.planning/notifications.md`
- [ ] Writes latest notification JSON to `<project>/.planning/latest-notification.json`
- [ ] latest-notification.json is valid JSON (parseable by jq)
- [ ] If `config/notify-hook.sh` exists and is executable, it gets called with JSON on stdin
- [ ] If hook doesn't exist, notify.sh still succeeds (no error)
- [ ] If hook fails, notify.sh warns but exits 0 (non-blocking)
- [ ] `config/notify-hook.sh.example` exists with documentation comments
- [ ] All 5 event types produce appropriate formatted messages
- [ ] ENHANCEMENT-ROADMAP.md has Sprint 7 with 7.2 marked done

## Smoke Tests
```bash
# 1. File exists and is executable
test -x ~/awsc-new/awesome/orchestrator/scripts/notify.sh && echo EXECUTABLE

# 2. Usage on no args
bash ~/awsc-new/awesome/orchestrator/scripts/notify.sh 2>&1 | grep -i "usage" && echo USAGE_OK

# 3. phase_complete notification writes to notifications.md
bash ~/awsc-new/awesome/orchestrator/scripts/notify.sh phase_complete ~/awsc-new/awesome/orchestrator --phase test-phase --detail "5 tests passed" && grep "test-phase" ~/awsc-new/awesome/orchestrator/.planning/notifications.md && echo NOTIFY_OK

# 4. latest-notification.json is valid JSON
jq . ~/awsc-new/awesome/orchestrator/.planning/latest-notification.json > /dev/null 2>&1 && echo JSON_VALID

# 5. latest-notification.json has correct event type
jq -r '.event' ~/awsc-new/awesome/orchestrator/.planning/latest-notification.json | grep "phase_complete" && echo EVENT_OK

# 6. Hook example exists
test -f ~/awsc-new/awesome/orchestrator/config/notify-hook.sh.example && echo EXAMPLE_EXISTS

# 7. notify.sh works without hook (no error)
rm -f ~/awsc-new/awesome/orchestrator/config/notify-hook.sh && bash ~/awsc-new/awesome/orchestrator/scripts/notify.sh verification_failed ~/awsc-new/awesome/orchestrator --phase test-fail --detail "3 of 8 failed" && echo NO_HOOK_OK

# 8. Sprint 7 in roadmap
grep "Sprint 7" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md

# 9. 7.2 marked done
grep "7.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"

# 10. Cleanup test data from notifications.md
sed -i '/test-phase\|test-fail/d' ~/awsc-new/awesome/orchestrator/.planning/notifications.md && echo CLEANED
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write result.json alongside result.md (see templates/result-schema.md for schema)
3. Write result to: `.planning/phases/02-notification-hooks/result.md`
4. Commit all changes with prefix: `[orchestrator-sprint7-02]`
5. Do NOT push
