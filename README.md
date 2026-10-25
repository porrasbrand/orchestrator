# Orchestrator

> Sanitized public version; client data and infrastructure details replaced with fictional examples.

Autonomous multi-phase project orchestration for Claude Code: a PM instance breaks a project
into phases, writes specs, dispatches them to remote DEV workers over SSH, independently verifies
the results with executable smoke tests, and runs revision cycles until each phase passes.

## Features

- Phase decomposition with templates (`templates/`) for briefs, specs, results and revisions
- Worker registry (`config/workers.json`), worker selection, load balancing and failover
- Parallel dispatch, dependency DAG and branch-per-phase merge orchestration
- Independent verification (`scripts/verify.sh`), regression and integration tests, auto-rollback
- AI-assisted failure diagnosis (`scripts/ai-diagnose.js`) and structured learnings
- Status page generation, notification hooks, cost tracking

## Setup

```bash
cp config/workers.example.json config/workers.json   # then edit hosts, users, keys
cp config/notify-hook.sh.example config/notify-hook.sh  # optional
```

Workers in the example config (`worker-1.example.internal`, `worker-2.example.internal`) are
placeholders. See `CLAUDE.md` for the orchestrator's operating instructions, `PLAN.md` for the
architecture and `.planning/` for the orchestrator's own self-hosted development history.

## Author

Manuel Porras — https://manuelporras.com
