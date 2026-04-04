# Sprint 3: Structured Results & Verification — Project Brief

## What
Replace fragile text-based parsing with machine-readable formats across 4 enhancements:
1. **Structured result.json** — DEV workers write machine-readable JSON result alongside result.md
2. **Executable smoke tests** — Smoke tests as runnable `.sh` scripts instead of markdown text parsed by regex
3. **Cancellation mechanism** — Ability to cancel a queued phase before the worker starts it
4. **Phase idempotency** — Cleanup section in spec template so re-running a phase doesn't create duplicate state

## Why
Sprint 2 improved spec quality and verification scope-checking. But verification still parses markdown with regex (brittle), smoke tests are text in spec.md (not executable), there's no way to cancel a bad spec once queued, and partial completions can leave dirty state. These 4 changes make the orchestrator more reliable and robust.

## Where
- Project path: `~/awsc-new/awesome/orchestrator/` (on >>hetzner)
- Target environment: hetzner (DEV worker implements here)
- Orchestrated from: lipo-360

## Boundaries
- Do NOT modify CLAUDE.md (separate effort)
- Do NOT modify PLAN.md (historical document)
- Do NOT touch add-task.sh or the super-agent messaging system
- Do NOT add new npm dependencies — keep it bash + node built-ins
- Keep backwards-compatible with existing .planning/ directories
- Build on Sprint 2 work (use the new spec template sections, structured learnings, check-spec.sh)

## Success Criteria
- [ ] DEV workers can write `result.json` with schema `{status, files_modified[], tests_run[], blockers[], summary}`
- [ ] verify.sh reads result.json when present (falls back to result.md parsing)
- [ ] Smoke tests can be defined as executable `.sh` scripts in phase directory
- [ ] verify.sh runs `.sh` smoke test scripts when present (falls back to markdown parsing)
- [ ] `scripts/cancel-task.sh` marks a phase as CANCELLED in events.jsonl and status.json
- [ ] Spec template includes optional "Cleanup" section for idempotent re-runs
- [ ] All existing scripts still work (init.sh, scan.sh, status.sh, verify.sh, update-learnings.sh, check-spec.sh)
- [ ] ENHANCEMENT-ROADMAP.md updated to mark Sprint 3 items complete

## Access & Credentials
- Already configured. SSH key auth to hetzner. Git repo initialized with Sprint 2 code.

## Preferences
- Tech stack: Bash scripts + Node.js one-liners (match existing)
- Code style: Match existing scripts
- Testing: Manual verification via smoke tests
- Checkpoint frequency: every 2 phases (4 phases total)
