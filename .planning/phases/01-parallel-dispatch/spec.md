# Phase 01: Parallel Dispatch

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprints 1-4 complete (17 enhancements). Key tools this phase builds on:
- `scripts/dag.sh` — Reads status.json, identifies ready-to-run phases and parallel groups
- `scripts/branch.sh` — Creates/merges/lists phase branches (create/merge/list subcommands)
- `scripts/get-worker.sh` — Reads worker config from `config/workers.json`
- `config/workers.json` — Registry with hetzner and wsl2 workers (host, port, user, ssh_key, capabilities, status)

Currently the orchestrator dispatches one phase at a time. This script enables dispatching multiple independent phases simultaneously.

## Objective
Create `scripts/parallel-dispatch.sh` that identifies all ready-to-run phases (using dag.sh), creates a phase branch for each (using branch.sh), and outputs the dispatch plan. The script prepares everything for parallel queuing but does NOT actually queue tasks (the orchestrator does that part via add-task.sh).

## Implementation Steps

1. **Create `scripts/parallel-dispatch.sh`**:
   ```
   Usage: parallel-dispatch.sh <project-path> [worker]
   ```

   The script should:
   a. Run `dag.sh` to identify ready-to-run phases
   b. For each ready phase, run `branch.sh create` to create a phase branch (on the worker via SSH if worker specified, locally otherwise)
   c. Output a dispatch plan as JSON to stdout:
      ```json
      {
        "ready_phases": ["02-dependency-dag", "03-branch-per-phase", "04-status-web-page"],
        "branches_created": ["phase/02-dependency-dag", "phase/03-branch-per-phase", "phase/04-status-web-page"],
        "suggested_assignments": {
          "02-dependency-dag": "hetzner",
          "03-branch-per-phase": "wsl2",
          "04-status-web-page": "hetzner"
        }
      }
      ```
   d. If no phases are ready, output `{"ready_phases":[],"branches_created":[],"suggested_assignments":{}}`
   e. If only 1 phase is ready, still output it (parallel dispatch with 1 phase = sequential)

2. **Worker assignment logic (simple round-robin for now):**
   - Read active workers from `config/workers.json` (status = "active")
   - Assign phases round-robin across active workers
   - This is a placeholder — Phase 03 will add smarter load balancing

3. **The dispatch plan is informational** — The orchestrator reads the JSON output and decides what to actually queue. The script doesn't call add-task.sh itself.

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 5 item 5.1 as done.

## Files to Create
- `scripts/parallel-dispatch.sh` — Parallel dispatch planner (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 5.1 as done

## Do NOT Touch
- All other scripts (dag.sh, branch.sh, get-worker.sh, verify.sh, etc.)
- config/workers.json
- templates/

## Expected Files Changed
- `scripts/parallel-dispatch.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/01-parallel-dispatch/result.md` (create)
- `.planning/phases/01-parallel-dispatch/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/parallel-dispatch.sh` is executable
- [ ] Uses dag.sh to find ready phases
- [ ] Creates phase branches for each ready phase (uses branch.sh)
- [ ] Outputs valid JSON dispatch plan to stdout
- [ ] Round-robin assigns phases to active workers
- [ ] Handles 0 ready phases (empty output)
- [ ] Handles 1 ready phase (single-element arrays)
- [ ] Does NOT queue tasks itself (output only)
- [ ] ENHANCEMENT-ROADMAP.md shows 5.1 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/parallel-dispatch.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/parallel-dispatch.sh ~/awsc-new/awesome/orchestrator 2>/dev/null | jq -r '.ready_phases | length'` → expect a number (0 or more)
3. `bash ~/awsc-new/awesome/orchestrator/scripts/parallel-dispatch.sh ~/awsc-new/awesome/orchestrator 2>/dev/null | jq -r 'has("ready_phases") and has("branches_created") and has("suggested_assignments")'` → expect `true`
4. `bash ~/awsc-new/awesome/orchestrator/scripts/parallel-dispatch.sh ~/awsc-new/awesome/orchestrator 2>/dev/null | jq '.' >/dev/null 2>&1 && echo VALID_JSON` → expect `VALID_JSON`
5. `grep "5.1" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match
6. Clean up any test branches: `cd ~/awsc-new/awesome/orchestrator && git checkout master 2>/dev/null; git branch | grep 'phase/' | xargs -I{} git branch -D {} 2>/dev/null; echo CLEANED`

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Make sure you end on master branch with no leftover phase branches
3. Write result.json alongside result.md
4. Write result to: `.planning/phases/01-parallel-dispatch/result.md`
5. Commit with prefix: `[orchestrator-sprint5-01]`
6. Do NOT push
