# Phase r1-01: Dispatch Ledger & Project Registry — Result

## Summary

Built the two foundation scripts (`register-project.sh`, `queue-phase.sh`), the hermetic
mock (`mock-add-task.sh`), and the smoke-test harness. All 7 spec test cases plus a bonus
`--worker wsl2` routing test pass; total 11 assertions green. Smoke tests are hermetic
(state under `mktemp -d`, cleaned via `trap`) and re-running the suite passes identically.

## Decisions

- **task_id stored as JSON string.** IDs are 18-digit nanosecond epochs; encoding as a
  number would lose precision in any downstream JS consumer. `queue-phase.sh` uses
  `jq -c -n --arg task_id "$TASK_ID"` so the value is always a string, and the test
  checks `(.task_id|type) == "string"`.
- **Registry writes are atomic.** `register-project.sh` writes to a `mktemp` sibling and
  `mv`s into place so a mid-write interrupt can't leave a half-written array.
- **Idempotent `add`.** Re-adding an existing name updates in place and preserves the
  original `registered_at` (via `(map(select(.name==$name)) | first).registered_at // $now`).
- **Worker default resolution.** `queue-phase.sh` looks up the worker in this order:
  explicit `--worker` flag → registry entry for the project → `hetzner`.
- **Fail-fast on ambiguous dispatch output.** `queue-phase.sh` treats *any* of these as
  failure and writes NO ledger line: dispatcher non-zero exit, `Task saved locally:`
  fallback line present, missing `Task queued:` line, or missing `ID: <digits>` line.
- **Skip event write if `.planning/` missing.** Per spec, a project without a `.planning/`
  dir gets a warning to stderr; the ledger line still records the dispatch.

## Files Created

- `scripts/register-project.sh` (executable, `bash -n` clean)
- `scripts/queue-phase.sh` (executable, `bash -n` clean)
- `templates/test-fixtures/mock-add-task.sh` (honours `MOCK_ADDTASK_FAIL` and `MOCK_ADDTASK_EXIT`)
- `.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh` (11 assertions across 8 tests)
- `.planning/phases/r1-01-dispatch-ledger/result.md` (this file)
- `.planning/phases/r1-01-dispatch-ledger/result.json`

## Files Modified

None. (Per spec — no existing script touched.)

## Test Output

```
Test 1: register + get round-trip
  ✅ PASS: T1: register + get
Test 2: idempotent re-add (still exactly 1 entry)
  ✅ PASS: T2: idempotent re-add
Test 3: successful dispatch writes ledger + event
  ✅ PASS: T3a: ledger line valid
  ✅ PASS: T3b: events.jsonl phase_queued event
Test 4: ledger task_id matches the ID the dispatcher printed
  ✅ PASS: T4: ledger id == dispatcher id (783002612343721766)
Test 5: failed dispatch (exit 1) writes nothing
  ✅ PASS: T5a: queue-phase exited non-zero on dispatcher exit=1
  ✅ PASS: T5b: ledger unchanged on dispatcher exit=1
Test 6: local-fallback (Task saved locally) treated as failure
  ✅ PASS: T6a: queue-phase exited non-zero on local-fallback
  ✅ PASS: T6b: ledger unchanged on local-fallback
Test 7: deactivate flips flag
  ✅ PASS: T7: deactivate flips active=false
Test 8: --worker wsl2 routing
  ✅ PASS: T8: --worker wsl2 routes to add-task-local.sh

==================================
Smoke test summary: 11 passed, 0 failed
```

Second run: identical output. No state leak between runs (all state under `mktemp -d`
dirs cleaned by `trap cleanup EXIT`).

## Acceptance Criteria — Status

- [x] `register-project.sh add` creates `active-projects.json` with all 6 fields
  (`name`, `local_path`, `worker`, `remote_path`, `active`, `registered_at`); `get`/`list --json`
  return valid jq-parseable JSON; re-`add` is idempotent (T2); `deactivate` flips `active` to false (T7).
- [x] `queue-phase.sh` with the mock appends exactly one valid JSONL ledger line per successful
  dispatch, with `task_id` as a JSON string matching the mock's printed ID (T3a + T4).
- [x] `queue-phase.sh` appends a `phase_queued` event (with task_id) to the project's
  `.planning/events.jsonl` (T3b).
- [x] `queue-phase.sh` writes NO ledger line and exits 1 when the dispatch exits non-zero
  (T5) AND when it falls back to `Task saved locally:` (T6).
- [x] Worker routing: `--worker wsl2` invokes `add-task-local.sh` (T8); default resolves from
  the registry when the project is registered (T3, T4 use registry-default `hetzner`).
- [x] All state paths honour `ORCH_STATE_DIR` and `SUPER_AGENT_DIR` overrides; nothing
  written to the real `$HOME/.orchestrator` during tests (verified — trap cleanup, and
  `fresh_env` sets both env vars to `mktemp -d` subpaths).
- [x] `bash -n` passes on both scripts; smoke-tests.sh exits 0 with all tests passing.

## Blockers

None.
