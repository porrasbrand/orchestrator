# Phase 02: Merge Orchestration

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 5 Phase 01 just added `scripts/parallel-dispatch.sh`: identifies ready phases via dag.sh, creates phase branches via branch.sh, outputs JSON dispatch plan with round-robin worker assignments. The script prepares parallel work but doesn't queue or merge.

After parallel phases complete on separate branches, someone needs to merge them back to main in the correct order. `scripts/branch.sh merge` handles a single branch, but doesn't know about dependency ordering or how to merge multiple branches safely.

## Objective
Create `scripts/merge-phases.sh` that merges multiple completed phase branches back to main in topological dependency order, with conflict detection and rollback capability.

## Implementation Steps

1. **Create `scripts/merge-phases.sh`**:
   ```
   Usage: merge-phases.sh <project-path> [worker]
   ```

   The script should:
   a. Read status.json to find all phases with status "complete" that still have an unmerged `phase/<name>` branch
   b. Use dag.sh dependency info to determine merge order (phases with no deps merge first)
   c. For each phase in order:
      - Run `branch.sh merge <project-path> <phase-name> [worker]`
      - If merge succeeds: log success, continue to next
      - If merge fails (conflict): STOP immediately, report which phase caused conflict, exit 1
   d. Output a merge report:
      ```
      Merge Report:
        ✅ 02-dependency-dag      — merged to master
        ✅ 03-branch-per-phase    — merged to master
        ✅ 04-status-web-page     — merged to master
      
      All 3 branches merged successfully.
      ```
   e. If no branches to merge: output "No phase branches to merge."

2. **Conflict handling:**
   - On conflict: print the conflicting phase name and affected files
   - Do NOT auto-resolve — exit 1 for manual intervention
   - Already-merged branches (no `phase/` branch exists) are silently skipped

3. **The script works locally by default** — If worker arg provided, runs git commands via SSH on that worker.

4. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 5 item 5.2 as done.

## Files to Create
- `scripts/merge-phases.sh` — Multi-branch merge orchestrator (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 5.2 as done

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/merge-phases.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/02-merge-orchestration/result.md` (create)
- `.planning/phases/02-merge-orchestration/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/merge-phases.sh` is executable
- [ ] Reads status.json to find completed phases with unmerged branches
- [ ] Merges in dependency order (no-dep phases first)
- [ ] Uses branch.sh merge for each branch
- [ ] Stops on first conflict with clear error message
- [ ] Handles "no branches to merge" gracefully
- [ ] Works locally (no worker arg) for testing
- [ ] Output shows merge report with per-phase status
- [ ] ENHANCEMENT-ROADMAP.md shows 5.2 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/merge-phases.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/merge-phases.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep -i "no.*branch\|merge"` → expect match (either "no branches" or merge report)
3. Test with actual branches: `cd ~/awsc-new/awesome/orchestrator && git checkout -b phase/test-merge-a master && echo "a" > /tmp/merge-test-a.txt && git add /tmp/merge-test-a.txt 2>/dev/null; git checkout master && git checkout -b phase/test-merge-b master && echo "b" > /tmp/merge-test-b.txt && git add /tmp/merge-test-b.txt 2>/dev/null; git checkout master && bash scripts/branch.sh list ~/awsc-new/awesome/orchestrator 2>&1 | grep -c "test-merge"` → expect `2`
4. `cd ~/awsc-new/awesome/orchestrator && git branch | grep 'phase/test-merge' | xargs -I{} git branch -D {} 2>/dev/null; echo CLEANED`
5. `grep "5.2" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. End on master branch, clean up any test branches
3. Write result.json alongside result.md
4. Write result to: `.planning/phases/02-merge-orchestration/result.md`
5. Commit with prefix: `[orchestrator-sprint5-02]`
6. Do NOT push
