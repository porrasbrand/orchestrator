# Phase r1-02: Headless PM Iteration Runner — Result

## Summary

Built `scripts/pm-iterate.sh` with all 5 guardrails (pause / interrupt / non-blocking
per-project flock / hourly cap / escalation gate) and a hermetic smoke suite that never
invokes real `claude`. 16/16 assertions pass across all 8 spec test cases; re-run
identical. Exit codes propagate from the mock (and `timeout` in real mode).

## Decisions

- **Guard order matches spec exactly.** paused → interrupt → flock → hourly cap →
  escalation. First hit prints `SKIP: <reason>` and exits 0; nothing else runs, no
  transcript, no ledger line.
- **Non-blocking flock via fd exec.** `exec {LOCKFD}>"$LOCK_FILE"; flock -n "$LOCKFD"`
  so the lock is held through prompt build, invocation, and ledger write; the fd stays
  open until the shell exits, releasing atomically.
- **Hourly cap counts only THIS project.** `jq -r 'select(.project==$p) | .ts'` +
  per-line epoch compare against `now - 3600`. Old lines and other projects don't count
  (verified in T5b).
- **Escalation gate uses last-event semantics.** For the current phase, look at the last
  event that is either `ai_escalation_recommended` or `escalation_resolved`. If that
  latest one is `ai_escalation_recommended`, the gate is closed. `--trigger resolution`
  bypasses it. A subsequent `escalation_resolved` re-opens it (both verified in T7).
- **Prompt file is written BEFORE guard-5 timing costs anything.** Guards run before any
  file write except state-dir creation. The `iteration_started` event is written just
  before the mock/real invocation (after prompt build).
- **`--dry-run` writes prompt + event, skips invocation and ledger.** So a caller can
  inspect what would be sent to claude without consuming turns.
- **Mock mode is the ONLY code path exercised in tests.** `PM_ITERATE_MOCK` is always set
  in smoke tests; the real `claude` CLI is never invoked. `PM_ITERATE_MOCK_EXIT` lets
  tests prove exit propagation (rc=7 in T8a).
- **bash's `printf` builtin does not understand `-- '- ...'`.** Rewrote every
  `printf '- …'` as `printf '%s\n' '- …'` to avoid printf treating the literal dash as
  an option flag.

## Files Created

- `scripts/pm-iterate.sh` (executable, `bash -n` clean)
- `templates/test-fixtures/mock-pm-transcript.txt` (hermetic mock payload)
- `.planning/phases/r1-02-pm-iterate/smoke-tests.sh` (16 assertions across 8 tests)
- `.planning/phases/r1-02-pm-iterate/result.md` (this file)
- `.planning/phases/r1-02-pm-iterate/result.json`

## Files Modified

None. (Per spec — no existing script touched.)

## Test Output

```
Test 1: paused kill switch
  ✅ PASS: T1: SKIP: paused; no transcript, no ledger
Test 2: interrupt.json
  ✅ PASS: T2: SKIP: interrupted; no ledger
Test 3: normal mock run
  ✅ PASS: T3a: RAN: exit=0
  ✅ PASS: T3b: iterations.jsonl line valid
  ✅ PASS: T3c: transcript == mock content
Test 4: --response-file inlined into prompt
  ✅ PASS: T4a: prompt contains response-file JSON marker
  ✅ PASS: T4b: prompt contains ONE-iter rule + queue-phase-only rule + name/trigger
Test 5: hourly cap
  ✅ PASS: T5a: 3rd call rate-capped after 2 iterations
  ✅ PASS: T5b: old line does not count toward hourly cap
Test 6: lock contention (background slow mock)
  ✅ PASS: T6: SKIP: locked while another holder
Test 7: escalation gate
  ✅ PASS: T7a: tick blocked by escalation
  ✅ PASS: T7b: --trigger resolution bypasses escalation
  ✅ PASS: T7c: escalation_resolved unblocks tick
Test 8: mock exit propagation + dry-run
  ✅ PASS: T8a: PM_ITERATE_MOCK_EXIT=7 propagates rc=7
  ✅ PASS: T8b: ledger records exit_code:7
  ✅ PASS: T8c: --dry-run prints DRYRUN, no ledger append

==================================
Smoke test summary: 16 passed, 0 failed
```

Re-run: identical (16/16). No state leak between runs; every `T=$(mktemp -d)` cleaned
by `trap cleanup EXIT`.

## Acceptance Criteria — Status

- [x] Guard order + messages exactly as specified; every guard-skip prints `SKIP: <reason>`
  and exits 0 without writing a transcript or iterations.jsonl line (T1, T2, T6, T7a).
- [x] Concurrent second invocation while the lock is held skips with `SKIP: locked`
  (T6 — background flock holds the lock while a foreground pm-iterate.sh calls).
- [x] Hourly cap counts ONLY this project's iterations within 3600 s; older lines and
  other projects don't count; cap reached → `SKIP: rate-capped...` (T5a, T5b).
- [x] Escalation gate: unresolved `ai_escalation_recommended` blocks `tick`/`response`
  but NOT `--trigger resolution`; subsequent `escalation_resolved` unblocks all triggers
  (T7a, T7b, T7c).
- [x] Prompt file contains: the ONE-iteration rule, the queue-phase.sh-only dispatch
  rule, project path/name/trigger, and (when `--response-file` given) the inlined
  response JSON (T4a, T4b).
- [x] Mock run writes transcript, appends a valid iterations.jsonl line (jq-parseable,
  correct project/trigger/exit_code), prints `RAN: exit=0 ...`, and
  `PM_ITERATE_MOCK_EXIT=7` propagates exit 7 while still logging `exit_code:7`
  (T3a, T3b, T3c, T8a, T8b).
- [x] `--dry-run` writes the prompt but no transcript and no iterations line (T8c).
- [x] `bash -n` clean; smoke-tests.sh exits 0, all tests pass, nothing written outside
  the temp dirs.

## Blockers

None.
