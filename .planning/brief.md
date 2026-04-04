# Sprint 5: Parallel Execution — Project Brief

## What
Enable the orchestrator to dispatch independent phases to multiple workers simultaneously, merge results, and verify everything works together. 4 enhancements:
1. **Parallel dispatch** — Orchestrator identifies independent phases via dag.sh and queues them to different workers at the same time
2. **Merge orchestration** — After parallel phases complete, merge phase branches in dependency order with conflict detection
3. **Worker load balancing** — Route phases to least-busy worker based on current queue depth
4. **Parallel regression testing** — After merging parallel work, run ALL smoke tests from ALL completed phases as one batch

## Why
This is the payoff for Sprints 1-4. We now have: worker registry (know who's available), dependency DAG (know what's parallel), branch-per-phase (isolated work), and status page (visibility). The missing piece is actually running phases in parallel — which would give 2-3x speedup on projects with independent tracks.

## Where
- Project path: `~/awsc-new/awesome/orchestrator/` (on >>hetzner)
- Target environment: hetzner (DEV worker implements here)
- Orchestrated from: lipo-360

## Boundaries
- Do NOT modify CLAUDE.md or PLAN.md
- Do NOT add npm dependencies — bash + jq + node built-ins only
- These are TOOLING scripts the orchestrator can use — they don't change how the orchestrator loop works (that's in CLAUDE.md, a separate effort)
- Keep backwards-compatible — sequential execution must still work
- Load balancing is advisory (suggests worker), not mandatory

## Success Criteria
- [ ] `scripts/parallel-dispatch.sh` identifies ready parallel phases and queues them to different workers
- [ ] `scripts/merge-phases.sh` merges completed phase branches in correct order
- [ ] `scripts/select-worker.sh` picks least-busy worker from registry
- [ ] `scripts/regression-test.sh` runs ALL previous smoke tests as one batch after merge
- [ ] All scripts use existing tools (dag.sh, branch.sh, get-worker.sh, verify.sh)
- [ ] Sequential execution still works (parallel is opt-in)
- [ ] ENHANCEMENT-ROADMAP.md updated to mark Sprint 5 complete

## Access & Credentials
- Already configured. SSH key auth. Git repo with Sprint 1-4 code.

## Preferences
- Tech stack: Bash + jq (match existing)
- Checkpoint frequency: after phase 2 (4 phases total)
