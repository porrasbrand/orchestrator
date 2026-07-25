# Phase r1r2-06: Integration Chain Tests + Resident-PM Docs — Result

## Summary

Final phase of `orchestrator-r1r2`. Delivered `scripts/integration-test-pm.sh` (5
end-to-end chain scenarios, 27 assertions across component seams), the Resident-PM
section in CLAUDE.md, the operator runbook at `docs/RESIDENT-PM-RUNBOOK.md`, and the
header refresh on `config/notify-hook.sh.example`. This phase's wrapper suite is 22/22
green; all five per-component suites still pass (11 + 16 + 19 + 18 + 32 = 96).

## Findings (spec-mandated instead of a fix)

### F1 — `PM_GRACE_PERIOD=0` is silently rejected by `numEnv()`

`services/pm-daemon.js` uses `Number.isFinite(v) && v > 0` — so `PM_GRACE_PERIOD=0`
falls back to the default 600. The r1r2-06 spec suggested `PM_GRACE_PERIOD=0` for the
S1 scenario to claim instantly, but that's not achievable with the shipped daemon
without editing it. The spec forbids modifying shipped scripts and requires
documenting the finding.

- **Impact:** minor. Zero is a nonsense grace period in production anyway (would race
  interactive sessions). All positive integers ≥ 1 work correctly.
- **Workaround (in the test):** `PM_GRACE_PERIOD=1` + `sleep 2` before invoking
  `pm-daemon.js --once`. The mtime is comfortably outside the 1 s window.
- **Not-XFAIL:** the working `grace=1` + sleep workaround makes S1 pass all four of
  its assertions without XFAILing anything. Recording the finding for future
  daemon-hardening (r3+): `v >= 0` or a separate "grace disabled" sentinel.

No cross-component bugs were found. Every scenario passes with 0 XFAIL.

## Decisions

- **Every integration assertion spans ≥ 2 components.** Per-component behaviour is
  already covered by the five phase suites (96 tests). This suite exercises the
  **seams** — the places where one component's output has to match another's
  contract.
- **Shared harness, per-scenario reset.** One `mktemp -d` per suite run; `reset_proj`
  wipes / rebuilds the fake project between scenarios so each is independent and the
  suite is idempotent.
- **Real components, mocked externals.** `services/pm-daemon.js`,
  `scripts/pm-iterate.sh`, `scripts/slack-poll-resolutions.sh`, `scripts/notify.sh`
  and `config/notify-hook.sh` all run **live** in each scenario. Externals stubbed:
  `PM_ITERATE_MOCK` for the claude CLI, `SLACK_MOCK` for outbound Slack,
  `SLACK_REPLIES_MOCK` for inbound Slack, an on-PATH mock `add-task.sh`.
- **Blocked-project check in S4** proves the abort path is honored end-to-end: the
  poller blocks the project's status, and a subsequent `pm-daemon.js --once` tick
  does not spawn `pm-iterate` for that project (its tick cycle sees `blocked` and
  skips).
- **Docs are grounded in real file / env / event names.** Every env knob in the
  CLAUDE.md table was pulled from `services/pm-daemon.js` / `scripts/pm-iterate.sh`
  (no inventions); every event name in the runbook Failure Playbook is one the code
  actually appends.

## Files Created

- `scripts/integration-test-pm.sh` (executable, `bash -n` clean)
- `docs/RESIDENT-PM-RUNBOOK.md`
- `.planning/phases/r1r2-06-integration-docs/smoke-tests.sh` (22 assertions)
- `.planning/phases/r1r2-06-integration-docs/result.md` (this file)
- `.planning/phases/r1r2-06-integration-docs/result.json`

## Files Modified

- `CLAUDE.md` — APPENDED one new `## Resident PM (daemon-first operation)` section
  (division of labor, iteration semantics clarification, override consumption,
  kill switches, full env-tuning table). No existing section touched.
- `config/notify-hook.sh.example` — header comment ONLY (points at
  `config/notify-hook.sh` as the shipped Slack hook and clarifies this remains a
  minimal template). No code changes below the header — verified by
  `git diff -U0` grep for non-comment lines returning empty.

## Do-NOT-Touch surface verified

`git diff` on `scripts/pm-iterate.sh`, `services/pm-daemon.js`,
`scripts/slack-poll-resolutions.sh`, `scripts/queue-phase.sh`,
`scripts/register-project.sh`, `scripts/notify.sh`, `config/notify-hook.sh`,
`scripts/run-pm-daemon.sh` — all empty in this phase.

## Test Output

### Integration suite: PASS=27 FAIL=0 scenarios=5

