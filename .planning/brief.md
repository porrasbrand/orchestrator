# Sprint 4: Scaling Foundation — Project Brief

## What
Prepare the orchestrator for parallel execution and multi-worker scaling with 5 enhancements:
1. **Worker registry** — Config-driven worker list replacing hardcoded SSH paths in scripts
2. **Dependency DAG** — Script that reads status.json and identifies parallelizable phases
3. **Branch-per-phase** — Git workflow where each phase works on its own branch, merged after verification
4. **Status web page** — Static HTML dashboard generated from status.json + events.jsonl
5. **Per-phase cost tracking** — Wall-clock time per phase stored in events.jsonl, summarized in status page

## Why
Currently we have 2 workers but can only use 1 at a time. Adding a new worker means editing multiple scripts. There's no visibility into progress from outside the terminal, and no data on what phases actually cost. These 5 items build the foundation needed before Sprint 5 (parallel execution).

## Where
- Project path: `~/awsc-new/awesome/orchestrator/` (on >>hetzner)
- Target environment: hetzner (DEV worker implements here)
- Orchestrated from: lipo-360

## Boundaries
- Do NOT modify CLAUDE.md or PLAN.md
- Do NOT add npm dependencies — bash + node built-ins + jq only
- Do NOT implement actual parallel execution (Sprint 5)
- Keep backwards-compatible with existing .planning/ directories
- Worker registry is read-only config — scripts read it, don't modify it

## Success Criteria
- [ ] `config/workers.json` defines workers with name, host, port, user, ssh_key, capabilities, status
- [ ] verify.sh reads worker config from registry instead of hardcoded if/else
- [ ] `scripts/dag.sh` reads status.json and outputs which phases can run in parallel
- [ ] Branch-per-phase workflow documented; helper script creates/merges phase branches
- [ ] `scripts/generate-status-page.sh` produces self-contained HTML from status.json + events.jsonl
- [ ] Events include `wall_clock_seconds` for completed phases
- [ ] Status page shows phase timeline, pass/fail, revisions, timing
- [ ] All existing scripts still work

## Access & Credentials
- Already configured. SSH key auth. Git repo with Sprint 2+3 code.

## Preferences
- Tech stack: Bash + jq + node one-liners (match existing)
- Checkpoint frequency: after phase 3 (5 phases total)
