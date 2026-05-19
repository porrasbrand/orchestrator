# Phase 01: Integration Test Suite
# Template: new-bash-script
# REQUIRED_VARS: filled

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 7 added 3 interconnected scripts:
- `scripts/verify.sh` (413 lines) — verification engine. Now writes `verification-report.json`, contextual error messages, failure summaries, suggested revision notes.
- `scripts/notify.sh` (160 lines) — notification engine. 5 event types, writes `notifications.md` + `latest-notification.json`, optional hook via `config/notify-hook.sh`.
- `scripts/auto-rollback.sh` (293 lines) — auto-rollback on regression failure. Reads events.jsonl for last merge, calls regression-test.sh, reverts via `git revert`, updates status.json, calls notify.sh.

Each script passed 10 structural smoke tests individually. But they've **never been tested as a chain** — verify failure → notification → rollback. If there's a bug in the handoff between scripts, we won't find it until a real failure.

Also involved:
- `scripts/regression-test.sh` (140 lines) — runs all smoke tests from all completed phases
- `scripts/get-worker.sh` (58 lines) — reads worker config from config/workers.json
- `scripts/merge-phases.sh` (159 lines) — merges phase branches in dependency order

## Objective
Create `scripts/integration-test.sh` that tests the verify → notify → rollback chain end-to-end using a mock project environment. Uses mock SSH (PATH override) for deterministic, fast testing — no real SSH, no network dependency.

## Implementation Steps

1. **Create `scripts/integration-test.sh`** (executable):

2. **Test setup (runs before each scenario):**
   - Create `/tmp/orchestrator-integration-test/` as a mock project
   - Initialize git repo in it
   - Create `.planning/` structure: status.json, events.jsonl, notifications.md, learnings.jsonl
   - Create mock phase dirs with spec.md, result.md, result.json
   - Create a `mock-ssh` script that returns canned responses based on arguments
   - Override PATH so `ssh` resolves to mock-ssh
   - Create a mock `get-worker.sh` response for the test worker

3. **Scenario 1: Verify passes → notification sent**
   - Set up mock-ssh to return passing smoke test results
   - Run verify.sh with test worker, test project, test phase
   - Assert: exit code 0
   - Assert: verification-report.json exists and has `"verified": true`
   - Run notify.sh phase_complete with test project
   - Assert: notifications.md has entry
   - Assert: latest-notification.json has `"event": "phase_complete"`

4. **Scenario 2: Verify fails → failure report + notification**
   - Set up mock-ssh to return failing smoke test results
   - Run verify.sh
   - Assert: exit code 1
   - Assert: verification-report.json has `"verified": false` and non-empty `failures` array
   - Assert: "Failure Summary" appears in stdout
   - Assert: "Suggested Revision Notes" appears in stdout
   - Run notify.sh verification_failed
   - Assert: latest-notification.json has `"event": "verification_failed"`

5. **Scenario 3: Regression failure → auto-rollback**
   - Set up mock project with a recent `phase_merged` event in events.jsonl
   - Create a git history with a merge commit to revert
   - Set up mock-ssh so regression-test.sh returns failure
   - Run auto-rollback.sh
   - Assert: git log shows a revert commit
   - Assert: status.json has `"rolled_back"` status for the phase
   - Assert: events.jsonl has `"phase_rolled_back"` event
   - Assert: notify.sh was called (check notifications.md for regression_failed entry)

6. **Scenario 4: Auto-rollback with no recent merge**
   - Empty events.jsonl (no phase_merged events)
   - Run auto-rollback.sh
   - Assert: exits with "nothing to rollback" message
   - Assert: no git changes

7. **Test teardown:** Remove `/tmp/orchestrator-integration-test/` after all scenarios.

8. **Output format:**
   ```
   === Orchestrator Integration Test Suite ===
   
   Scenario 1: Verify pass → notify ... ✅ PASS
   Scenario 2: Verify fail → report  ... ✅ PASS  
   Scenario 3: Regression → rollback ... ✅ PASS
   Scenario 4: No merge → no-op     ... ✅ PASS
   
   Results: 4/4 passed
   ```

9. **Important: mock-ssh approach.**
   Create `/tmp/orchestrator-integration-test/bin/mock-ssh` that:
   - Logs all calls to `/tmp/orchestrator-integration-test/ssh-calls.log`
   - Inspects the command argument to determine response:
     - `test -f */result.md` → echo "YES" or "NO" based on scenario
     - `test -x */smoke-tests.sh` → echo "YES" or "NO"
     - `cat */result.json` → output mock result JSON
     - `git diff --name-only` → output mock file list
     - `cd * && bash */smoke-tests.sh` → output mock pass/fail lines
   - Prepend `/tmp/orchestrator-integration-test/bin` to PATH before running tests

10. **Update `ENHANCEMENT-ROADMAP.md`** — Add Sprint 8 section with 8.1 marked done.

## Files to Create
- `scripts/integration-test.sh` — Integration test suite (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Add Sprint 8, mark 8.1 done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- All existing scripts (verify.sh, notify.sh, auto-rollback.sh, etc.)
- `templates/`, `config/`
- `.planning/` (except events.jsonl via normal logging)

## Expected Files Changed
- `scripts/integration-test.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/01-integration-test/result.md` (create)
- `.planning/phases/01-integration-test/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/integration-test.sh` exists and is executable
- [ ] Creates mock project in /tmp (no real SSH needed)
- [ ] Mock-ssh intercepts SSH calls and returns canned responses
- [ ] Scenario 1: verify pass → notification chain works
- [ ] Scenario 2: verify fail → failure report + notification chain works
- [ ] Scenario 3: regression failure → auto-rollback chain works
- [ ] Scenario 4: no merge → graceful no-op
- [ ] All 4 scenarios pass when run
- [ ] Cleans up /tmp after test
- [ ] ENHANCEMENT-ROADMAP.md has Sprint 8 with 8.1 marked done

## Smoke Tests
```bash
# 1. File exists and executable
test -x ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo EXECUTABLE

# 2. Contains all 4 scenarios
grep -c "Scenario" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh | awk '{print ($1 >= 4) ? "HAS_SCENARIOS" : "TOO_FEW"}'

# 3. Creates mock-ssh
grep "mock-ssh" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo HAS_MOCK

# 4. References verify.sh
grep "verify.sh" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo TESTS_VERIFY

# 5. References notify.sh
grep "notify.sh" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo TESTS_NOTIFY

# 6. References auto-rollback.sh
grep "auto-rollback.sh" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo TESTS_ROLLBACK

# 7. Cleans up /tmp
grep -E "rm -rf|cleanup" ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh && echo HAS_CLEANUP

# 8. Run the actual integration test
bash ~/awsc-new/awesome/orchestrator/scripts/integration-test.sh 2>&1 | tail -5

# 9. Sprint 8 in roadmap
grep "Sprint 8" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md

# 10. 8.1 marked done
grep "8.1" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. CRITICAL: Smoke test #8 actually runs the integration test — all 4 scenarios must pass
3. Write result.json alongside result.md (see templates/result-schema.md for schema)
4. Write result to: `.planning/phases/01-integration-test/result.md`
5. Commit all changes with prefix: `[orchestrator-sprint8-01]`
6. Do NOT push
