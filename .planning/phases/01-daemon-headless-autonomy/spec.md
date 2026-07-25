# Phase 01: daemon-headless-autonomy (SF-15 + SF-14)

## Context

Self-dogfood fix phase on the orchestrator repo. The `orch-shakedown-fault`
shakedown proved S4 (pm-daemon grace-claim) works but left two open daemon-side
defects that block trusting laptop-closed operation. Fix BOTH here, with hermetic
tests, keep the full regression green, and redeploy the daemon.

Repo (self-target): `/home/ubuntu/awsc-new/awesome/orchestrator`
(= `~/awsc-new/awesome/orchestrator` on this worker). Local repo, no push.

**Live daemon:** `services/pm-daemon.js` runs under pm2 (`pm-daemon`). Your deploy
step MUST restart it and leave it online.

## Prior Work Summary

None for this project (r1r2 archived to `.planning/archive/r1r2/`). The two bugs
are documented in `SHAKEDOWN-REPORT.md` §4 (SF-14, SF-15) in this repo.

## Objective

1. **SF-15 (HIGH):** a daemon-spawned headless `pm-iterate` must be able to SPEC
   and QUEUE a phase (dispatch must resolve to the real resident local dispatcher,
   NOT the absent `$SUPER_AGENT_DIR/scripts/add-task.sh`), while the hermetic-test
   injection mechanism the suites rely on still works.
2. **SF-14 (MEDIUM):** a scan cycle where a claimed shim was already archived by
   the interactive PM must NOT throw an escaping exception; the cycle completes and
   `claims[taskId]` is cleared.
3. New hermetic tests for both; full existing regression still green; daemon
   redeployed cleanly; findings marked resolved in learnings with commit refs.

## The two defects (exact current sites)

**SF-15.** `services/pm-daemon.js:135` spawns pm-iterate with `env: process.env`,
which includes the daemon's operational `SUPER_AGENT_DIR` (`:37`, = its response-
shim dir). `scripts/queue-phase.sh:23` sets `SA_DIR_EXPLICIT=1` whenever
`SUPER_AGENT_DIR` is set, and `:93-96` then routes dispatch to
`$SUPER_AGENT_DIR/scripts/add-task.sh` (absent under the shim dir) → hard fail.
Net: the headless PM can verify but cannot spec/queue.

**SF-14.** `services/pm-daemon.js` claimed-loop (`:203-227`): after a pm-iterate
`exit 0` it calls `moveFile(claimedPath, RESP_ARCHIVE)` (`:217`, `moveFile` at
`:145` does `fs.renameSync`) and then `delete s.claims[taskId]` (`:219`). If the
interactive PM already archived that shim, `renameSync` throws `ENOENT`, escapes
`scanCycle` (`:167`), abandons the rest of the cycle for a full poll interval, and
leaks `claims[taskId]` (the delete never runs).

## Implementation Steps

### A. SF-15 fix — `scripts/queue-phase.sh` resident local-dispatcher fallback
1. In the `hetzner` dispatch-resolution branch (`:90-97`), when `orch_is_hetzner`
   is true and the resolved `$SUPER_AGENT_DIR/scripts/add-task.sh` does **NOT**
   exist, set `DISPATCH="$SCRIPT_DIR/dispatch-local-hetzner.sh"` (the resident
   local dispatcher) **even if** `SA_DIR_EXPLICIT=1`. Keep the current behavior
   otherwise: if `add-task.sh` **does** exist under the injected `SUPER_AGENT_DIR`
   (hermetic suites), use it (injection preserved).
2. Add a short comment referencing SF-15 explaining the fallback.
3. (Optional, defence-in-depth — only if you justify it keeps ALL suites green):
   in `pm-daemon.js:133-135`, spawn pm-iterate with a child env that omits
   `SUPER_AGENT_DIR` (e.g. clone `process.env`, `delete env.SUPER_AGENT_DIR`).
   The response file is passed via `--response-file` arg, not this var. If ANY
   existing suite relies on the daemon propagating `SUPER_AGENT_DIR` to the child,
   do NOT do this — the queue-phase fallback alone satisfies the criterion.

### B. SF-14 fix — `services/pm-daemon.js` guarded archive + claim-clear
1. Make `moveFile` (`:145`) tolerate a missing source: if `!fs.existsSync(src)`,
   log and return (no throw); wrap the rename in try/catch and, on `ENOENT`,
   treat as already-moved (no throw). Preserve the existing cross-device fallback
   at `:158` (guard it too).
2. In the claimed-loop (`:203-227`), clear `s.claims[taskId]` + `saveDaemonState`
   for the success path BEFORE / independently of the archive move, so a move
   failure cannot leak the claim. Wrap the per-file loop body in try/catch so one
   file's error is logged and the loop continues (cycle completes).
