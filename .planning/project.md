# orch-daemon-fixes — Level-0 Plan

> Self-dogfood on `~/awsc-new/awesome/orchestrator` (same pattern as r1r2). Fix the
> two open daemon-side defects from the `orch-shakedown-fault` shakedown:
> **SF-15** (HIGH) and **SF-14** (MEDIUM). Scope is STRICTLY these two — SF-11/12/13
> and all other findings are OUT (brief Boundaries). Brief: `.planning/brief.md`
> (immutable). Prior r1r2 planning archived to `.planning/archive/r1r2/`.

## Target

- Repo: `/home/ubuntu/awsc-new/awesome/orchestrator` (self-target; on the worker
  it resolves via `REMOTE_BASE/basename` = `~/awsc-new/awesome/orchestrator` — no
  symlink needed, it is already under `awesome/`).
- Worker: `hetzner` only. Commit prefix `[orch-daemon-fixes-NN]`; PM state
  `[orch-daemon-fixes-orchestrator]`. Local repo, no push.
- **Live-daemon caution:** `services/pm-daemon.js` is deployed live (pm2
  `pm-daemon`). Any phase touching it MUST end with `pm2 restart pm-daemon
  --update-env` and must not leave the daemon stopped (brief Boundaries).

## Phases

| # | Dir | Fixes | Type | Deploy |
|---|-----|-------|------|--------|
| 01 | `01-daemon-headless-autonomy` | **SF-15** + **SF-14** | complex | `pm2 restart pm-daemon --update-env` |

**One combined phase** (brief allows "one combined + tests"): both defects are
daemon-headless-autonomy bugs, share the regression suite, and need a single
atomic daemon restart. If verification fails on one fix, the revision targets that
specific failure.

## Fix approaches (PM-chosen, worker to implement + justify in result.md)

- **SF-15 — resident local-dispatcher fallback in `queue-phase.sh`** (primary).
  When `orch_is_hetzner` AND the resolved `$SUPER_AGENT_DIR/scripts/add-task.sh`
  does **not** exist, fall back to the local dispatcher even if `SA_DIR_EXPLICIT=1`.
  Rationale: surgical (single file), and it changes behavior ONLY in the exact
  failure case (injected `SUPER_AGENT_DIR` with no `add-task.sh` = the daemon's
  operational env leaking in). Hermetic suites inject a **real mock** `add-task.sh`,
  so their path is unaffected → injection preserved. No pm-daemon restart needed
  for THIS fix (queue-phase.sh is read fresh per dispatch). The worker MAY also
  scrub `SUPER_AGENT_DIR` from the pm-iterate child env in `pm-daemon.js:133-135`
  (defence-in-depth) if it justifies the change keeps all suites green.
- **SF-14 — guard the archive rename + clear the claim first** in `pm-daemon.js`.
  Make `moveFile` (`:145`) tolerate a missing source (existsSync/try-catch, no
  throw on ENOENT); clear `s.claims[taskId]` BEFORE / regardless of the move; wrap
  the per-file body in the claimed-loop (`:203`) in try-catch so one file's error
  cannot abandon the rest of the cycle. Check the other `moveFile`/`renameSync`
  call sites (`:148,:158`) for the same hazard.

## Success criteria → phase mapping (from brief)

- SF-15 hermetic test: daemon-runtime env → pm-iterate can spec AND queue (dispatch
  resolves to the real local path, not `$SUPER_AGENT_DIR/scripts/add-task.sh`); mock
  injection still routes to the mock. → P01
- SF-14 hermetic test: pre-archived shim mid-scan → no exception escapes, cycle
  completes, `claims[taskId]` cleared. → P01
- Full existing regression green (r1r2 baseline 145+). → P01 smoke contract
- pm-daemon restarted cleanly, `pm2 list` online, clean first-minutes logs. → P01 + PM close
- SF-15/SF-14 marked resolved in learnings with commit refs. → P01 + PM close

## Dependencies / cadence

Single phase. No checkpoints (brief: notify at completion). Escalate only on
2-attempt verification failure (doctrine). Daemon restart is the worker's deploy
step; PM independently re-verifies `pm2` online + clean logs at close.
