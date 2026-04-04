# Phase 03: Worker Load Balancing

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 5 progress:
- **Phase 01 (parallel-dispatch):** `scripts/parallel-dispatch.sh` identifies ready phases, creates branches, outputs JSON dispatch plan with round-robin worker assignment.
- **Phase 02 (merge-orchestration):** `scripts/merge-phases.sh` merges completed phase branches in dependency order, stops on conflicts.

parallel-dispatch.sh currently uses simple round-robin to assign phases to workers. This doesn't account for whether a worker is busy or idle. A smarter selection picks the least-busy worker.

## Objective
Create `scripts/select-worker.sh` that checks active workers from the registry and returns the least-busy one. Update parallel-dispatch.sh to use it instead of round-robin.

## Implementation Steps

1. **Create `scripts/select-worker.sh`**:
   ```
   Usage: select-worker.sh [config-path]
   Default config: config/workers.json (relative to script dir)
   Output: worker name (e.g., "hetzner")
   ```

   The script should:
   a. Read active workers from config/workers.json (status = "active")
   b. For each active worker, check if they're busy by SSHing and looking for a running Claude process or checking queue depth
   c. Since we can't reliably check remote queue depth without additional infrastructure, use a simpler heuristic: check if the worker responds to SSH within 5 seconds (available) and check for a `.busy` lock file at `~/awsc-new/awesome/.orchestrator-busy`
   d. Return the first available (non-busy) worker
   e. If all workers are busy or only one exists, return the first active worker
   f. Output just the worker name to stdout (machine-readable)

2. **Modify `scripts/parallel-dispatch.sh`** — Replace the round-robin logic with calls to `select-worker.sh`. For multiple phases, alternate: call select-worker for first phase, use the OTHER active worker for the second, etc. (simple 2-worker optimization).

3. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 5 item 5.3 as done.

## Files to Create
- `scripts/select-worker.sh` — Worker selection helper (make executable)

## Files to Modify
- `scripts/parallel-dispatch.sh` — Use select-worker.sh instead of round-robin
- `ENHANCEMENT-ROADMAP.md` — Mark 5.3 as done

## Do NOT Touch
- All other scripts, config/workers.json, templates

## Expected Files Changed
- `scripts/select-worker.sh` (create)
- `scripts/parallel-dispatch.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/03-worker-load-balancing/result.md` (create)
- `.planning/phases/03-worker-load-balancing/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/select-worker.sh` is executable
- [ ] Returns a worker name from config/workers.json
- [ ] Only considers workers with status "active"
- [ ] Checks SSH reachability (with timeout)
- [ ] Returns first active worker if all busy or single worker
- [ ] parallel-dispatch.sh uses select-worker.sh for assignments
- [ ] Output is clean (just worker name, no extra text)
- [ ] ENHANCEMENT-ROADMAP.md shows 5.3 as done

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/select-worker.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `RESULT=$(bash ~/awsc-new/awesome/orchestrator/scripts/select-worker.sh) && echo "$RESULT" | grep -E "^(hetzner|wsl2)$"` → expect match (returns a valid worker name)
3. `bash ~/awsc-new/awesome/orchestrator/scripts/select-worker.sh | wc -l` → expect `1` (single line output)
4. `grep "select-worker" ~/awsc-new/awesome/orchestrator/scripts/parallel-dispatch.sh | head -1` → expect match
5. `grep "5.3" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/03-worker-load-balancing/result.md`
4. Commit with prefix: `[orchestrator-sprint5-03]`
5. Do NOT push
