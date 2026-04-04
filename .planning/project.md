# Sprint 2: Quality & Intelligence — Level-0 Plan

**Project:** orchestrator
**Sprint:** 2
**Phases:** 4
**Checkpoint:** After Phase 2

---

## Phase Overview

| Phase | Name | Complexity | Depends On | Description |
|-------|------|-----------|------------|-------------|
| 01 | structured-learnings | standard | — | Replace learnings.md with learnings.jsonl schema + auto-generated markdown view |
| 02 | context-handoff | standard | — | Add "Prior Work Summary" and "Expected Files Changed" sections to spec template |
| 03 | spec-quality-check | standard | 02 | New script `check-spec.sh` that validates spec.md has required sections |
| 04 | diff-verification | standard | 02 | Update verify.sh to check git diff against expected_files from spec |

## Execution Order

```
Phase 01 (structured-learnings)  ─┐
                                   ├─ CHECKPOINT ─── Phase 03 (spec-quality-check)
Phase 02 (context-handoff)       ─┘                  Phase 04 (diff-verification)
```

Phases 01 and 02 are independent — could run in parallel (but sequential for v1).
Phases 03 and 04 depend on Phase 02 (they validate/use the new spec sections).

## Architecture Decisions

1. **learnings.jsonl schema:** `{ts, phase, category, discovery, impact}` — category enables filtering (e.g., "codebase", "api", "testing", "auth")
2. **learnings.md auto-generation:** A helper in scripts/ reads learnings.jsonl and writes a formatted learnings.md. Both files coexist.
3. **Spec template changes are additive:** New sections added to templates/spec.md. Existing specs without these sections still work (check-spec.sh warns, doesn't error).
4. **expected_files is advisory:** verify.sh warns on out-of-scope changes but doesn't fail the phase (DEV may have legitimate reasons to touch extra files).
5. **check-spec.sh is a pre-queue gate:** Orchestrator runs it before queuing. Warnings printed, errors block queuing.

## Files to Create/Modify

### Phase 01: structured-learnings
- CREATE: `templates/learnings-schema.md` — documents the JSONL schema
- MODIFY: `scripts/init.sh` — scaffold learnings.jsonl instead of (or alongside) learnings.md
- CREATE: `scripts/update-learnings.sh` — appends structured entry to learnings.jsonl + regenerates learnings.md

### Phase 02: context-handoff
- MODIFY: `templates/spec.md` — add "Prior Work Summary" section (max 500 words) + "Expected Files Changed" section
- MODIFY: `ENHANCEMENT-ROADMAP.md` — mark 2.2 and partial 2.4 as done

### Phase 03: spec-quality-check
- CREATE: `scripts/check-spec.sh` — validates spec.md sections, reports warnings/errors
- MODIFY: `ENHANCEMENT-ROADMAP.md` — mark 2.3 as done

### Phase 04: diff-verification
- MODIFY: `scripts/verify.sh` — add diff-check step after smoke tests
- MODIFY: `ENHANCEMENT-ROADMAP.md` — mark Sprint 2 complete

## Risks
- **Backwards compatibility:** Old .planning/ dirs won't have learnings.jsonl. Scripts must handle missing files gracefully.
- **Spec template bloat:** Adding sections increases spec size. Keep new sections concise with clear guidance.
