# Sprint 5: Parallel Execution — Level-0 Plan

**Project:** orchestrator-sprint5
**Sprint:** 5
**Phases:** 4
**Checkpoint:** After Phase 2

---

## Phase Overview

| Phase | Name | Complexity | Depends On | Description |
|-------|------|-----------|------------|-------------|
| 01 | parallel-dispatch | complex | — | Script to identify ready parallel phases and queue to different workers |
| 02 | merge-orchestration | complex | 01 | Script to merge completed phase branches in dependency order |
| 03 | worker-load-balancing | standard | — | Script to select least-busy worker from registry |
| 04 | parallel-regression | standard | 02 | Script to run all previous smoke tests as one batch after merge |

## Execution Order

```
Phase 01 (parallel-dispatch)       ─┐
                                     ├─ CHECKPOINT
Phase 02 (merge-orchestration)     ─┘
Phase 03 (worker-load-balancing)   ─┐
Phase 04 (parallel-regression)     ─┘
```

Phase 02 depends on 01 (merge needs dispatch to have happened first).
Phase 04 depends on 02 (regression runs after merge).
Phase 03 is independent.

## Architecture Decisions

1. **parallel-dispatch.sh is a helper, not a daemon** — Orchestrator calls it to dispatch a batch of ready phases. It returns immediately after queuing (doesn't wait for results).
2. **merge-phases.sh handles ordering** — Uses dag.sh dependency info to merge branches in correct topological order. Fails fast on conflict.
3. **select-worker.sh is advisory** — Returns worker name. Orchestrator chooses whether to use suggestion.
4. **regression-test.sh reuses verify.sh infrastructure** — Collects all smoke tests from all completed phase specs, runs them in sequence via SSH on the merged branch.
5. **All scripts compose existing tools** — dag.sh, branch.sh, get-worker.sh, verify.sh. No new SSH logic.
