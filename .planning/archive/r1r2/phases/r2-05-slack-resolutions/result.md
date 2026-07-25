# Phase r2-05: Slack Reply Polling → Resolutions — Result

## Summary

Shipped `scripts/slack-poll-resolutions.sh` (the inbound half of R2) plus the small
supporting edits: G6 checkpoint gate in `scripts/pm-iterate.sh`, `phase_aborted` event
in `scripts/notify.sh`, and daemon wiring in `services/pm-daemon.js`. 32/32 hermetic
assertions pass; all prior suites still green (11 + 16 + 19 + 18 = 64/64).

## Decisions

- **Eligibility check runs before any network call.** Only projects with a
  `slack-threads.json` entry AND at least one closed gate (escalation or checkpoint)
  are polled. Blocked/aborted projects are NOT polled (per Level-0 learnings —
  unblocking requires a laptop session).
- **Cursor is per-project last_ts.** After each batch we advance to the max `.ts` seen
  in the thread (including the parent + bot messages). A re-run with the same fixture
  is a complete no-op — verified in T4 across events, resolutions, mock ACKs, and mock
  pm-iterate call log.
- **Command grammar acts on the first line only.** `continue` / `retry` → kind
  `continue`; `abort` → kind `abort`; `override: <text>` captures the rest verbatim
  (case-insensitive prefix strip); anything else → kind `unrecognized`. Bots and the
  parent message are dropped before parsing.
- **Gate detection & release** reuses the same jq semantics as G5/G6 so poller and
  runner agree exactly. `escalation_resolved` when the escalation gate was closed;
  `checkpoint_acknowledged` when the checkpoint gate was closed; both if both.
- **Abort disposition (per spec):** append resolutions.jsonl line, atomically write
  status.json (`phases[PHASE].status="blocked"`, `blocked=true`,
  `blocked_reason="aborted via Slack by <user>"`, `updated=<today>`), append
  `phase_aborted` event, run `scripts/notify.sh phase_aborted ...` (that's the Slack
  confirmation — no separate ACK). **No pm-iterate** on abort.
- **G6 checkpoint gate.** Latest of `{checkpoint, checkpoint_acknowledged,
  phase_queued}` decides the gate. `--trigger resolution` bypasses it. A
  `phase_queued` after a checkpoint keeps the gate OPEN — backward-compat with
  projects that were resumed via an interactive session before r2-05.
- **`phase_aborted` in notify.sh** is a two-line edit only. `notify-hook.sh` renders
  unknown events with 🔔 already, so no hook change was required.
- **Daemon wiring** adds `resolutionsCycle()` on `PM_RESOLUTIONS_INTERVAL` (120 s
  default). If `PM_RESOLUTIONS_BIN` is missing / non-executable, the cycle silently
  no-ops so bare installs don't error.
- **Never leaks the token.** The poller only ever passes `$SLACK_BOT_TOKEN` inside a
  curl `Authorization` header; `set -x` is never enabled; nothing echoes or logs the
  header. Verified with synthetic `xoxb-TESTSECRET789` in T12.

## Files Created

- `scripts/slack-poll-resolutions.sh` (executable, `bash -n` clean)
- `.planning/phases/r2-05-slack-resolutions/smoke-tests.sh` (32 assertions across 12+regression tests)
- `.planning/phases/r2-05-slack-resolutions/result.md` (this file)
- `.planning/phases/r2-05-slack-resolutions/result.json`

## Files Modified

- `scripts/pm-iterate.sh` — added G6 checkpoint gate ONLY. Rule: latest of
  `{checkpoint, checkpoint_acknowledged, phase_queued}`; if `checkpoint` AND trigger
  != `resolution` → `SKIP: checkpoint-awaiting-human`.
- `scripts/notify.sh` — added `phase_aborted` to `VALID_EVENTS`, added a `phase_aborted)`
  arm in `format_message` → `Phase aborted: ${phase}`, added a line in usage(). No
  other change; existing event types byte-compatible.
