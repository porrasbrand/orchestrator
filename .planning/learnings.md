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

## Phase 01: COMPLETE (PM-verified) — SF-15 + SF-14 fixed
- SF-15 (HIGH) RESOLVED: queue-phase.sh resident fallback to dispatch-local-hetzner.sh when injected SUPER_AGENT_DIR lacks scripts/add-task.sh; hermetic injection preserved. pm-daemon.js unchanged for SF-15 (worker justified: integration-test-pm S1 relies on the daemon passing SUPER_AGENT_DIR to the child). Commit b8abf35.
- SF-14 (MED) RESOLVED: pm-daemon.js moveFile guarded (existsSync + ENOENT try/catch), claim cleared regardless of move, claimed-loop body wrapped in try/catch so one file can't abandon the cycle. Commit b8abf35.
- PM independent verification: smoke contract ALL PASS (both hermetic tests + integration-test-pm 27/0 + integration-test 40/9 + test-numenv + node --check + daemon online + learnings). verify.sh exit 0. Daemon post-restart: online, no stack traces, grace=600s.
- A headless daemon-spawned PM can now BOTH verify AND spec/queue — laptop-closed autonomy is no longer half-broken (closes the S4 caveat from the shakedown).
