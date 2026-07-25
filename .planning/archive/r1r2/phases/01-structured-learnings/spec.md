# Phase 01: Structured Learnings

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.

This is an autonomous multi-phase project execution framework. It breaks large projects into phases, dispatches to DEV workers, and verifies results independently.

Currently, the framework stores phase learnings in `learnings.md` — an unstructured markdown file. This makes it impossible to query learnings by category (e.g., "what failed in auth phases?") or programmatically include relevant learnings in future specs.

**Prior Work Summary:** This is Phase 01 — no prior phases. Sprint 1 reliability fixes (escaping, SSH retry, delivery ACK, SSH key auth) were implemented directly on lipo-360 and are already in the codebase.

## Objective
Replace the unstructured `learnings.md` with a structured `learnings.jsonl` file as the source of truth, plus an auto-generated `learnings.md` view for human readability.

## Implementation Steps

1. **Define the JSONL schema** — Create `templates/learnings-schema.md` documenting:
   ```jsonl
   {"ts":"2026-04-04T12:00:00Z","phase":"01-publish-history","category":"codebase","discovery":"Uses ESM not CommonJS","impact":"high"}
   ```
   Categories: `codebase`, `api`, `testing`, `infrastructure`, `security`, `performance`, `other`
   Impact: `high`, `medium`, `low`

2. **Create `scripts/update-learnings.sh`** — A script that:
   - Takes args: `<project-path> <phase> <category> <discovery> [impact]`
   - Appends a JSON line to `.planning/learnings.jsonl`
   - Regenerates `.planning/learnings.md` from the JSONL (grouped by phase, showing category tags)
   - Uses `jq` for JSON construction (safe escaping)
   - If learnings.jsonl doesn't exist, creates it

3. **Modify `scripts/init.sh`** — Add creation of empty `learnings.jsonl` alongside existing `learnings.md` during scaffold. Keep both files — JSONL is source of truth, MD is the human view.

4. **Add query capability** — Add a `--query` flag to update-learnings.sh:
   - `./scripts/update-learnings.sh --query <project-path> category=api` → prints all API-related learnings
   - `./scripts/update-learnings.sh --query <project-path> phase=03` → prints Phase 03 learnings
   - Uses `jq` to filter learnings.jsonl

## Files to Create
- `templates/learnings-schema.md` — Schema documentation
- `scripts/update-learnings.sh` — Add + query + regenerate learnings

## Files to Modify
- `scripts/init.sh` — Add learnings.jsonl scaffolding

## Do NOT Touch
- `CLAUDE.md`
- `PLAN.md`
- `scripts/verify.sh` (modified in Phase 04)
- `templates/spec.md` (modified in Phase 02)
- Any files outside the orchestrator project

## Expected Files Changed
- `templates/learnings-schema.md` (new)
- `scripts/update-learnings.sh` (new)
- `scripts/init.sh` (modified — add learnings.jsonl creation)

## Acceptance Criteria
- [ ] `templates/learnings-schema.md` exists and documents the JSONL schema with examples
- [ ] `scripts/update-learnings.sh` is executable and appends valid JSONL entries
- [ ] Running update-learnings.sh regenerates learnings.md from learnings.jsonl
- [ ] `scripts/init.sh` creates both learnings.jsonl and learnings.md during scaffold
- [ ] `--query` flag filters learnings by category or phase
- [ ] All JSON output is valid (parseable by jq)
- [ ] Handles missing learnings.jsonl gracefully (creates it)
- [ ] Existing scripts (scan.sh, status.sh, verify.sh) still work unchanged

## Smoke Tests
Run these AFTER implementing:

1. `cd ~/awsc-new/awesome/orchestrator && bash scripts/init.sh /tmp/test-orch-s2` → expect "scaffolded"
2. `test -f /tmp/test-orch-s2/.planning/learnings.jsonl && echo EXISTS` → expect `EXISTS`
3. `bash scripts/update-learnings.sh /tmp/test-orch-s2 01-test codebase "Uses ESM modules" high && cat /tmp/test-orch-s2/.planning/learnings.jsonl | jq -r '.category'` → expect `codebase`
4. `bash scripts/update-learnings.sh /tmp/test-orch-s2 01-test api "REST not GraphQL" medium && wc -l < /tmp/test-orch-s2/.planning/learnings.jsonl` → expect `2`
5. `cat /tmp/test-orch-s2/.planning/learnings.md | grep "Uses ESM"` → expect match
6. `bash scripts/update-learnings.sh --query /tmp/test-orch-s2 category=api | jq -r '.discovery'` → expect `REST not GraphQL`
7. `rm -rf /tmp/test-orch-s2` (cleanup)

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result to: `.planning/phases/01-structured-learnings/result.md`
3. Commit with prefix: `[orchestrator-sprint2-01]`
4. Do NOT push (no remote configured)
