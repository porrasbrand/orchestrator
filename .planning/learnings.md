# Learnings

Discoveries made during execution that inform future phases.

## Phase r1-01: Dispatch Ledger (orchestrator-r1r2)
- Smoke suite runs clean on BOTH hetzner and lipo-360 — env overrides (ORCH_STATE_DIR/SUPER_AGENT_DIR) make hermetic tests portable; keep this pattern for r1-02/03.
- queue-phase.sh treats the add-task local-fallback ("Task saved locally:") as FAILURE — future phases must not assume ledger entry == task on worker without the "Task queued:" line.
- If .planning/ missing, ledger is written but phase_queued event skipped (stderr warning) — daemon must key off the LEDGER, not events.jsonl.
