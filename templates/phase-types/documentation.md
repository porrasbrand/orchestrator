# Phase XX: {{PHASE_NAME}}
# Template: documentation
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, DOC_PATH, DOC_PURPOSE

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Create or update documentation at `{{DOC_PATH}}` for {{DOC_PURPOSE}}.

## Implementation Steps
1. **Create or update `{{DOC_PATH}}`** — Write clear, well-structured documentation for {{DOC_PURPOSE}}
2. **Include expected sections** — Title, overview, usage examples, reference details as appropriate
3. **Verify formatting** — Ensure valid markdown with proper headings, code blocks, and lists
4. **Cross-reference** — Link to related docs or scripts where applicable
5. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
- `{{DOC_PATH}}` — {{DOC_PURPOSE}} (if new)

## Files to Modify
- `{{DOC_PATH}}` — {{DOC_PURPOSE}} (if existing)
- `ENHANCEMENT-ROADMAP.md` — Mark this phase as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Scripts and config files (documentation only — no code changes)
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- `{{DOC_PATH}}` (create | modify) — Documentation file
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] `{{DOC_PATH}}` exists and is not empty
- [ ] Document has clear title and section structure
- [ ] Content accurately describes {{DOC_PURPOSE}}
- [ ] Markdown formatting is valid (headings, code blocks, lists)
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: File exists
test -f ~/awsc-new/awesome/orchestrator/{{DOC_PATH}} && echo EXISTS
# expect: EXISTS

# Test 2: File is not empty
test -s ~/awsc-new/awesome/orchestrator/{{DOC_PATH}} && echo NOT_EMPTY
# expect: NOT_EMPTY

# Test 3: Has expected sections (title at minimum)
head -1 ~/awsc-new/awesome/orchestrator/{{DOC_PATH}} | grep "^#" && echo HAS_TITLE
# expect: HAS_TITLE
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
