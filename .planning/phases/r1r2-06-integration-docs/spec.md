# Phase r1r2-06: Integration Chain Tests + Resident-PM Docs

## Context

Project **orchestrator-r1r2** — see `.planning/brief.md` + `.planning/project.md`.
ALL implementation phases are complete: r1-01 (ledger/registry), r1-02 (pm-iterate),
r1-03 (pm-daemon), r2-04 (Slack outbound hook), r2-05 (Slack inbound resolutions + G6).
The 5 per-component smoke suites are green (11+16+19+18+32 = 96 tests).

This FINAL phase delivers (a) an end-to-end integration suite that exercises the CHAINS
across components — the seams no per-component suite covers — and (b) the operator docs:
a "Resident PM" section in CLAUDE.md and a deploy/monitor/failure runbook. This is a
tests + docs phase: **you must NOT modify any shipped script or service** (see Do NOT
Touch). If an integration scenario exposes a real cross-component bug, do NOT fix it —
document it in result.md as a finding and mark that scenario XFAIL with a comment.

All tests hermetic: `PM_ITERATE_MOCK` (canned claude transcript), `SLACK_MOCK` (outbound
JSONL sink), `SLACK_REPLIES_MOCK` (inbound fixture), mock `add-task.sh` via PATH
override, `ORCH_STATE_DIR`/`SUPER_AGENT_DIR` overrides, `pm-daemon.js --once`.
$0 cost, no network, no lipo services, no real claude invocations.

## Prior Work Summary

Contracts you must honor — read, don't rediscover:

- **pm-daemon.js (r1-03 + r2-05):** knobs `PM_GRACE_PERIOD` (600), `PM_POLL_INTERVAL`
  (60), `PM_TICK_INTERVAL` (900), `PM_STALL_TIMEOUT` (14400), `PM_MAX_ATTEMPTS` (2),
  `PM_RESOLUTIONS_INTERVAL` (120), `PM_ITERATE_BIN`, `PM_RESOLUTIONS_BIN`. `--once` runs
  scan + tick + resolutions each exactly once, synchronously. Claims a response file only
  if it is still in `new/` after GRACE_PERIOD AND its task_id is in the dispatch ledger.
- **pm-iterate.sh (r1-02 + r2-05):** knobs `PM_MAX_ITER_PER_HOUR` (6), `PM_MAX_TURNS`
  (80), `PM_ITERATE_TIMEOUT` (1800), `PM_CLAUDE_MODEL`, `PM_CLAUDE_BIN`,
  `PM_ITERATE_MOCK`, `PM_ITERATE_MOCK_EXIT`. Guards print `SKIP: <reason>` + exit 0.
  G5 escalation gate: latest {ai_escalation_recommended, escalation_resolved} for the
  current phase; G6 checkpoint gate: latest {checkpoint, checkpoint_acknowledged,
  phase_queued} for the project. `--trigger resolution` bypasses both.
- **Kill switches:** `$ORCH_STATE_DIR/paused` (global — daemon cycles log + no-op,
  pm-iterate SKIPs) and `<project>/.planning/interrupt.json` (per-project pm-iterate SKIP).
- **slack-poll-resolutions.sh (r2-05, 3b056f0):** eligibility = threads entry AND a
  closed gate; commands continue/retry/abort/override; ACKs via SLACK_MOCK convention
  (`{"api":"chat.postMessage","payload":<payload>}` JSONL); cursor file
  `slack-resolutions-state.json`; abort → status blocked + `phase_aborted` + notify.sh,
  NO pm-iterate.
- **queue-phase.sh (r1-01):** treats add-task local-fallback ("Task saved locally:") as
  FAILURE; success requires the "Task queued:"/ID line from add-task.sh. Ledger line:
  `{ts, task_id, project, project_path, phase, worker}`.
- **House style:** `set -euo pipefail`, `T=$(mktemp -d)` + `trap ... EXIT`, PASS/FAIL
  counters, exit 0 only all-green, jq for JSON, `printf '%s\n'` for `-`-leading lines.

## Objective

