# Resident PM Runbook

Operator playbook for deploying, monitoring, and troubleshooting the daemon-driven
orchestration loop (R1: dispatch ledger + pm-iterate + pm-daemon; R2: Slack outbound +
inbound resolutions). Assumes bash / jq / node ≥ 18 / pm2 / curl on the controller.

## Deploy

1. **Register each orchestrated project** with the daemon.

   ```bash
   scripts/register-project.sh add /path/to/project [--worker hetzner|wsl2]
   ```

   This writes `~/.orchestrator/active-projects.json` with `{name, local_path, worker,
   remote_path, active:true, registered_at}`. Re-add is idempotent (preserves
   `registered_at`). Deactivate later with `register-project.sh deactivate <name>`.

2. **Start the daemon under pm2.**

   ```bash
   pm2 start scripts/run-pm-daemon.sh --name pm-daemon
   ```

   `run-pm-daemon.sh` is a thin wrapper: it `exec`s `node
   services/pm-daemon.js "$@"`. Any change to `services/pm-daemon.js` requires
   `pm2 restart pm-daemon` to take effect. Changes to `scripts/pm-iterate.sh`,
   `scripts/slack-poll-resolutions.sh`, or `config/notify-hook.sh` are picked up
   automatically on the next spawn — no restart needed.

3. **Provision Slack (optional but usual).** Create the `#orchestrator` channel in
   your Slack workspace, invite the bot, and drop credentials into
   `~/.orchestrator/slack.env` (never commit this file):

   ```bash
   cat > ~/.orchestrator/slack.env <<'EOF'
   SLACK_BOT_TOKEN=xoxb-...
   SLACK_CHANNEL=C0XXXXXXXX
   EOF
   chmod 600 ~/.orchestrator/slack.env
   ```

   Without `slack.env`, `config/notify-hook.sh` and
   `scripts/slack-poll-resolutions.sh` both gracefully no-op (exit 0). The rest of
   the loop still works — just without Slack notifications.

4. **Verify the wiring.** Run each phase suite once (all hermetic — safe on any
   machine):

   ```bash
   bash .planning/phases/r1-01-dispatch-ledger/smoke-tests.sh   # 11/11
   bash .planning/phases/r1-02-pm-iterate/smoke-tests.sh        # 16/16
   bash .planning/phases/r1-03-pm-daemon/smoke-tests.sh         # 19/19
   bash .planning/phases/r2-04-slack-notify/smoke-tests.sh      # 18/18
   bash .planning/phases/r2-05-slack-resolutions/smoke-tests.sh # 32/32
   scripts/integration-test-pm.sh                                # scenarios=5 FAIL=0
   ```

## Monitor

- **Daemon logs.** `pm2 logs pm-daemon`. Every claim, spawn, exit code, disposition
  (archive / failed / SKIP), tick-summary line, and resolutions-cycle summary is
  logged with an ISO-8601 UTC timestamp and the `[pm-daemon]` tag.
- **Per-project state** (all under `<project>/.planning/`):
  - `status.json` — canonical phase state, including `current_phase`, `phases[…].status`,
    `blocked` / `blocked_reason`, and `updated`.
  - `events.jsonl` — append-only audit: `phase_queued`, `phase_complete`, `phase_failed`,
    `ai_escalation_recommended`, `escalation_resolved`, `checkpoint`,
    `checkpoint_acknowledged`, `phase_aborted`, `pm_iteration`, `pm_daemon_gave_up`.
  - `resolutions.jsonl` — human-authored resolutions (continue / abort / override) that
    the daemon consumed from Slack.
  - `notifications.md` + `latest-notification.json` — every `scripts/notify.sh` call.
- **Global state** (all under `~/.orchestrator/`):
  - `dispatch-ledger.jsonl` — every `queue-phase.sh` dispatch (`{ts, task_id (string),
    project, project_path, phase, worker}`).
  - `iterations.jsonl` — every `pm-iterate.sh` run (`{ts, project, trigger, exit_code,
    duration_s, prompt, transcript}`).
  - `runs/<project>/<ts>-prompt.md` + `<ts>-transcript.log` — the exact prompt sent to
    claude + the transcript that came back.
  - `daemon-state.json` — retry attempts per claimed response.
  - `slack-threads.json` — per-project Slack thread map.
  - `slack-resolutions-state.json` — per-project inbound cursor.
