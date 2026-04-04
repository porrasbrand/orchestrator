# Sprint 4: Scaling Foundation — Level-0 Plan

**Project:** orchestrator-sprint4
**Sprint:** 4
**Phases:** 5
**Checkpoint:** After Phase 3

---

## Phase Overview

| Phase | Name | Complexity | Depends On | Description |
|-------|------|-----------|------------|-------------|
| 01 | worker-registry | standard | — | Config file for workers; update verify.sh to read from it |
| 02 | dependency-dag | standard | — | Script to analyze status.json and identify parallel opportunities |
| 03 | branch-per-phase | standard | — | Helper script for phase branch creation and merge |
| 04 | status-web-page | complex | — | Generate self-contained HTML dashboard from orchestration state |
| 05 | cost-tracking | standard | 04 | Add wall-clock timing to events; include in status page |

## Execution Order

```
Phase 01 (worker-registry)    ─┐
Phase 02 (dependency-dag)      ├─ CHECKPOINT
Phase 03 (branch-per-phase)   ─┘
Phase 04 (status-web-page)    ─┐
Phase 05 (cost-tracking)      ─┘
```

Phases 01-03 are independent. Phase 05 depends on 04 (adds timing data to the status page).

## Architecture Decisions

1. **workers.json is static config** — Not auto-discovered. User maintains it. Scripts read it with jq.
2. **DAG script is advisory** — Outputs parallel opportunities but doesn't execute them. Sprint 5 will use this.
3. **Branch-per-phase is opt-in** — Helper scripts available, but orchestrator doesn't enforce branching in v4.
4. **Status page is self-contained HTML** — Single file, no external deps, inline CSS. Can be opened locally or published.
5. **Cost tracking uses wall-clock only** — No token counting in v4 (requires API integration). Wall-clock time from events.jsonl timestamps.
