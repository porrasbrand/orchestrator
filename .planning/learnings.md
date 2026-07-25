# Learnings

Discoveries made during execution that inform future phases.

## Phase 01 — daemon-headless-autonomy (SF-15 + SF-14)

- **SF-15 — RESOLVED** (commit `b8abf35`). A daemon-spawned headless `pm-iterate` inherited the
  daemon's operational `SUPER_AGENT_DIR` (its response-shim dir), which set `SA_DIR_EXPLICIT=1`
  in `queue-phase.sh` and routed dispatch to the absent `$SUPER_AGENT_DIR/scripts/add-task.sh`
  → hard fail (a laptop-closed PM could verify but not spec/queue). Fix: on the resident host,
  when `add-task.sh` doesn't exist under `SUPER_AGENT_DIR`, fall back to the local dispatcher
  `dispatch-local-hetzner.sh` even when `SA_DIR_EXPLICIT=1`; the hermetic-test injection path
  (mock `add-task.sh` present) is preserved. Proven by `scripts/test-sf15.sh` (SF15-a/-b).
- **SF-14 — RESOLVED** (commit `b8abf35`). When the interactive PM archived a claimed shim
  before the daemon's scan reached it, `moveFile()`'s unguarded `renameSync` threw `ENOENT`,
  escaped `scanCycle`, abandoned the rest of the cycle for a full poll interval, and leaked
  `claims[taskId]`. Fix: `moveFile()` tolerates a missing source (existsSync + ENOENT
  try/catch); the success path clears `claims[taskId]` before the archive move; the
  claimed-loop body is wrapped in try/catch. Proven by `scripts/test-sf14.sh`.