- `services/pm-daemon.js` — added `PM_RESOLUTIONS_INTERVAL` + `PM_RESOLUTIONS_BIN`
  knobs, a `resolutionsCycle()` (paused-file check, bin executability check, spawnSync
  + log summary + per-cycle try/catch), and wired it into both `--once` and daemon
  mode. Startup banner logs the new interval.

## Test Output — r2-05: 32/32

```
T1: not configured → graceful no-op                         ✅
T2a: eligible=0                                              ✅
T2b: no ACK posted                                           ✅
T3a: escalation_resolved event appended                      ✅
T3b: resolutions.jsonl line correct                          ✅
T3c: ▶️ ACK posted threaded under thread_ts                  ✅
T3d: mock pm-iterate called with --trigger resolution        ✅
T4: idempotent (all counters stable)                         ✅
T5a: override text captured verbatim                         ✅
T5b: gate-release event carries resolution=override          ✅
T6a: status.json blocked with user in reason                 ✅
T6b: phase_aborted event appended                            ✅
T6c: notify.sh recorded Phase aborted                        ✅
T6d: pm-iterate NOT called on abort                          ✅
T7a: 🤖 help ACK posted                                       ✅
T7b: no resolutions.jsonl line written                       ✅
T7c: no gate-release event written                           ✅
T8a: parent + bot ignored (no actions)                       ✅
T8b: cursor advanced to max seen ts                          ✅
T9a: checkpoint gate closes tick                             ✅
T9b: --trigger resolution bypasses G6                        ✅
T9c: checkpoint_acknowledged reopens gate                    ✅
T9d: phase_queued after checkpoint reopens gate (compat)     ✅
T10a: checkpoint_acknowledged event appended                 ✅
T10b: pm-iterate invoked                                     ✅
T11a: PM_RESOLUTIONS_BIN executed once (daemon --once)       ✅
T11b: --once clean with missing bin                          ✅
T12: token string absent from all poller output              ✅

Regressions:
  R1-01 still 11/11                                          ✅
  R1-02 still 16/16                                          ✅
  R1-03 still 19/19                                          ✅
  R2-04 still 18/18                                          ✅

Smoke test summary: 32 passed, 0 failed
```

## Acceptance Criteria — Status

- [x] Poller without `SLACK_REPLIES_MOCK` + no slack.env → exit 0 with skip line (T1).
- [x] Project with threads entry but no closed gate → `eligible=0`, no fetch, no ACK,
  cursor file untouched (T2a, T2b).
- [x] Escalation + `continue` → escalation_resolved event with (phase, source=slack,
  user, reply_ts, resolution), resolutions.jsonl written, ▶️ ACK threaded, cursor
  advanced, mock pm-iterate called with `--trigger resolution` (T3a–T3d).
- [x] Immediate re-run with same fixture = complete no-op across events, resolutions,
  ACKs, pm-iterate calls (T4).
- [x] `override: use bearer auth` → kind=override + text exact, gate-release event
  resolution=override (T5a, T5b).
- [x] `abort` → status.json blocked with Slack user in `.blocked_reason`;
  `phase_aborted` event; notifications.md gains "Phase aborted"; pm-iterate NOT
  called (T6a–T6d).
- [x] Unrecognized → 🤖 help ACK only; no events, no resolutions line (T7a–T7c).
- [x] Parent + `bot_id` messages ignored; cursor still advances to max seen ts
  (T8a, T8b).
- [x] G6: checkpoint gate closes tick; resolution bypasses; `checkpoint_acknowledged`
  reopens; `phase_queued` after checkpoint also reopens (T9a–T9d).
- [x] Checkpoint-gated + `continue` → `checkpoint_acknowledged` event AND pm-iterate
  invoked (T10a, T10b).
- [x] `pm-daemon.js --once` runs `PM_RESOLUTIONS_BIN` exactly once; missing bin →
  clean silent exit (T11a, T11b).
- [x] Synthetic `xoxb-TESTSECRET789` never appears in poller stdout/stderr (T12).
- [x] `bash -n` clean on all shell files; `node --check` clean on pm-daemon.js;
  smoke-tests.sh exits 0; r1-01/r1-02/r1-03/r2-04 all still green (regression block).

## Blockers

None.
