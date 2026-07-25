# Phase 04: Parallel Regression Testing

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 5 — three phases complete:
- **Phase 01 (parallel-dispatch):** `scripts/parallel-dispatch.sh` identifies ready phases via dag.sh, creates branches, outputs JSON dispatch plan using select-worker.sh.
- **Phase 02 (merge-orchestration):** `scripts/merge-phases.sh` merges completed phase branches in dependency order, stops on conflicts.
- **Phase 03 (worker-load-balancing):** `scripts/select-worker.sh` checks SSH reachability + busy lock to pick least-busy worker. parallel-dispatch.sh updated to use it.

After parallel phases are merged, we need to verify nothing broke. The current verify.sh runs smoke tests for ONE phase. We need a script that runs ALL previous smoke tests as one batch — a full regression suite after merging parallel work.

## Objective
Create `scripts/regression-test.sh` that collects smoke tests from all completed phase specs and runs them as one batch, reporting overall pass/fail. Also mark Sprint 5 and the entire enhancement roadmap as complete.

## Implementation Steps

1. **Create `scripts/regression-test.sh`**:
   ```
   Usage: regression-test.sh <project-path> [worker]
   ```

   The script should:
   a. Read status.json to find all completed phases
   b. For each completed phase, read its spec.md and extract smoke test commands (reuse the same parsing logic from verify.sh)
   c. Also check for `smoke-tests.sh` scripts in phase dirs (Phase 02 of Sprint 3 added this)
   d. Run all tests in sequence on the worker (or locally)
   e. Output a regression report:
      ```
      Regression Test Suite
      =====================
      
      Phase 01-worker-registry:
        ✅ Test 1: config exists
        ✅ Test 2: get-worker executable
        Tests: 2/2 passed
      
      Phase 02-dependency-dag:
        ✅ Test 1: dag executable
        Tests: 1/1 passed
      
      ...
      
      =====================
      Total: 15/15 passed
      Result: ALL PASS
      ```
   f. Exit 0 if all pass, exit 1 if any fail
   g. If no completed phases found: print "No completed phases to test" and exit 0

2. **For smoke-tests.sh scripts:** If `<phase-dir>/smoke-tests.sh` exists, run it instead of parsing spec.md. Same priority as verify.sh Step 1.7.

3. **For markdown smoke tests:** Reuse the same `→ expect` / `-> expect` parsing that verify.sh uses. Extract from `## Smoke Tests` section.

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 5 item 5.4 as done AND mark Sprint 5 overall as COMPLETE. Also add a final note that all 5 sprints are complete.

## Files to Create
- `scripts/regression-test.sh` — Full regression test runner (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 5.4 done, Sprint 5 complete, all sprints complete

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/regression-test.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/04-parallel-regression/result.md` (create)
- `.planning/phases/04-parallel-regression/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/regression-test.sh` is executable
- [ ] Reads status.json for completed phases
- [ ] Runs smoke tests from each completed phase spec
- [ ] Supports smoke-tests.sh scripts (priority over markdown)
- [ ] Shows per-phase test results
- [ ] Shows total pass/fail count
- [ ] Exit 0 on all pass, exit 1 on any fail
- [ ] Handles no completed phases gracefully
- [ ] ENHANCEMENT-ROADMAP.md shows 5.4 done, Sprint 5 complete, all sprints done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/regression-test.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/regression-test.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep -i "regression\|total"` → expect match
3. `bash ~/awsc-new/awesome/orchestrator/scripts/regression-test.sh ~/awsc-new/awesome/orchestrator 2>&1 | tail -3` → expect summary with pass count
4. `grep "5.4" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match
5. `grep -i "sprint 5.*complete\|sprint 5.*done\|sprint 5.*✅" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md` → expect match
6. `grep -i "all.*sprint.*complete\|roadmap.*complete\|5/5.*sprint" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/04-parallel-regression/result.md`
4. Commit with prefix: `[orchestrator-sprint5-04]`
5. Do NOT push