1. `scripts/integration-test-pm.sh` — 5 hermetic end-to-end chain scenarios.
2. CLAUDE.md — new top-level section: **"Resident PM (daemon-first operation)"**.
3. `docs/RESIDENT-PM-RUNBOOK.md` — deploy / monitor / failure playbook.
4. `config/notify-hook.sh.example` — header updated to point at the shipped Slack hook.

## Implementation Steps

### 1. `scripts/integration-test-pm.sh` (the core deliverable)

One self-contained executable script, runnable from the repo root on any machine with
bash+jq+node. Shared hermetic harness built once in `T=$(mktemp -d)`:

- `ORCH_STATE_DIR=$T/state` with registry (`active-projects.json` pointing at a fake
  project `$T/proj` with `.planning/` status.json + events.jsonl), empty ledger,
  `slack-threads.json` (thread_ts `1000000000.000001`), `SLACK_MOCK=$T/slack-out.jsonl`,
  `SLACK_REPLIES_MOCK=$T/replies.json`.
- `SUPER_AGENT_DIR=$T/super-agent` with a fake responses dir layout (`tasks/responses/
  new|archive|claimed|failed` — mirror whatever pm-daemon.js actually reads; copy the
  layout from the r1-03 smoke suite) and a mock `add-task.sh` on PATH that prints the
  ID line queue-phase.sh expects.
- `PM_ITERATE_MOCK` canned transcripts so the REAL `scripts/pm-iterate.sh` runs its full
  guard chain without invoking claude; `PM_GRACE_PERIOD=0` so `--once` claims instantly.
- Each scenario gets a fresh copy of the fake project (helper `reset_proj`), so
  scenarios are independent and the suite is idempotent.

Do NOT re-test per-component behavior already covered by the 5 phase suites; every
assertion here must span at least two components. Scenarios (label output `S1..S5`,
each with numbered asserts feeding the shared PASS/FAIL counters):

- **S1 — response → grace-claim → iterate → archive:** ledger entry for task_id X;
  response file `new/X.json`; run `node services/pm-daemon.js --once` with
  `PM_GRACE_PERIOD=0`. Assert: the REAL pm-iterate.sh ran (mock transcript consumed /
  iteration logged), the response file left `new/` (archived/claimed per r1-03
  contract), and a non-ledgered response file in `new/` is untouched by the same run.
- **S2 — escalation → Slack notify → "continue" → resolution iterate:** append
  `ai_escalation_recommended` for the current phase; run `scripts/notify.sh
  ai_escalation_recommended $T/proj ...` (SLACK_MOCK) → assert threaded Slack post +
  notifications.md. Assert `pm-iterate.sh $T/proj --trigger tick` prints
  `SKIP: escalated-awaiting-human` (gate CLOSED end-to-end). Fixture a human `continue`
  reply; run the REAL `scripts/slack-poll-resolutions.sh` with `PM_ITERATE_BIN` =
  recorder. Assert: `escalation_resolved` event, resolutions.jsonl line, ▶️ ACK in
  SLACK_MOCK, recorder called once with `--trigger resolution`, and a real
  `pm-iterate.sh --trigger tick` now proceeds past G5 (gate reopened).
- **S3 — checkpoint → G6 pause → acknowledge → proceed:** append `checkpoint` event
  (latest); assert tick → `SKIP: checkpoint-awaiting-human`; fixture `continue`; run
  poller; assert `checkpoint_acknowledged` event (NOT escalation_resolved) + ACK +
  recorder call; assert tick now proceeds.
- **S4 — abort → blocked → daemon ignores project:** escalated project + `abort` reply;
  run poller. Assert: status.json blocked with the Slack user in the reason,
  `phase_aborted` event, "Phase aborted" in notifications.md + SLACK_MOCK, recorder NOT
  called. Then `pm-daemon.js --once` tick: assert NO pm-iterate spawn for the blocked
  project (daemon respects blocked state end-to-end).
- **S5 — kill switches:** create `$ORCH_STATE_DIR/paused`; assert `pm-daemon.js --once`
  spawns nothing AND direct `pm-iterate.sh` SKIPs. Remove `paused`; create
  `$T/proj/.planning/interrupt.json`; assert pm-iterate SKIPs for that project. Remove;
  assert an iterate proceeds again (switches are reversible).

Final line: `integration-test-pm: PASS=<n> FAIL=<m> scenarios=5`; exit 0 only if FAIL=0.

