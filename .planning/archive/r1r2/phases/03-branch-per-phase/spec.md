# Phase 03: Branch-Per-Phase

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 4 progress:
- **Phase 01 (worker-registry):** Created `config/workers.json` + `scripts/get-worker.sh`. verify.sh reads worker config from registry.
- **Phase 02 (dependency-dag):** Created `scripts/dag.sh` that analyzes status.json dependencies, shows parallel groups, ready-to-run phases, and summary stats.

Currently all phases commit directly to the main branch. When Sprint 5 adds parallel execution, multiple workers committing to the same branch will cause merge conflicts. Branch-per-phase isolates work so each phase has its own branch, merged after verification.

## Objective
Create a `scripts/branch.sh` helper script that manages phase branches: creating a branch for a phase before queuing, and merging it back to main after verification passes. This is opt-in tooling — the orchestrator can choose to use it or not.

## Implementation Steps

1. **Create `scripts/branch.sh`** with two subcommands:

   **Create a phase branch:**
   ```
   Usage: branch.sh create <project-path> <phase-name> [worker]
   ```
   - Runs on the DEV worker via SSH (or locally if no worker specified)
   - Creates branch `phase/<phase-name>` from current main/master
   - Checks out the branch
   - Prints: `Created and checked out branch: phase/<phase-name>`

   **Merge a phase branch back:**
   ```
   Usage: branch.sh merge <project-path> <phase-name> [worker]
   ```
   - Runs on the DEV worker via SSH
   - Checks out main/master
   - Merges `phase/<phase-name>` with `--no-ff` (preserves branch history)
   - Deletes the phase branch after merge
   - Prints: `Merged phase/<phase-name> into main`
   - If merge conflict: prints error, does NOT force, exits 1

   **List phase branches:**
   ```
   Usage: branch.sh list <project-path> [worker]
   ```
   - Lists all `phase/*` branches on the worker

2. **The script should use `get-worker.sh`** to resolve SSH commands when a worker is specified. If no worker arg, run commands locally.

3. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 4 item 4.3 as done.

## Files to Create
- `scripts/branch.sh` — Branch management helper (make executable)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark 4.3 as done

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/branch.sh` (create)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/03-branch-per-phase/result.md` (create)
- `.planning/phases/03-branch-per-phase/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/branch.sh` is executable
- [ ] `branch.sh create` creates a `phase/<name>` branch and checks it out
- [ ] `branch.sh merge` merges phase branch back to main with --no-ff
- [ ] `branch.sh merge` deletes the phase branch after successful merge
- [ ] `branch.sh list` shows phase branches
- [ ] Works locally (no worker arg) for testing
- [ ] Uses get-worker.sh for SSH when worker arg provided
- [ ] Merge conflicts exit 1 with clear error message
- [ ] ENHANCEMENT-ROADMAP.md shows 4.3 as done

## Smoke Tests
Run these AFTER implementing (test locally on the orchestrator repo itself):

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/branch.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `cd ~/awsc-new/awesome/orchestrator && bash scripts/branch.sh create ~/awsc-new/awesome/orchestrator test-phase && git branch | grep "phase/test-phase"` → expect match
3. `cd ~/awsc-new/awesome/orchestrator && bash scripts/branch.sh list ~/awsc-new/awesome/orchestrator | grep "test-phase"` → expect match
4. `cd ~/awsc-new/awesome/orchestrator && echo "test" >> /tmp/branch-test.txt && git add /tmp/branch-test.txt 2>/dev/null; git checkout master && bash scripts/branch.sh merge ~/awsc-new/awesome/orchestrator test-phase && git branch | grep -c "phase/test-phase"` → expect `0` (branch deleted)
5. `grep "4.3" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Make sure you end on the master branch (not a phase branch)
3. Write result.json alongside result.md
4. Write result to: `.planning/phases/03-branch-per-phase/result.md`
5. Commit with prefix: `[orchestrator-sprint4-03]`
6. Do NOT push