- **AI-quality trend.** `scripts/ai-stats.sh` summarizes the P2 diagnostic-agent
  decisions (retry vs escalate confidence and outcomes).
- **Slack.** One per-project thread in `#orchestrator` collects all notifications for
  that project. Attention events (`ai_escalation_recommended`, `phase_failed`,
  `checkpoint`, `project_complete`, `phase_aborted`) broadcast to the channel via
  `reply_broadcast:true`; benign events stay in-thread.

## Failure playbook

### A response sits in `claimed/` and never archives

Cause: `pm-iterate.sh` returned an exit 0 with a `SKIP:` line (rate-cap, escalation
gate, checkpoint gate, interrupt, paused). The daemon deliberately leaves the file in
place so the next cycle retries. Check the daemon log for the specific `SKIP: <reason>`.

- `SKIP: rate-capped ...` — hit `PM_MAX_ITER_PER_HOUR` for this project. Wait an hour
  or raise the cap.
- `SKIP: escalated-awaiting-human` — the current phase has an unresolved
  `ai_escalation_recommended` event. Reply `continue` / `abort` / `override: <text>`
  in the project's Slack thread (r2-05), or bypass from a laptop with
  `pm-iterate.sh <project> --trigger resolution`.
- `SKIP: checkpoint-awaiting-human` — same idea but the project hit a manual
  checkpoint. Human must acknowledge (`continue`).
- `SKIP: paused` — the global kill switch is set. `rm ~/.orchestrator/paused`.
- `SKIP: interrupted` — `<project>/.planning/interrupt.json` exists.
  `rm <project>/.planning/interrupt.json`.
- `SKIP: locked` — another `pm-iterate` for this project is already running (or the
  flock file is stuck). Should self-clear as the other run exits.

### A response moved to `failed/` and left a `pm_daemon_gave_up` event

`PM_MAX_ATTEMPTS` (default 2) exhausted with non-zero exits. Read the transcript
under `~/.orchestrator/runs/<project>/<ts>-transcript.log` and the
`pm_daemon_gave_up` event `{task_id, phase, attempts, last_exit}` to diagnose.
Re-enqueue the task via `scripts/queue-phase.sh` and clear
`~/.orchestrator/daemon-state.json` to reset the attempts counter.

### Slack replies aren't advancing an escalated project

- Check `~/.orchestrator/slack.env` exists and has a valid `SLACK_BOT_TOKEN` +
  `SLACK_CHANNEL`.
- Confirm the bot was invited to the channel and can read the project's thread.
- `scripts/slack-poll-resolutions.sh` must be executable; `pm2 logs pm-daemon` should
  show `spawn (resolutions): …` with an `exit=0` and a `slack-poll: eligible=<n>
  processed=<m>` summary.
- The reply must be a TOP-LEVEL reply in the correct thread (bot messages and the
  parent are filtered out); the first line must be `continue` / `retry` / `abort` or
  `override: <text>` (case-insensitive).
- Cursor per project lives in `~/.orchestrator/slack-resolutions-state.json`. Deleting
  a project's cursor entry re-processes all replies in the thread on the next poll.

### Escalation flow recap

- `ai_escalation_recommended` events are appended by the P2 diagnostic agent (see
  `lib/ai-diagnose.js` + the AI-stats section of `PLAN.md`) when its confidence /
  policy indicates the loop should stop and ask a human.
- The runbook answer from Slack: `continue` (or `retry`) re-runs the phase;
  `override: <text>` re-runs with human guidance injected into the next revision
  spec; `abort` marks the phase blocked and the daemon subsequently ignores it
  (unblocking requires a laptop session).
- The runbook answer from a laptop: `scripts/pm-iterate.sh <project> --trigger
  resolution` bypasses BOTH G5 (escalation gate) and G6 (checkpoint gate).

### Kill switches (mirror of the CLAUDE.md table)

- **Global:** `touch ~/.orchestrator/paused` — daemon cycles + `pm-iterate` all stop;
  reverse with `rm`. Interactive PM sessions unaffected.
- **Per-project:** `touch <project>/.planning/interrupt.json` — only `pm-iterate.sh`
  for that project SKIPs; daemon and other projects unaffected.
- **Process:** `pm2 stop pm-daemon` — full daemon halt; `pm2 start pm-daemon` to resume.