### 2. CLAUDE.md — "Resident PM (daemon-first operation)" section

Append ONE new `##` section (do not touch any existing section). Contents:

- **Division of labor:** interactive tmux session is primary; the daemon only claims
  responses still in `new/` after `PM_GRACE_PERIOD` whose task_id is in the dispatch
  ledger. Non-orchestrated tasks are ignored by construction.
- **ITERATION SEMANTICS (verbatim clarification):** one pm-iterate invocation = ONE
  phase advance — verify-and-complete OR verify-and-revise OR spec-and-queue counts as
  exactly one iteration; the daemon provides cadence, the headless PM never loops.
- **Override consumption (headless PM instruction):** when writing a revision spec,
  read `.planning/resolutions.jsonl`; if the newest entry for the current phase is
  `kind=override`, inject its `text` verbatim into the revision spec's Additional
  Guidance section and reference the reply user/ts.
- **Kill switches:** `~/.orchestrator/paused` (global), `<project>/.planning/
  interrupt.json` (per project), `pm2 stop pm-daemon` (process) — what each stops and
  how to reverse it.
- **Env tuning table:** every `PM_*` knob from pm-daemon.js and pm-iterate.sh with
  default + one-line effect (pull names/defaults from the scripts, do not invent).

### 3. `docs/RESIDENT-PM-RUNBOOK.md`

