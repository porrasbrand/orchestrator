# Phase 05: Cost Tracking

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

## Prior Work Summary
Sprint 4 — four phases complete:
- **Phase 01 (worker-registry):** `config/workers.json` + `scripts/get-worker.sh`. verify.sh reads from registry.
- **Phase 02 (dependency-dag):** `scripts/dag.sh` for dependency analysis and parallel group identification.
- **Phase 03 (branch-per-phase):** `scripts/branch.sh` with create/merge/list for phase branches.
- **Phase 04 (status-web-page):** `scripts/generate-status-page.sh` generates self-contained HTML dashboard from status.json + events.jsonl. Shows phases, events timeline, progress bar, summary stats.

Currently there's no visibility into how long each phase takes. The events.jsonl has timestamps for queued/complete events, but nothing calculates or displays the duration. The status page doesn't show timing data.

## Objective
Add wall-clock time tracking per phase by calculating duration from events.jsonl timestamps, and include timing data in the status HTML page.

## Implementation Steps

1. **Create `scripts/timing.sh`** that calculates phase durations:
   ```
   Usage: timing.sh <project-path>
   ```
   - Reads events.jsonl
   - For each phase: find `phase_queued` and `phase_complete` events
   - Calculate duration in seconds between them
   - Output a summary table:
     ```
     Phase Timing:
       01-worker-registry       3m 42s
       02-dependency-dag        2m 15s
       03-branch-per-phase      4m 08s
       04-status-web-page       5m 30s  (longest)
       05-cost-tracking         pending
     
     Total wall-clock: 15m 35s
     Average per phase: 3m 54s
     ```

2. **Modify `scripts/generate-status-page.sh`** — Add a "Timing" column to the phase table showing duration for completed phases. Add total and average to the summary stats section.

3. **Update `ENHANCEMENT-ROADMAP.md`** — Mark Sprint 4 item 4.5 as done AND mark Sprint 4 overall as COMPLETE.

## Files to Create
- `scripts/timing.sh` — Phase timing calculator (make executable)

## Files to Modify
- `scripts/generate-status-page.sh` — Add timing column and stats
- `ENHANCEMENT-ROADMAP.md` — Mark 4.5 done + Sprint 4 complete

## Do NOT Touch
- All other scripts, templates, config files

## Expected Files Changed
- `scripts/timing.sh` (create)
- `scripts/generate-status-page.sh` (modify)
- `ENHANCEMENT-ROADMAP.md` (modify)
- `.planning/phases/05-cost-tracking/result.md` (create)
- `.planning/phases/05-cost-tracking/result.json` (create)

## Acceptance Criteria
- [ ] `scripts/timing.sh` is executable
- [ ] Calculates duration for each completed phase from events.jsonl timestamps
- [ ] Shows total wall-clock and average per phase
- [ ] Handles pending/queued phases gracefully (shows "pending" or "in progress")
- [ ] generate-status-page.sh includes timing in phase table
- [ ] generate-status-page.sh includes total/average timing in summary
- [ ] Works with current Sprint 4 orchestration data
- [ ] ENHANCEMENT-ROADMAP.md shows 4.5 done and Sprint 4 COMPLETE

## Smoke Tests
Run these AFTER implementing:

1. `test -x ~/awsc-new/awesome/orchestrator/scripts/timing.sh && echo EXECUTABLE` → expect `EXECUTABLE`
2. `bash ~/awsc-new/awesome/orchestrator/scripts/timing.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep "01-worker-registry"` → expect line with duration
3. `bash ~/awsc-new/awesome/orchestrator/scripts/timing.sh ~/awsc-new/awesome/orchestrator 2>&1 | grep -i "total"` → expect total time line
4. `bash ~/awsc-new/awesome/orchestrator/scripts/generate-status-page.sh ~/awsc-new/awesome/orchestrator /tmp/test-timing.html && grep -i "timing\|duration\|time" /tmp/test-timing.html | head -1` → expect match
5. `rm -f /tmp/test-timing.html && grep "4.5" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md | grep -i "done\|✅"` → expect match
6. `grep -i "sprint 4.*complete\|sprint 4.*done\|sprint 4.*✅" ~/awsc-new/awesome/orchestrator/ENHANCEMENT-ROADMAP.md` → expect match

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result.json alongside result.md
3. Write result to: `.planning/phases/05-cost-tracking/result.md`
4. Commit with prefix: `[orchestrator-sprint4-05]`
5. Do NOT push
