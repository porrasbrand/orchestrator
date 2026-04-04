# Sprint 3: Structured Results & Verification — Level-0 Plan

**Project:** orchestrator-sprint3
**Sprint:** 3
**Phases:** 4
**Checkpoint:** After Phase 2

---

## Phase Overview

| Phase | Name | Complexity | Depends On | Description |
|-------|------|-----------|------------|-------------|
| 01 | structured-results | standard | — | Add result.json schema + template; update verify.sh to read JSON results |
| 02 | executable-smoke-tests | standard | 01 | Support `.sh` smoke test scripts alongside markdown; verify.sh runs both |
| 03 | cancellation | standard | — | New cancel-task.sh script; CANCELLED state in events + status |
| 04 | phase-idempotency | standard | — | Add Cleanup section to spec template; document idempotency pattern |

## Execution Order

```
Phase 01 (structured-results)       ─┐
                                      ├─ CHECKPOINT
Phase 02 (executable-smoke-tests)   ─┘
Phase 03 (cancellation)             ─┐
Phase 04 (phase-idempotency)        ─┘
```

Phase 02 depends on 01 (needs result.json support before smoke test scripts can write structured output).
Phases 03 and 04 are independent of each other and of 01/02.

## Architecture Decisions

1. **result.json is optional** — verify.sh checks for it first, falls back to result.md. Older phases without result.json still work.
2. **Smoke test scripts are optional** — If `phases/XX/smoke-tests.sh` exists, verify.sh runs it. Otherwise falls back to markdown parsing. Both can coexist.
3. **Cancellation is local** — cancel-task.sh updates local .planning/ state. It does NOT kill a running Claude session (impossible). It marks the phase so orchestrator skips verification on response.
4. **Cleanup section is advisory** — Template guidance for DEV workers. Not enforced by tooling (too complex for v3).

## Files to Create/Modify

### Phase 01: structured-results
- CREATE: `templates/result-schema.md` — documents result.json schema
- MODIFY: `templates/result.md` — add note about result.json
- MODIFY: `scripts/verify.sh` — read result.json for basic checks when present
- MODIFY: `templates/spec.md` — update Completion Instructions to mention result.json

### Phase 02: executable-smoke-tests
- CREATE: `templates/smoke-tests-template.sh` — example smoke test script
- MODIFY: `scripts/verify.sh` — detect and run smoke-tests.sh from phase dir
- MODIFY: `templates/spec.md` — add note about optional smoke-tests.sh

### Phase 03: cancellation
- CREATE: `scripts/cancel-task.sh` — marks phase as CANCELLED
- No other files modified

### Phase 04: phase-idempotency
- MODIFY: `templates/spec.md` — add optional "Cleanup" section
- MODIFY: `ENHANCEMENT-ROADMAP.md` — mark Sprint 3 complete
