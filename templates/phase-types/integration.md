# Phase XX: {{PHASE_NAME}}
# Template: integration
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, SOURCE_MODULE, TARGET_SYSTEM, INTEGRATION_POINT

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Integrate `{{SOURCE_MODULE}}` with `{{TARGET_SYSTEM}}` at the integration point: {{INTEGRATION_POINT}}.

## Implementation Steps
1. **Understand the source module** — Read `{{SOURCE_MODULE}}` and document its interface (inputs, outputs, side effects)
2. **Understand the target system** — Read `{{TARGET_SYSTEM}}` and document its expected inputs and current state
3. **Identify integration point** — Map exactly where and how the two connect: {{INTEGRATION_POINT}}
4. **Wire them together** — Implement the integration code/config that connects source to target
5. **Test end-to-end** — Run a full flow from source through to target and verify correct behavior
6. **Verify source unchanged** — Confirm `{{SOURCE_MODULE}}` behavior is not altered for its existing consumers
7. **Verify target accepts** — Confirm `{{TARGET_SYSTEM}}` correctly processes input from the new integration
8. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
- [List any new glue/adapter files needed for the integration]

## Files to Modify
- `{{SOURCE_MODULE}}` — Add integration output/hook (if needed)
- `{{TARGET_SYSTEM}}` — Add integration input/handler (if needed)
- `ENHANCEMENT-ROADMAP.md` — Mark this phase as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Unrelated scripts and modules
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- [List integration files] (create | modify) — Integration wiring
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] End-to-end flow works: data flows from `{{SOURCE_MODULE}}` through `{{INTEGRATION_POINT}}` to `{{TARGET_SYSTEM}}`
- [ ] `{{SOURCE_MODULE}}` existing behavior is unchanged for its current consumers
- [ ] `{{TARGET_SYSTEM}}` correctly accepts and processes integrated input
- [ ] No hardcoded values — integration is configurable where appropriate
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: End-to-end integration works
# [Fill in e2e test from {{SOURCE_MODULE}} to {{TARGET_SYSTEM}}]
# expect: Data flows correctly through {{INTEGRATION_POINT}}

# Test 2: Source module unchanged for existing consumers
# [Fill in existing test for {{SOURCE_MODULE}}]
# expect: Same output as before integration

# Test 3: Target system accepts integrated input
# [Fill in test for {{TARGET_SYSTEM}} receiving new input]
# expect: Correct processing of integrated data
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
