# Phase r2-04: Slack Notify Hook — Result

## Summary

Built `config/notify-hook.sh` (Slack outbound hook), added the missing `checkpoint`
event to `scripts/notify.sh`, and wrote 18 hermetic assertions across 10 tests — all
green. All three prior R1 suites still pass (11 + 16 + 19 = 46 assertions), verified
by the smoke-tests script itself.

## Decisions

- **Graceful no-op is the default.** If neither `SLACK_MOCK` is set nor slack.env
  provides token+channel, the hook prints one stderr line and exits 0. `notify.sh`
  keeps working; nothing crashes on machines without Slack configured.
- **`SLACK_MOCK` file sink is the sole test path.** No real Slack API calls anywhere
  in the suite. The mock synthesizes deterministic `ts` values as
  `1000000000.00000N` where N is the post-append line count of the sink — so tests can
  assert exact `thread_ts` values.
- **Threading is per-project.** `slack-threads.json` maps `<project> → {thread_ts,
  channel}`. Missing entry → post root ("📦 *<project>* — orchestration thread") first,
  then reply-thread the actual notification. Existing entry → single threaded reply.
  Threads file is written atomically (mktemp + mv).
- **Corrupt threads file is auto-recovered.** A leading `jq -e . file` check gates the
  read; failure → treat as `{}` and rebuild fresh. The notification is still delivered
  (T6).
- **Attention events broadcast to the channel.** `ai_escalation_recommended`,
  `phase_failed`, `checkpoint`, `project_complete` set `reply_broadcast: true` so they
  surface in the channel and not just the thread. `phase_complete` and other benign
  events do not.
- **`checkpoint` event added to `notify.sh`.** Minimal edit: added to `VALID_EVENTS`,
  added a case in `format_message` that emits `Checkpoint: ${phase}`, added to the
  usage() docstring. No other behavioural change; existing outputs byte-compatible.
- **Token never leaked.** The hook only reads `SLACK_BOT_TOKEN` inside curl's
  `Authorization` header; `set -x` is not enabled; nothing echoes or logs the header.
  Verified by T9 with a synthetic `xoxb-TESTSECRET123` token.

## Files Created

- `config/notify-hook.sh` (executable, `bash -n` clean)
- `.planning/phases/r2-04-slack-notify/smoke-tests.sh` (18 assertions, hermetic)
- `.planning/phases/r2-04-slack-notify/result.md` (this file)
- `.planning/phases/r2-04-slack-notify/result.json`

## Files Modified

- `scripts/notify.sh` — added `checkpoint` to `VALID_EVENTS`, added a `checkpoint)`
  arm to `format_message`, added `checkpoint` line to the usage() docstring. No other
  changes; existing event types produce byte-identical output.

## Test Output

### r2-04 (this phase): 18/18

```
T1:  hook exit 0, no threads file (graceful no-op)
T2a: exactly 2 mock calls (root + reply)
T2b: line 1 (root) has NO thread_ts
T2c: line 2 threaded under synthesized ts
T2d: projA entry in slack-threads.json
T3:  line 3 threaded under same thread_ts as line 2
T4:  both projects present, distinct thread_ts
T5a: 🚨 with reply_broadcast:true
T5b: phase_complete has no reply_broadcast
T6:  corrupt threads file rebuilt, projC entry present
T7:  notify.sh exit 0; notifications.md + latest-notification.json written
T8a: Checkpoint heading in notifications.md
T8b: 🛑 in mock payload
T9:  token string absent from hook output
T10a: bash -n clean on hook + notify.sh
T10b: r1-01 still 11/11
T10c: r1-02 still 16/16
T10d: r1-03 still 19/19

Smoke test summary: 18 passed, 0 failed
```

### Regression: r1-01 11/11, r1-02 16/16, r1-03 19/19 (verified inside T10 above)

## Acceptance Criteria — Status

- [x] Graceful no-op without SLACK_MOCK / slack.env: exit 0, no threads file (T1).
- [x] First project → root then threaded reply, exactly 2 calls; slack-threads.json
  gains the entry with the synthesized ts (T2a–T2d).
- [x] Second notification same project → 1 new call, same thread_ts (T3).
- [x] Second project → separate root + distinct thread_ts; both entries coexist (T4).
- [x] `ai_escalation_recommended` payload has 🚨 + `reply_broadcast:true`;
  `phase_complete` payload has no `reply_broadcast` (T5a, T5b).
- [x] Corrupt threads file is rebuilt and the notification still posts (T6).
- [x] `SLACK_MOCK_FAIL` → hook exits non-zero, notify.sh still exits 0 and writes
  notifications.md + latest-notification.json (T7).
- [x] `notify.sh checkpoint <proj>` writes Checkpoint heading + mock receives 🛑 (T8).
- [x] Synthetic `xoxb-TESTSECRET123` token appears NOWHERE in hook stdout/stderr (T9).
- [x] `bash -n` clean; smoke-tests.sh exits 0; r1-01/r1-02/r1-03 all still green
  (T10a–T10d).

## Blockers

None.
