# Learnings

Discoveries made during execution that inform future phases.

## Phase r1-01: Dispatch Ledger (orchestrator-r1r2)
- Smoke suite runs clean on BOTH hetzner and lipo-360 — env overrides (ORCH_STATE_DIR/SUPER_AGENT_DIR) make hermetic tests portable; keep this pattern for r1-02/03.
- queue-phase.sh treats the add-task local-fallback ("Task saved locally:") as FAILURE — future phases must not assume ledger entry == task on worker without the "Task queued:" line.
- If .planning/ missing, ledger is written but phase_queued event skipped (stderr warning) — daemon must key off the LEDGER, not events.jsonl.

## Phase r1-02: pm-iterate (orchestrator-r1r2)
- SPEC AMBIGUITY (mine): --dry-run emits the pm_iteration event to the project's real events.jsonl (spec placed the emit inside prompt-build). Dry-run must be side-effect-free → fix folded into r1-03 spec as a Files-to-Modify item.
- Dry-run against the real project confirmed name resolution + commit-prefix templating work without registry entry (status.json fallback path).
- Worker gotcha worth reusing: bash printf with leading '-' lines needs printf '%s\n' form.

## Phase r2-04: Slack notify hook (orchestrator-r1r2)
- CONTRACT for r2-05: pm-iterate.sh's escalation gate unblocks ONLY on a later `escalation_resolved` event for the same phase in events.jsonl (see r1-02 T7). The resolution flow MUST (a) append that event, (b) invoke pm-iterate with `--trigger resolution` (which bypasses the gate even without the event). Slack command mapping: continue/retry → escalation_resolved + resolution-trigger iterate; abort → set phase status blocked + notify; override: <text> → escalation_resolved + write the text into .planning/resolutions.jsonl for the next revision spec.
- Poller efficiency: only poll conversations.replies for projects whose slack-threads.json entry exists AND whose status is escalated/blocked/awaiting-checkpoint — not on every tick for every project.
- notify-hook.sh reply_broadcast list: ai_escalation_recommended, phase_failed, checkpoint, project_complete (attention events surface in-channel).

## Phase r2-05: Slack resolutions (orchestrator-r1r2)
- pm-daemon.js deployed live on the controller — ANY future phase touching services/pm-daemon.js needs "pm2 restart pm-daemon" in its deploy notes; pm-iterate.sh/hook changes are picked up per-spawn automatically.
- FOR r1r2-06 SPEC (final phase wishlist): (1) integration-test-pm.sh = end-to-end chain scenarios ACROSS components (response→claim→iterate→archive; escalation→Slack→continue→resolution-iterate; checkpoint→G6 pause→acknowledge), using all existing mocks — do not re-test per-component behavior already covered by the 5 suites; (2) CLAUDE.md gets a "Resident PM (daemon-first operation)" section: grace-period division of labor vs interactive sessions, kill switches (paused file, interrupt.json, pm2 stop), env tuning table, and a CLARIFICATION that one pm-iterate "iteration" = one phase advance (verify-and-advance or spec-and-queue counts as one); (3) new docs/RESIDENT-PM-RUNBOOK.md: deploy steps (register-project, pm2 start, slack.env + SLACK_CHANNEL, channel+bot invite), monitoring (pm2 logs, iterations.jsonl, ai-stats), failure playbook (claimed/ stuck, failed/ dir, gave-up events, rate-cap); (4) update config/notify-hook.sh.example header to mention the shipped Slack hook.