Operator-facing, three parts:
- **Deploy:** `scripts/register-project.sh` usage; `pm2 start scripts/run-pm-daemon.sh
  --name pm-daemon` (match run-pm-daemon.sh's actual interface); `$ORCH_STATE_DIR/
  slack.env` (`SLACK_BOT_TOKEN`, `SLACK_CHANNEL`, never committed); create the Slack
  channel + invite the bot; `pm2 restart pm-daemon` required after any
  services/pm-daemon.js change (pm-iterate/hook changes are picked up per-spawn).
- **Monitor:** `pm2 logs pm-daemon`, per-project `.planning/` (`iterations.jsonl` /
  transcript logs — use the real filenames pm-iterate writes), `scripts/ai-stats.sh`,
  the `#orchestrator` Slack thread per project.
- **Failure playbook:** response stuck in `claimed/`; files in `failed/`; give-up events
  after `PM_MAX_ATTEMPTS`; hourly rate-cap SKIPs; escalation flow recap (what fires
  `ai_escalation_recommended`, how to answer from Slack vs laptop). Ground every entry
  in actual r1-03/r2-05 behavior — cite the event names and dirs the code really uses.

### 4. `config/notify-hook.sh.example` — header only

Update the header comment block: note that a production Slack hook shipped in r2-04 at
`config/notify-hook.sh` (chat.postMessage, per-project threads, `SLACK_MOCK` for tests)
and this example remains a minimal template for custom hooks. No functional changes —
the file must stay byte-identical below the header comment.

### 5. Smoke tests → `.planning/phases/r1r2-06-integration-docs/smoke-tests.sh`

Thin wrapper (integration suite does the heavy lifting):
- T1: `bash -n scripts/integration-test-pm.sh` clean; file executable.
- T2: `scripts/integration-test-pm.sh` exits 0 and prints `scenarios=5` + `FAIL=0`.
- T3: re-run integration suite → still exits 0 (idempotent).
- T4: CLAUDE.md contains the "Resident PM" heading, the iteration-semantics
  clarification, all three kill switches, and a `PM_GRACE_PERIOD` row (env table proof).
- T5: docs/RESIDENT-PM-RUNBOOK.md exists with Deploy/Monitor/Failure sections;
  mentions `pm2 restart pm-daemon`, `slack.env`, and `register-project.sh`.
- T6: config/notify-hook.sh.example header mentions `config/notify-hook.sh`; the file
  below the header comment is unchanged vs git (`git diff` shows only comment lines).
- T7: regressions — all five prior suites green (11/16/19/18/32).

## Files to Create

- `scripts/integration-test-pm.sh` (executable)
- `docs/RESIDENT-PM-RUNBOOK.md`
- `.planning/phases/r1r2-06-integration-docs/smoke-tests.sh`
- `.planning/phases/r1r2-06-integration-docs/result.md` (+ result.json)

## Files to Modify

- `CLAUDE.md` — ONLY append the new Resident PM section (step 2)
- `config/notify-hook.sh.example` — ONLY the header comment (step 4)

## Do NOT Touch

- `scripts/pm-iterate.sh`, `services/pm-daemon.js`, `scripts/slack-poll-resolutions.sh`,
  `scripts/queue-phase.sh`, `scripts/register-project.sh`, `scripts/notify.sh`,
  `config/notify-hook.sh`, `scripts/run-pm-daemon.sh` — shipped and live; integration
  tests RUN them, never edit them. A cross-component bug found → result.md finding +
  XFAIL, not a fix.
- `/home/mp/awesome/super-agent` anything; `.planning/brief.md`
- No real network; no tokens anywhere; no new dependencies beyond bash/jq/node
- No `pm2 restart` needed (pm-daemon.js untouched)

## Cleanup

All test state under `mktemp -d`, removed via `trap ... EXIT`. Both suites idempotent.

## Expected Files Changed

```
scripts/integration-test-pm.sh
docs/RESIDENT-PM-RUNBOOK.md
CLAUDE.md
config/notify-hook.sh.example
.planning/phases/r1r2-06-integration-docs/smoke-tests.sh
.planning/phases/r1r2-06-integration-docs/result.md
.planning/phases/r1r2-06-integration-docs/result.json
```

## Acceptance Criteria

- [ ] `scripts/integration-test-pm.sh` runs hermetically from the repo root (no network,
      no lipo services, no real claude) and exits 0 with `scenarios=5 ... FAIL=0`.
- [ ] S1 proves the ledger-gated grace claim end-to-end: ledgered response → REAL
      pm-iterate ran → file left `new/`; non-ledgered response untouched.
- [ ] S2 proves the full escalation round-trip: notify → G5 SKIP → Slack continue →
      escalation_resolved + ACK + `--trigger resolution` call → G5 reopened.
- [ ] S3 proves the checkpoint round-trip via G6 with `checkpoint_acknowledged`.
- [ ] S4 proves abort blocks the project AND the daemon subsequently ignores it.
- [ ] S5 proves both kill switches stop the loop and are reversible.
- [ ] Every scenario asserts across ≥2 components; no shipped script/service modified
      (`git diff` on Do-NOT-Touch files is empty).
- [ ] CLAUDE.md gains the Resident PM section with division-of-labor, the one-iteration
      clarification, override-consumption instruction, kill switches, full PM_* table.
- [ ] docs/RESIDENT-PM-RUNBOOK.md covers deploy/monitor/failure per step 3, grounded in
      real filenames, dirs, and event names.
- [ ] notify-hook.sh.example: header updated, everything below it byte-identical.
- [ ] smoke-tests.sh exits 0; prior suites still green (11/16/19/18/32); `bash -n` clean
      on both new shell files.

## Smoke Tests

```bash
bash -n scripts/integration-test-pm.sh
scripts/integration-test-pm.sh                                  # scenarios=5 FAIL=0, exit 0
scripts/integration-test-pm.sh                                  # idempotent re-run, exit 0
grep -q 'Resident PM' CLAUDE.md && grep -q 'PM_GRACE_PERIOD' CLAUDE.md
grep -q 'pm2 restart pm-daemon' docs/RESIDENT-PM-RUNBOOK.md
grep -q 'config/notify-hook.sh' config/notify-hook.sh.example
bash .planning/phases/r1-01-dispatch-ledger/smoke-tests.sh      # 11/11
bash .planning/phases/r1-02-pm-iterate/smoke-tests.sh           # 16/16
bash .planning/phases/r1-03-pm-daemon/smoke-tests.sh            # 19/19
bash .planning/phases/r2-04-slack-notify/smoke-tests.sh         # 18/18
bash .planning/phases/r2-05-slack-resolutions/smoke-tests.sh    # 32/32
```

## Completion Instructions

1. `chmod +x scripts/integration-test-pm.sh`; syntax-check both shell files; run THIS
   phase's smoke-tests.sh AND all five prior suites — all green.
2. Write result.md + result.json in this phase dir (include any XFAIL findings).
3. Commit with prefix `[orchestrator-r1r2-06]` and push to origin master.