3. Verify the other `moveFile`/`renameSync` call sites (`:148`,`:158`, and any
   `failed/` move) don't share the unguarded hazard; apply the same guard.

### C. Hermetic tests (mock pattern, matching existing suites)
Create `scripts/test-sf15.sh` and `scripts/test-sf14.sh` (executable, self-
contained, exit 0 = pass), each emitting one `✅`/`❌` per assertion:
- **test-sf15.sh:**
  - *SF15-a:* with `SUPER_AGENT_DIR` set to a temp dir that has NO
    `scripts/add-task.sh` (simulating the daemon's runtime env) on the resident
    host, `queue-phase.sh` dispatch resolves to `dispatch-local-hetzner.sh` (assert
    it does NOT try `$SUPER_AGENT_DIR/scripts/add-task.sh`). Use the existing mock
    dispatch/queue pattern; do not actually queue a real worker task (mock it).
  - *SF15-b:* with `SUPER_AGENT_DIR` set to a temp dir that DOES contain a mock
    `scripts/add-task.sh`, dispatch routes to that mock (injection preserved).
- **test-sf14.sh:** drive `scanCycle` once (the daemon supports `--once`) with a
  ledgered task whose claimed shim has been pre-removed/pre-archived; assert: the
  process exits without an escaping exception, the cycle completes (reaches its
  end / summary), and `daemon-state.json` `claims` no longer contains that taskId.
  Use the same mock/env harness the existing pm-daemon tests use (`PM_ITERATE_MOCK`,
  temp `ORCH_STATE_DIR`/`SUPER_AGENT_DIR`).

### D. Regression + deploy
1. Run the FULL existing regression (all suites — e.g. `scripts/integration-test-pm.sh`,
   `scripts/integration-test.sh`, `scripts/regression-test.sh`, `scripts/test-numenv.sh`,
   and any per-component suites). ALL must stay green (r1r2 baseline 145+). Fix any
   test that your change legitimately updates (comment-only where possible); do NOT
   weaken assertions to pass.
2. **Deploy:** `cd ~/awsc-new/awesome/orchestrator && pm2 restart pm-daemon --update-env`.
   Confirm `pm2 describe pm-daemon` status=online and the first log lines are clean
   (no stack trace). Do NOT leave the daemon stopped.
3. Mark **SF-15** and **SF-14** resolved in `.planning/learnings.md` with the commit
   SHA(s).

## Files to Create

- `scripts/test-sf15.sh`, `scripts/test-sf14.sh` (hermetic tests).

## Files to Modify

- `scripts/queue-phase.sh` (SF-15 fallback).
- `services/pm-daemon.js` (SF-14 guards; optional SF-15 child-env scrub).
- `.planning/learnings.md` (findings resolved + commit refs).
- Any existing test file ONLY if your change legitimately requires a comment/update.

## Do NOT Touch

- Anything outside the orchestrator repo. wsl2 config. Other projects' `.planning/`.
- Out-of-scope findings (SF-11/12/13 etc.) — do not "also fix" them.
- `.planning/archive/**` (the r1r2 history).
- `brief.md`. Do not weaken existing test assertions.

## Expected Files Changed

- `scripts/queue-phase.sh`
- `services/pm-daemon.js`
- `scripts/test-sf15.sh`
- `scripts/test-sf14.sh`

## Acceptance Criteria

- [ ] SF-15: `test-sf15.sh` proves daemon-env dispatch → local dispatcher (not the
      absent add-task.sh) AND mock injection still routes to the mock.
- [ ] SF-14: `test-sf14.sh` proves a pre-archived shim mid-scan → no escaping
      exception, cycle completes, `claims[taskId]` cleared.
- [ ] `node --check services/pm-daemon.js` passes; `bash -n scripts/queue-phase.sh` passes.
- [ ] Full existing regression green (no weakened assertions).
- [ ] `pm2 restart pm-daemon --update-env` done; `pm-daemon` status=online, clean logs.
- [ ] SF-15 + SF-14 marked resolved in `.planning/learnings.md` with commit SHAs.
- [ ] Commit(s) with prefix `[orch-daemon-fixes-01]`.

## Smoke Tests

Verification contract: `.planning/phases/01-daemon-headless-autonomy/smoke-tests.sh`
(PM-authored). It runs both new hermetic tests, the key regression suites,
`node --check`, and confirms the daemon is online.

## Completion Instructions

Implement A–D, run the smoke contract locally (must ALL PASS), write
`result.md` (justify the SF-15 approach chosen; paste hermetic + regression
output; note the pm2 restart + online confirmation), commit with prefix
`[orch-daemon-fixes-01]` (local, no push).
