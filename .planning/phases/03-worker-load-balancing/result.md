# Phase 03: Worker Load Balancing - Result

**Status:** COMPLETE
**Date:** 2026-04-04

## Summary

Created `scripts/select-worker.sh` that selects the least-busy active worker by checking SSH reachability and a `.orchestrator-busy` lock file. Updated `parallel-dispatch.sh` to use load-balanced worker selection instead of simple round-robin.

## Files Created
- `scripts/select-worker.sh` — Worker selection helper (executable)

## Files Modified
- `scripts/parallel-dispatch.sh` — Uses select-worker.sh for load-balanced assignment
- `ENHANCEMENT-ROADMAP.md` — Marked Sprint 5 item 5.3 as ✅ DONE

## Implementation Details

### select-worker.sh Features
1. **Active Worker Filter** — Only considers workers with status="active" in workers.json
2. **Busy Check** — SSHs to each worker and checks for `.orchestrator-busy` lock file
3. **Fallback** — Returns first active worker if all busy or single worker exists
4. **Clean Output** — Outputs just the worker name (machine-readable)

### parallel-dispatch.sh Changes
- Replaced round-robin with load-balanced selection
- Calls `select-worker.sh` to get primary (least-busy) worker
- Alternates between primary and secondary worker for parallel phases
- Falls back to primary if only one worker exists

### Busy Detection Heuristic
```bash
# Check if worker has .orchestrator-busy lock file
is_busy=$($ssh_cmd "test -f $base_path/.orchestrator-busy && echo BUSY || echo FREE")
```

### Usage
```bash
# Get least-busy worker
./scripts/select-worker.sh
# Output: hetzner

# With custom config
./scripts/select-worker.sh /path/to/workers.json
```

## Smoke Tests Passed
1. ✅ Script is executable
2. ✅ Returns valid worker name (hetzner)
3. ✅ Single line output (1 line)
4. ✅ parallel-dispatch.sh uses select-worker.sh
5. ✅ 5.3 marked as done

## Blockers
None.

## Notes
- Lock file approach is simple but effective for 2-worker setup
- Workers can set `.orchestrator-busy` when starting a task
- Future enhancement: check actual queue depth via SQLite
