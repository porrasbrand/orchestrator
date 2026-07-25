# Level-0 Plan: orchestrator-r1r2 — Resident PM

**Created:** 2026-07-02 · **Worker:** hetzner (wsl2 hands-off) · **Repo:** github.com/porrasbrand/orchestrator

## Architecture Overview

```
tasks/responses/new/<id>.json  (written by response-fetcher, lipo-360)
        │
        ├── local-response-watcher → tmux ping (interactive session, unchanged)
        │        └─ session handles it → file moved to archive/ → daemon no-op
        │
        └── pm-daemon.js (pm2, lipo-360)
             │  file still in new/ after GRACE_PERIOD and task_id ∈ dispatch-ledger?
             ▼
        pm-iterate.sh <project> --response-file <path>
             │  flock + hourly cap + interrupt/paused checks
             ▼
        claude -p (headless, allowedTools whitelist, bounded turns)
             │  ONE loop iteration: verify → advance/revise → queue-phase.sh → exit
             ▼
        queue-phase.sh → add-task.sh → ledger entry (task_id → project/phase)
             │
        notify.sh → config/notify-hook.sh → Slack #orchestrator (threaded per project)
             │
        slack-poll-resolutions.sh (daemon tick) → .planning/resolutions.jsonl → pm-iterate
```

State in `~/.orchestrator/`: `active-projects.json`, `dispatch-ledger.jsonl`, `locks/`,
`slack.env`, `slack-threads.json`, `paused` (kill switch).

## Phases

| # | Phase | Complexity | Depends on | Deliverable |
|---|-------|-----------|------------|-------------|
| r1-01-dispatch-ledger | Project registry + dispatch ledger | standard | — | register-project.sh, queue-phase.sh, ledger schema |
| r1-02-pm-iterate | Headless single-iteration runner | complex | r1-01 | pm-iterate.sh (flock, caps, allowedTools, transcript logs, PM_ITERATE_MOCK) |
| r1-03-pm-daemon | Watcher daemon + tick | complex | r1-02 | services/pm-daemon.js, run-pm-daemon.sh, grace-period claim, paused/interrupt |
| r2-04-slack-notify | Slack notify hook | standard | — | config/notify-hook.sh (chat.postMessage, per-project threads, SLACK_MOCK) |
| r2-05-slack-resolutions | Reply polling → resolutions | complex | r1-03, r2-04 | slack-poll-resolutions.sh, resolutions.jsonl, daemon-tick wiring, thread ACKs |
| r1r2-06-integration-docs | Hermetic chain tests + docs | standard | r1-03, r2-05 | integration-test-pm.sh (5 scenarios), CLAUDE.md Resident PM section, runbook |

**Execution order:** r1-01 → r1-02 → r1-03 → r2-04 → r2-05 → r1r2-06
(r2-04 is DAG-independent but same repo ⇒ serialized by per-repo lock anyway.)

## Key Design Decisions (Level-0)

1. **Grace-period claim, not watcher modification.** The interactive flow stays primary:
   watcher pings tmux immediately; a handled response is archived. The daemon only claims
   responses still sitting in `new/` after GRACE_PERIOD (default 600s) whose task_id is in
   the dispatch ledger. Zero changes to super-agent, zero race with open sessions.
2. **Ledger written at dispatch time.** `queue-phase.sh` wraps `add-task.sh`, parses the
   printed `ID: <task_id>`, appends `{ts, task_id, project, project_path, phase, worker}`
   to `~/.orchestrator/dispatch-ledger.jsonl`, and emits `phase_queued` (with task_id) to
   the project's events.jsonl. Non-orchestrated tasks never enter the ledger ⇒ daemon
   ignores them by construction.
3. **One iteration per invocation.** `pm-iterate.sh` never loops. The daemon provides the
   cadence; the headless claude does exactly one state transition and exits. Bounded blast
   radius, bounded cost, resumable by design (state is `.planning/`).
4. **Safety stack:** allowedTools whitelist · per-project flock · hourly iteration cap
   (default 6) · `~/.orchestrator/paused` global kill switch · `.planning/interrupt.json`
   per project · escalation rules unchanged (daemon notifies + waits, never auto-revises
   past an unresolved escalation).
5. **Everything mockable:** `PM_ITERATE_MOCK` (canned claude transcript), `SLACK_MOCK`
   (write JSON to file), mock `add-task.sh` via PATH override — hermetic tests on hetzner,
   $0, no lipo services needed.
