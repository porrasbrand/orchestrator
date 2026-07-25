# Project Brief: pm-daemon Headless-Autonomy Fixes (SF-15 + SF-14)

> **Origin:** `orch-shakedown-fault` findings (SHAKEDOWN-REPORT.md, 2026-07-25).
> **Approved by:** Manuel, 2026-07-25.
> **Suggested project name:** `orch-daemon-fixes`

## What

Fix the two open daemon-side defects the shakedown left behind, both in the
orchestrator repo (self-dogfood, same pattern as r1r2):

**SF-15 (HIGH) — `SUPER_AGENT_DIR` overload breaks headless spec/queue.**
`pm-daemon` runs with `SUPER_AGENT_DIR` pointed at its response-shim dir and passes
`env: process.env` to pm-iterate (`services/pm-daemon.js:128`). `queue-phase.sh`
reads `SUPER_AGENT_DIR` as a hermetic-test injection and routes dispatch to
`$SUPER_AGENT_DIR/scripts/add-task.sh` (absent) → hard fail (shakedown EJ:80). Net
effect: a daemon-spawned headless PM can VERIFY but cannot SPEC/QUEUE the next
phase — laptop-closed autonomy is half-broken. Shakedown workaround was
`env -u SUPER_AGENT_DIR`. Candidate fixes (worker/PM to choose + justify): separate
the two env vars, scrub the child env in pm-daemon, or a local-dispatcher fallback
in queue-phase.sh. The fix must preserve the hermetic-test injection mechanism the
suites rely on.

**SF-14 (MEDIUM) — daemon scan cycle aborts on ENOENT shim rename.**
`pm-daemon.js` `moveFile:141` ← `scanCycle:210`: an unconditional
`renameSync claimed/… → archive/` throws `ENOENT` when the interactive PM already
archived the shim; the exception escapes `scanCycle`, abandoning the remainder of
the cycle for a full poll interval and leaking `claims[taskId]` (evidenced:
pm-daemon log 18:19:31.734Z stack trace, EJ:79). Fix per report suggestion:
`existsSync`/try-catch guard in `moveFile`; clear `claims[taskId]` before the move.
Consider whether other `moveFile` call sites share the hazard.

## Why

S4 proved the grace-claim machinery works — and simultaneously proved that the
headless PM it hands control to cannot advance the project (SF-15) and that normal
interactive/daemon coexistence can knock out a scan cycle (SF-14). These are the
last blockers to trusting laptop-closed operation.

## Where

- Repo: `~/awsc-new/awesome/orchestrator` on hetzner (self-target, like r1r2).
- Prior `.planning/` is from the completed r1r2 project — archive per your
  convention before init.
- Target worker: `hetzner` only (wsl2 remains hands-off).

## Boundaries

- Scope is SF-15 + SF-14 ONLY. SF-11 (strict reply grammar), SF-12 (gate desync),
  SF-13 (shim re-delivery) and all other shakedown findings are explicitly OUT of
  scope — separate briefs later.
- Do not disturb active registered projects.
- `services/pm-daemon.js` is deployed live → any phase touching it must include
  `pm2 restart pm-daemon --update-env` in its deploy steps (established learning),
  and must not leave the daemon stopped.
- No destructive ops; kill-switches honored as always.

## Success Criteria

- [ ] SF-15: with the daemon's real runtime env, a daemon-spawned pm-iterate can spec AND queue (hermetic test proving dispatch resolves to the real add-task path, not `$SUPER_AGENT_DIR/scripts/add-task.sh`); hermetic-test injection still works for the suites.
- [ ] SF-14: hermetic test — pre-archived shim during a scan cycle → no exception escapes, cycle completes, `claims[taskId]` cleared.
- [ ] Full existing regression suites still green (r1r2 baseline: 145+ tests).
- [ ] pm-daemon restarted cleanly, `pm2 list` online, no error in first minutes of logs.
- [ ] Findings SF-15/SF-14 marked resolved in the orchestrator's learnings with commit refs.

## Access & Credentials

All local on hetzner. No external services needed.

## Preferences

- Small: 1–2 phases (one per finding, or one combined + tests). Max 3.
- Checkpoint frequency: none needed — notify at completion (this is a
  well-bounded bugfix project; escalate only on 2-attempt failure per doctrine).
- Testing: required, hermetic (mock-SSH pattern), matching existing suites.
