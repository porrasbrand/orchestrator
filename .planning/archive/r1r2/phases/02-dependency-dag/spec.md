# Phase 02: Dependency DAG

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 4 Phase 01 just added a worker registry: `config/workers.json` with hetzner/wsl2 definitions, `scripts/get-worker.sh` for reading config, and verify.sh now reads from registry instead of hardcoded if/else.

The orchestrator tracks phase dependencies in `status.json` via `depends_on` arrays, but has no tooling to analyze these dependencies. The orchestrator (human) must manually determine which phases can run in parallel. Sprint 5 will add actual parallel execution — this phase builds the analysis tool it needs.

## Objective
Create a `scripts/dag.sh` script that reads status.json and analyzes phase dependencies to identify which phases can run in parallel. It outputs: dependency visualization, ready-to-run phases, and critical path.

## Implementation Steps

1. **Create `scripts/dag.sh`** that takes a project path:
   ```
   Usage: dag.sh <project-path>
   ```

   The script reads `.planning/status.json` and outputs:

   **Section 1: Dependency Graph**
   ```
   Phase Dependencies:
     01-worker-registry    → (none)
     02-dependency-dag     → (none)
     03-branch-per-phase   → (none)
     04-status-web-page    → (none)
     05-cost-tracking      → 04-status-web-page
   ```

   **Section 2: Ready to Run**
   Phases whose status is "pending" AND all dependencies are "complete":
   ```
   Ready to run (can execute in parallel):
     02-dependency-dag
     03-branch-per-phase
     04-status-web-page
   ```

   **Section 3: Parallel Groups**
   Group phases by dependency level (0 = no deps, 1 = depends on level 0, etc.):
   ```
   Parallel groups:
     Level 0: 01-worker-registry, 02-dependency-dag, 03-branch-per-phase, 04-status-web-page
     Level 1: 05-cost-tracking (after: 04-status-web-page)
   ```

   **Section 4: Summary**
   ```
   Total phases: 5
   Complete: 1
   Ready: 3
   Blocked: 1
   Min sequential steps: 2 (with parallel execution)
   ```

2. **Use `jq` for all JSON parsing** — read status.json, extract phases, depends_on, status fields.

3. **Handle edge cases:**
   - Phase with no depends_on → level 0
   - Phase with all deps complete → ready
   - Phase already complete → skip in "ready" list
   - Circular dependencies → detect and warn (shouldn't happen but be safe)

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 4 item 4.2 as done.

## Files to Create
- `scripts/dag.sh` — Dependency analysis script (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 4.2 as done

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/dag.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-dependency-dag/result.md` (create)
- `.planning/phases/02-dependency-dag/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/dag.sh` is executable
- [ ] Shows dependency graph for all phases
- [ ] Identifies "ready to run" phases (pending + deps complete)
- [ ] Groups phases by parallel level
- [ ] Shows summary with counts
- [ ] Works with current Sprint 4 status.json (has real dependency data)
- [ ] Handles phases with no dependencies
- [ ] Handles phases with unmet dependencies
- [ ] ENHANCEMENT-ROADMAP.md shows 4.2 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/dag.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/dag.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep -c "Phase Dependencies\|Ready to run\|Parallel groups\|Summary"` → expect `4` (all 4 sections present)
3. `bash ~/awsc-new/awesome/orchestrator/scripts/dag.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep "05-cost-tracking" | head -1` → expect line showing dependency on 04
4. `bash ~/awsc-new/awesome/orchestrator/scripts/dag.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep "Ready"` → expect at least one ready phase listed
5. `bash ~/awsc-new/awesome/orchestrator/scripts/dag.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep "Total phases"` → expect `5`
6. `grep "4.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/02-dependency-dag/result.md`
4. Commit with prefix: `[orchestrator-sprint4-02]`
5. Do NOT push
