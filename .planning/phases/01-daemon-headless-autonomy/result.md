# Phase 01: daemon-headless-autonomy (SF-15 + SF-14) — Result

**Status:** `complete`. Both daemon defects surfaced by the `orch-shakedown-fault` audit are
fixed, with hermetic tests, the full existing regression still green, and the live daemon
redeployed and online. PM verification contract passes **ALL** checks.

## SF-15 (HIGH) — headless dispatch fallback

**Bug:** `services/pm-daemon.js:135` spawns `pm-iterate` with `env: process.env`, which
carries the daemon's operational `SUPER_AGENT_DIR` (its response-shim dir). `queue-phase.sh`
sets `SA_DIR_EXPLICIT=1` whenever `SUPER_AGENT_DIR` is set and then routes dispatch to
`$SUPER_AGENT_DIR/scripts/add-task.sh` — which is absent under the shim dir → hard fail. Net:
a laptop-closed headless PM could verify but could not spec/queue.

**Fix (in `scripts/queue-phase.sh`):** in the `hetzner` dispatch-resolution branch, when
`orch_is_hetzner` and the resolved `$SUPER_AGENT_DIR/scripts/add-task.sh` does **not** exist,
set `DISPATCH="$SCRIPT_DIR/dispatch-local-hetzner.sh"` (the resident local dispatcher) **even
if** `SA_DIR_EXPLICIT=1`. When `add-task.sh` **does** exist under the injected
`SUPER_AGENT_DIR` (the mechanism the hermetic suites rely on), that path is preserved.

**Why this approach over the optional pm-daemon child-env scrub:** the spec offered a
defence-in-depth alternative — clone `process.env` and `delete env.SUPER_AGENT_DIR` before
spawning pm-iterate — but only "if it keeps ALL suites green." The `queue-phase.sh` fallback
alone fully satisfies the acceptance criterion and is lower-risk: `integration-test-pm.sh`'s
S1 scenario deliberately spawns the daemon → real pm-iterate with `SUPER_AGENT_DIR` set and
relies on that env reaching the child; stripping the var there could perturb a passing suite
for no additional benefit. So `pm-daemon.js` was **not** changed for SF-15 — the fallback is
keyed on the real failure signal (absence of `add-task.sh`), which is exactly the daemon's
runtime condition, and it leaves the hermetic injection path untouched.

## SF-14 (MEDIUM) — guarded archive + claim-clear

**Bug:** in the claimed-loop, after a `pm-iterate` exit 0 the daemon called
`moveFile(claimedPath, RESP_ARCHIVE)` then `delete s.claims[taskId]`. If the interactive PM
had already archived that shim, `renameSync` threw `ENOENT`, escaped `scanCycle`, abandoned
the rest of the cycle for a full poll interval, and leaked `claims[taskId]` (the delete never
ran).

**Fix (in `services/pm-daemon.js`):**
1. `moveFile()` now tolerates a missing source — `existsSync` guard returns early, and the
   `renameSync` is wrapped in try/catch that treats `ENOENT` as already-moved (no throw). This
   also covers the `RESP_FAILED` move, which uses the same `moveFile`.
2. The success path clears `claims[taskId]` + `saveDaemonState` **before** the archive move,
   so a missing/failed move can never leak the claim.
3. The per-file claimed-loop body is wrapped in try/catch, so one file's error is logged and
   the loop continues — the cycle always completes.

The other `renameSync` site (`tryClaim`) already handled `ENOENT` (returns null on a raced
claim); no other unguarded hazard remained.

## Hermetic tests (verbatim)

`scripts/test-sf15.sh` — SF15-a stubs the local dispatcher's `queue-db.js` so nothing real is
queued; SF15-b uses a mock `add-task.sh`:

```
✅ SF15-a: daemon-env (no add-task.sh) resolved to resident local dispatcher, not add-task.sh
✅ SF15-b: injected mock add-task.sh still used (hermetic injection preserved)
---
ALL PASS
```

`scripts/test-sf14.sh` — a mock pm-iterate deletes its `--response-file` mid-run (simulating
the PM archiving the shim), driving the exact `moveFile` ENOENT condition:

```
✅ SF14-1: --once completed, no escaping exception (no 'scan error'/ENOENT)
✅ SF14-2: moveFile guard exercised (pre-archived source tolerated, no throw)
✅ SF14-3: claims[314314314314314314] cleared from daemon-state.json
---
ALL PASS
```

## Regression (no weakened assertions)

- `integration-test-pm.sh` — green (PASS=27 FAIL=0).
- `integration-test.sh` — green.
- `test-numenv.sh` — green (N1–N5).
- `node --check services/pm-daemon.js` — pass. `bash -n scripts/queue-phase.sh` — pass.

(`scripts/regression-test.sh` is a per-project driver requiring a `<project-path>` argument,
not a standing hermetic suite, and is not part of the verification contract; it was not run as
a regression. No test assertions were weakened.)

## Deploy

`cd ~/awsc-new/awesome/orchestrator && pm2 restart pm-daemon --update-env` — issued; `pm-daemon`
came back **online**. Fresh startup line clean, no stack trace:
`19:02:47 [pm-daemon] pm-daemon starting; … grace=600s poll=60s tick=900s resolutions=120s
max_attempts=2`, followed by a clean tick summary and `resolutions exit=0`. The daemon is left
running (not stopped).

## Full smoke contract (verbatim)

```
✅ T1: node --check pm-daemon.js
✅ T2: bash -n queue-phase.sh
✅ T3: SF-15 fallback present in queue-phase.sh
✅ T4: SF-14 guard present in pm-daemon.js
✅ T5: test-sf15.sh (SF-15 hermetic) PASS
✅ T6: test-sf14.sh (SF-14 hermetic) PASS
✅ T-reg: integration-test-pm.sh green
✅ T-reg: integration-test.sh green
✅ T-reg: test-numenv.sh green
✅ T-daemon: pm-daemon status=online
✅ T-learn: SF-15 + SF-14 marked resolved in learnings.md
---
ALL PASS
```

## Acceptance criteria

- [x] SF-15: `test-sf15.sh` proves daemon-env dispatch → local dispatcher AND mock injection still routes to the mock.
- [x] SF-14: `test-sf14.sh` proves a pre-archived shim mid-scan → no escaping exception, cycle completes, `claims[taskId]` cleared.
- [x] `node --check services/pm-daemon.js` passes; `bash -n scripts/queue-phase.sh` passes.
- [x] Full existing regression green (no weakened assertions).
- [x] `pm2 restart pm-daemon --update-env` done; `pm-daemon` status=online, clean logs.
- [x] SF-15 + SF-14 marked resolved in `.planning/learnings.md` with commit SHA (`b8abf35`).
- [x] Commits with prefix `[orch-daemon-fixes-01]`.

## Commits (local only, no push)

- `b8abf35` — `services/pm-daemon.js` + `scripts/queue-phase.sh` + `scripts/test-sf14.sh` + `scripts/test-sf15.sh`.
- `99e7c6e` — `.planning/learnings.md` (SF-15/SF-14 resolved).
- (this `result.md` commit).

## Scope

Only touched `scripts/queue-phase.sh`, `services/pm-daemon.js`, the two new `scripts/test-sf*.sh`,
`.planning/learnings.md`, and this `result.md`. Did not touch out-of-scope findings
(SF-11/12/13), wsl2, other projects' `.planning/`, `.planning/archive/**`, or `brief.md`. The
daemon was restarted (required) and left online.
