# Phase 02: Worker Failover
# Template: new-bash-script
# REQUIRED_VARS: filled

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 8 Phase 01 created `scripts/integration-test.sh` — end-to-end test suite that validates the verify → notify → rollback chain using mock SSH. 4 scenarios, all passing.

Sprint 7 added:
- verify.sh improvements (contextual errors, verification-report.json)
- notify.sh (notification engine, 5 event types, optional hooks)
- auto-rollback.sh (reverts broken merges, updates status, notifies)

Sprint 4 added:
- `config/workers.json` — worker registry (hetzner, wsl2)
- `scripts/get-worker.sh` — reads worker config
- `scripts/select-worker.sh` (46 lines) — returns least-busy worker (checks `.orchestrator-busy` lock file)

**Current problem:** If a worker goes down mid-phase (SSH timeout, crash), the phase stays "queued" forever. The PM must manually detect the timeout, cancel the phase, and re-queue to another worker. No automation.

## Objective
Create `scripts/failover.sh` that monitors a queued/in-progress phase and automatically re-queues to another worker if the current worker becomes unreachable.

## Implementation Steps

1. **Create `scripts/failover.sh`:**
   ```
   Usage: failover.sh <project-path> <phase-name> [--timeout <minutes>] [--check-only]
   
   Default timeout: 30 minutes
   --check-only: just check health, don't failover
   ```

2. **Worker health check:**
   - Read status.json to find which worker the phase was queued to (need `target_worker` field or phase-level worker field)
   - Run: `ssh -o ConnectTimeout=5 <worker> 'echo alive'` (via get-worker.sh)
   - Retry 3 times with 10-second gaps
   - If all 3 fail → worker is DOWN

3. **Timeout check:**
   - Read events.jsonl for the `phase_queued` event for this phase
   - Calculate elapsed time since queued
   - If elapsed > timeout → phase is STALE

4. **Failover logic (when worker DOWN or phase STALE):**
   - Call `select-worker.sh` to pick the next available worker (excludes the failed one)
   - If no other worker available → exit 1 with "no alternative workers" message
   - Update status.json: set phase `target_worker` to new worker, add `failover_from` and `failover_at` fields
   - Log `phase_failover` event to events.jsonl with: old_worker, new_worker, reason (down/stale)
   - Call notify.sh with a notification about the failover
   - Output the new worker name so the PM can re-queue the task
   - **Do NOT re-queue the task itself** — the PM/orchestrator does that (failover.sh just handles detection + worker selection + state update)

5. **--check-only mode:**
   - Just run health check + timeout check
   - Output: `HEALTHY`, `WORKER_DOWN`, or `PHASE_STALE`
   - Don't modify any state
   - Useful for monitoring/polling

6. **Exit codes:**
   - 0: healthy (no failover needed) OR failover completed successfully
   - 1: failover needed but no alternative workers
   - 2: error (can't read status.json, can't parse events, etc.)

7. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 8 item 8.2 as done.

## Files to Create
- `scripts/failover.sh` — Worker failover engine (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 8.2 as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- All existing scripts
- `templates/`, `config/workers.json`
- `.planning/` phases from previous sprints

## Expected Files Changed
- `scripts/failover.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-worker-failover/result.md` (create)
- `.planning/phases/02-worker-failover/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/failover.sh` exists and is executable
- [ ] Prints usage when called with no args or --help
- [ ] Reads worker assignment from status.json
- [ ] Checks worker health via SSH (3 retries, 10s gaps)
- [ ] Checks phase timeout from events.jsonl timestamps
- [ ] --check-only mode outputs HEALTHY/WORKER_DOWN/PHASE_STALE without modifying state
- [ ] On failover: updates status.json with new worker + failover metadata
- [ ] On failover: logs phase_failover event to events.jsonl
- [ ] On failover: calls notify.sh
- [ ] Uses select-worker.sh for worker selection (doesn't duplicate logic)
- [ ] Uses get-worker.sh for SSH commands (doesn't hardcode)
- [ ] Exits 1 if no alternative workers available
- [ ] ENHANCEMENT-ROADMAP.md has Sprint 8 with 8.2 marked done

## Smoke Tests
```bash
# 1. File exists and executable
test -x ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo EXECUTABLE

# 2. Usage on no args
bash ~/awsc-new/awesome/orchestrator/scripts/failover.sh 2>&1 | grep -i "usage" && echo USAGE_OK

# 3. References select-worker.sh (doesn't duplicate)
grep "select-worker.sh" ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo USES_SELECT

# 4. References get-worker.sh
grep "get-worker.sh" ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo USES_REGISTRY

# 5. References notify.sh
grep "notify.sh" ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo USES_NOTIFY

# 6. Has --check-only mode
grep "check-only\|check_only\|CHECK_ONLY" ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo HAS_CHECK_ONLY

# 7. Has 3 retry logic
grep -E "retry|retries|attempt" ~/awsc-new/awesome/orchestrator/scripts/failover.sh && echo HAS_RETRY

# 8. Handles HEALTHY/DOWN/STALE states
grep -c "HEALTHY\|WORKER_DOWN\|PHASE_STALE" ~/awsc-new/awesome/orchestrator/scripts/failover.sh | awk '{print ($1 >= 3) ? "HAS_STATES" : "MISSING"}'

# 9. Sprint 8 in roadmap
grep "Sprint 8" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md

# 10. 8.2 marked done
grep "8.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write result.json alongside result.md (see templates/result-schema.md for schema)
3. Write result to: `.planning/phases/02-worker-failover/result.md`
4. Commit all changes with prefix: `[orchestrator-sprint8-02]`
5. Do NOT push