```
S1: response → grace-claim → REAL pm-iterate → archived
  ✅ S1.1: ledgered response archived after --once
  ✅ S1.2: non-ledger response untouched
  ✅ S1.3: iterations.jsonl records the response iteration
  ✅ S1.4: real pm-iterate wrote transcript log

S2: escalation → notify → G5 SKIP → continue → G5 reopened
  ✅ S2.1: notify.sh wrote AI-escalation heading
  ✅ S2.2: 🚨 posted to SLACK_MOCK (r2-04 hook end-to-end)
  ✅ S2.3: pm-iterate G5 gate closed by escalation event
  ✅ S2.4: escalation_resolved event appended
  ✅ S2.5: resolutions.jsonl continue line written
  ✅ S2.6: ▶️ ACK posted threaded
  ✅ S2.7: pm-iterate recorder invoked with --trigger resolution
  ✅ S2.8: G5 reopened — subsequent tick runs (RAN:)

S3: checkpoint → G6 SKIP → continue → checkpoint_acknowledged → G6 reopened
  ✅ S3.1: pm-iterate G6 gate closed by checkpoint event
  ✅ S3.2: checkpoint_acknowledged event appended (NOT escalation_resolved)
  ✅ S3.3: escalation_resolved NOT appended (checkpoint-only path)
  ✅ S3.4: ▶️ ACK posted
  ✅ S3.5: recorder invoked with --trigger resolution
  ✅ S3.6: G6 reopened — subsequent tick runs (RAN:)

S4: abort → blocked + phase_aborted + notify; daemon then ignores
  ✅ S4.1: status.json blocked with U_HUMAN in reason
  ✅ S4.2: phase_aborted event appended
  ✅ S4.3: notifications.md gained 'Phase aborted'
  ✅ S4.4: recorder NOT invoked on abort
  ✅ S4.5: daemon --once tick did NOT spawn pm-iterate for blocked project

S5: kill switches (paused / interrupt.json), reversible
  ✅ S5.1: paused → daemon spawns nothing
  ✅ S5.2: pm-iterate SKIP: paused (kill switch honored)
  ✅ S5.3: interrupt.json → SKIP: interrupted
  ✅ S5.4: kill switches reversible — iterate now proceeds
```

### r1r2-06 wrapper: 22/22

```
T1: integration-test-pm.sh syntax clean + executable
T2: integration suite exit 0 + scenarios=5 FAIL=0
T3: idempotent re-run still green
T4a–T4e: CLAUDE.md heading, PM_GRACE_PERIOD row, iteration-semantics clarification, all three kill switches, override-consumption instruction
T5a + T5×6 grep landmarks in RESIDENT-PM-RUNBOOK.md (pm2 restart pm-daemon, slack.env, register-project.sh, Deploy, Monitor, Failure playbook)
T6a: notify-hook.sh.example header references config/notify-hook.sh
T6b: git diff shows ONLY comment lines
T7 × 5: r1-01 11/11, r1-02 16/16, r1-03 19/19, r2-04 18/18, r2-05 32/32
```

Both suites idempotent on re-run.

## Acceptance Criteria — Status

- [x] `scripts/integration-test-pm.sh` runs hermetically from repo root (no network,
  no real Slack, no real claude); exits 0 with `scenarios=5` and `FAIL=0`.
- [x] S1: ledger-gated grace claim → REAL pm-iterate ran → response left `new/`;
  non-ledgered response untouched (S1.1–S1.4).
- [x] S2: escalation → notify → G5 SKIP → Slack continue → escalation_resolved + ACK
  + `--trigger resolution` invocation → G5 reopened (S2.1–S2.8).
- [x] S3: checkpoint round-trip via G6 with `checkpoint_acknowledged`
  (S3.1–S3.6).
- [x] S4: abort blocks the project AND the daemon subsequently ignores it
  (S4.1–S4.5).
- [x] S5: both kill switches stop the loop; both reversible (S5.1–S5.4).
- [x] Every scenario asserts across ≥ 2 components; no shipped script modified
  (git diff on Do-NOT-Touch surface = empty).
- [x] CLAUDE.md gains the Resident PM section with division of labor,
  one-iteration clarification, override-consumption instruction, kill switches,
  and full `PM_*` env table.
- [x] `docs/RESIDENT-PM-RUNBOOK.md` covers Deploy / Monitor / Failure grounded in real
  filenames / dirs / event names.
- [x] `config/notify-hook.sh.example` header updated; below-header byte-identical
  (T6b `git diff` proof).
- [x] Wrapper smoke-tests.sh exits 0 (22/22); five prior suites still green
  (11/16/19/18/32); `bash -n` clean on both new shell files.

## Blockers

None. Project `orchestrator-r1r2` is COMPLETE.
