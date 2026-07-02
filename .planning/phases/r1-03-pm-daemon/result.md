# Phase r1-03: Resident PM Daemon — Result

## Summary

Built `services/pm-daemon.js` (stdlib-only Node), `scripts/run-pm-daemon.sh` (pm2
wrapper), and the mock `mock-pm-iterate.sh`. Also applied the small r1-02 bugfix so
`pm-iterate.sh --dry-run` no longer appends a `pm_iteration` event. Both suites green:
r1-03 = 19/19; r1-02 = 16/16 (regression suite still passes).

## Decisions

- **Atomic claim via `fs.renameSync`.** ENOENT is silently treated as "someone else took
  it" so a second daemon (or a live interactive session that beat us to it) never causes
  a crash.
- **Grace period + ledger lookup + registry active-check** are ALL required before claim.
  Non-ledger responses, ledger responses younger than grace, and deactivated projects are
  all left untouched in `new/`.
- **Single-flight is enforced in the daemon code itself** (a plain `for`-loop over
  claimed files, each invocation via `spawnSync`). The per-project flock inside
  `pm-iterate.sh` is defence-in-depth for concurrent daemon instances or hand-triggers.
- **Disposition detects SKIP-guarded exit 0.** If `pm-iterate` prints a line starting
  with `SKIP:` (and exits 0), the daemon does NOT archive AND does NOT bump attempts —
  the file stays in `claimed/` for the next cycle. This is critical for the hourly-cap
  case (spending would rate-cap immediately even though the response is real).
- **Retry semantics: `PM_MAX_ATTEMPTS` (2) attempts before give-up.** Attempts persist
  in `daemon-state.json` (`{claims: {<task_id>: {attempts, last_exit, last_ts}}}`).
  On give-up: move to `failed/`, append `pm_daemon_gave_up` (with task_id + phase +
  attempts + last_exit) to the project's events.jsonl, log loudly, and clear the state
  entry.
- **Tick actionability.** Only `pending` / `specified` / `verifying` phases are poked
  unconditionally. `queued` phases are poked only if the newest `phase_queued` event for
  that phase is older than `PM_STALL_TIMEOUT` (14400 s). Anything else (`complete`,
  `blocked`, unreadable status.json) is skipped. Steady-state cost is ~zero.
- **`--once` mode** runs one scan + one tick synchronously and exits. This is the mode
  the smoke tests use; daemon mode uses `setInterval` loops.
- **pm-iterate.sh bugfix** — moved the `pm_iteration` event write to AFTER the `--dry-run`
  short-circuit so a dry-run has zero side effects beyond the prompt file.

## Files Created

- `services/pm-daemon.js` (stdlib-only Node, `node --check` clean)
- `scripts/run-pm-daemon.sh` (pm2 wrapper, `bash -n` clean)
- `templates/test-fixtures/mock-pm-iterate.sh` (`bash -n` clean; JSON-logs each argv)
- `.planning/phases/r1-03-pm-daemon/smoke-tests.sh` (19 assertions across 9 tests)
- `.planning/phases/r1-03-pm-daemon/result.md` (this file)
- `.planning/phases/r1-03-pm-daemon/result.json`

## Files Modified

- `scripts/pm-iterate.sh` — ONLY the dry-run bugfix (move event append below the
  dry-run short-circuit). No other changes.

## Test Output

### r1-03 (this phase): 19/19

```
Test 1: claim + iterate + archive
  ✅ PASS: T1a: 111.json archived
  ✅ PASS: T1b: mock invoked with --trigger response
  ✅ PASS: T1c: mock invoked with projA path
Test 2: non-ledger response untouched
  ✅ PASS: T2: non-ledger 999.json left in new/
  ✅ PASS: T2: mock log empty
Test 3: younger than grace untouched
  ✅ PASS: T3: fresh 111.json left in new/ (grace=3600)
Test 3b: deactivated project response untouched
  ✅ PASS: T3b: deactivated projA response left in new/
Test 4: retry then give-up (PM_MAX_ATTEMPTS=2)
  ✅ PASS: T4a: after attempt 1, 222.json still in claimed/
  ✅ PASS: T4b: attempts=1 in daemon-state.json
  ✅ PASS: T4c: after attempt 2, 222.json moved to failed/
  ✅ PASS: T4d: pm_daemon_gave_up event landed with task_id=222 attempts=2
Test 5: SKIP stdout leaves claim in place
  ✅ PASS: T5a: SKIP: leaves 111.json in claimed/
  ✅ PASS: T5b: no attempts recorded for SKIP
Test 6: tick actionability
  ✅ PASS: T6a: only projA(specified) poked; projB(queued+fresh) not poked
  ✅ PASS: T6b: projB(queued+stall) poked after aging event
Test 7: paused kill switch
  ✅ PASS: T7: paused blocks scan + tick
Test 8: pm-iterate.sh --dry-run no longer appends event
  ✅ PASS: T8: events.jsonl line count unchanged after --dry-run
Test 9: single-flight enforcement (sequential pm-iterate calls)
  ✅ PASS: T9a: two invocations recorded
  ✅ PASS: T9b: pm-iterate invocations sequential (>= 0.4s apart)

Smoke test summary: 19 passed, 0 failed
```

Re-run: identical (19/19).

### r1-02 (regression): 16/16 — the bugfix did not break the prior suite.

## Acceptance Criteria — Status

- [x] Ledger-matched response older than grace → claimed → mock pm-iterate invoked once
  with `--trigger response --response-file <claimed-path>` and correct project_path,
  archived on exit 0. (T1a, T1b, T1c)
- [x] Non-ledger AND ledger-younger-than-grace responses both left untouched in `new/`.
  (T2, T3)
- [x] Response for a DEACTIVATED registry project left untouched. (T3b)
- [x] Failure path: `MOCK_PM_EXIT=1` leaves in `claimed/` attempts=1; at MAX_ATTEMPTS
  moves to `failed/` and appends `pm_daemon_gave_up` with task_id + attempts to events.
  (T4a–T4d)
- [x] `SKIP:` stdout (exit 0) leaves file in `claimed/` with attempts unchanged.
  (T5a, T5b)
- [x] Tick: `specified` → tick invocation; `queued`+fresh → no; `queued`+stalled → yes.
  (T6a, T6b)
- [x] `paused` file → `--once` performs no claims and no ticks. (T7)
- [x] Two responses in one cycle → pm-iterate invocations sequential; no overlap.
  (T9a, T9b)
- [x] `pm-iterate.sh --dry-run` no longer appends events (T8), r1-02 suite still
  16/16.
- [x] `bash -n` clean on shell files; `node --check services/pm-daemon.js` clean;
  smoke-tests.sh exits 0.

## Blockers

None.
