# Project Brief: orchestrator-r1r2 — Resident PM (Event-Driven Daemon + Slack Escalations)

**Created:** 2026-07-02
**Requested by:** Manuel
**Project path:** /home/mp/awesome/orchestrator (repo shared lipo-360 ↔ hetzner via GitHub)

## 1. Goal

Close the orchestration loop without a human-attended session. Today every orchestrated
project freezes when the interactive Claude session on lipo-360 is closed: responses sit
unread in `tasks/responses/new/`, verification never runs, next phases never queue.

**R1 — Resident PM daemon:** a pm2 service on lipo-360 that detects worker responses
belonging to orchestrated projects and spawns a headless `claude -p` invocation that runs
exactly ONE orchestration-loop iteration (verify → advance/revise → queue → exit).

**R2 — Slack escalations:** orchestrator notifications (checkpoint, escalation, phase
failed, project complete) post to a Slack channel; human replies ("continue", "abort",
"override: ...") are polled and fed back into the loop as resolutions.

## 2. Success Criteria

- A phase response arriving while NO interactive session is open gets verified and the
  next phase queued automatically within ~grace-period + 5 min, with full transcript logged.
- A response handled by an open interactive session is NOT double-processed by the daemon.
- Escalations (`ai_escalation_recommended`, `phase_failed`, checkpoint) reach Slack; a
  threaded "continue" reply resumes the loop without touching the laptop.
- Kill switch (`~/.orchestrator/paused`) and per-project `interrupt.json` are honored.
- Hermetic integration tests cover the chain with $0 API cost (mock claude, mock Slack,
  mock add-task).

## 3. Boundaries / Constraints

- All new code lives in the orchestrator repo (portable, configurable paths). Nothing is
  hardcoded to lipo-360 paths — super-agent dir, responses dir, state dir all via env/config
  with sensible defaults.
- Do NOT modify `/home/mp/awesome/super-agent` scripts or services (add-task.sh,
  local-response-watcher.js are consumed as-is; watcher pings interactive sessions first,
  daemon claims only after a grace period).
- Daemon runtime state lives in `~/.orchestrator/` (ledger, registry, locks, slack state) —
  NOT in the git repo.
- Headless claude runs use an allowedTools whitelist (Bash, Read, Write, Edit, Glob, Grep),
  bounded turns, per-project flock, and a per-project hourly iteration cap. Never
  `--dangerously-skip-permissions`.
- The daemon NEVER overrides orchestrator escalation rules: an unresolved
  `ai_escalation_recommended` still halts auto-revision; the daemon's job there is only to
  notify Slack and wait for a resolution.
- Slack: reuse the existing "B3X CC Experts" app bot token (lives on hetzner expert-bridge);
  channel `#orchestrator` in breakthrough3x.slack.com. Token/channel provided at deploy
  time via `~/.orchestrator/slack.env` — code must no-op gracefully when absent.
- wsl2 is hands-off (colleague using it) — all phases dispatch to >>hetzner.

## 4. Deliverables

- `scripts/register-project.sh`, `scripts/queue-phase.sh` (dispatch ledger)
- `scripts/pm-iterate.sh` (single headless PM iteration w/ guardrails)
- `services/pm-daemon.js` + run wrapper (pm2 on lipo-360)
- `config/notify-hook.sh` Slack implementation + `scripts/slack-poll-resolutions.sh`
- `scripts/integration-test-pm.sh` (hermetic chain tests)
- Docs: CLAUDE.md "Resident PM" section + deployment runbook

## 5. Verification Method

Executable smoke tests per phase (hermetic, mock-based, runnable on hetzner without
lipo-side services). Final live validation happens on lipo-360 at deploy time (PM-run).

## 6. Checkpoint Frequency

3 (checkpoint after phase 03 and at completion).

## 7. Revision Budget

Standard phases: 3. Complex phases: 5.
