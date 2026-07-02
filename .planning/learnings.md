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
