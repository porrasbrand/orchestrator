# Sprint 2: Quality & Intelligence — Project Brief

## What
Enhance the orchestrator framework with 4 quality improvements:
1. **Structured learnings** — Replace `learnings.md` with `learnings.jsonl` (queryable, schema-enforced)
2. **Context reset / handoff** — Add summary handoff to spec template so DEV workers get clean context per phase
3. **Spec quality pre-check** — New script that validates specs before queuing (has smoke tests? acceptance criteria? clear scope?)
4. **Diff-based verification** — Add `expected_files` field to spec template; verify.sh checks git diff against expected scope

## Why
Real-world orchestration (GitHub portfolio build, 10 phases) revealed that:
- Learnings in markdown are unqueryable — can't ask "what went wrong in auth phases?"
- Long projects degrade as Claude context fills — need fresh context per phase
- Vague specs cause most revision cycles — catching them early saves full dispatch round-trips
- DEV workers sometimes touch files outside spec scope — no guard against this

These 4 changes target the root causes of wasted cycles and quality degradation.

## Where
- Project path: `~/awsc-new/awesome/orchestrator/` (on >>hetzner)
- Target environment: hetzner (DEV worker implements here)
- Orchestrated from: lipo-360

## Boundaries
- Do NOT modify CLAUDE.md instructions (that's a separate effort)
- Do NOT modify PLAN.md (historical document)
- Do NOT touch add-task.sh or the super-agent messaging system
- Do NOT add new npm dependencies — keep it bash + node built-ins
- Keep all changes backwards-compatible with existing .planning/ directories

## Success Criteria
- [ ] `learnings.jsonl` schema defined and template updated. Existing learnings.md becomes auto-generated view from JSONL.
- [ ] Spec template (`templates/spec.md`) includes "Prior Work Summary" section (max 500 words) and "Expected Files Changed" section
- [ ] New script `scripts/check-spec.sh` validates a spec.md and reports warnings/errors for missing sections
- [ ] `scripts/verify.sh` checks git diff against `expected_files` list from spec and warns on out-of-scope changes
- [ ] All existing scripts still work (init.sh, scan.sh, status.sh, verify.sh)
- [ ] ENHANCEMENT-ROADMAP.md updated to mark Sprint 2 items as complete

## Access & Credentials
- Already configured. SSH key auth to hetzner. Git repo initialized.

## Preferences
- Tech stack: Bash scripts + Node.js one-liners (match existing)
- Code style: Match existing scripts in `scripts/`
- Testing: Manual verification via smoke tests
- Checkpoint frequency: every 2 phases (4 phases total, so 1 checkpoint at midpoint)
