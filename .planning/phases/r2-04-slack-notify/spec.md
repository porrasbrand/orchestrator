# Phase r2-04: Slack Notify Hook (config/notify-hook.sh)

## Context

Project **orchestrator-r1r2** — see `.planning/brief.md` + `.planning/project.md`.
R1 is complete (dispatch ledger, headless pm-iterate runner, resident pm-daemon). This
phase starts R2: orchestrator notifications must reach Slack channel `#orchestrator`
(breakthrough3x.slack.com) as **per-project threads**, so a human can follow — and later
(r2-05) reply to — each orchestrated project from their phone. This phase delivers the
OUTBOUND half only: a `config/notify-hook.sh` that `scripts/notify.sh` already knows how
to invoke (it pipes the notification JSON to `config/notify-hook.sh` if that file exists
and is executable, and tolerates non-zero hook exits).

Token and channel are provided at DEPLOY time via `~/.orchestrator/slack.env` — they are
NOT available on this DEV machine and must NEVER be committed. All smoke tests run
hermetically via a `SLACK_MOCK` file sink ($0, no network).

## Prior Work Summary

- **notify.sh contract (existing, do not break):** `notify.sh <event> <project-path>
  [--phase <name>] [--detail <msg>]` writes `notifications.md` +
  `latest-notification.json` in `<project>/.planning/`, then, if
  `<repo>/config/notify-hook.sh` is executable, pipes the JSON
  `{timestamp, event, phase, detail, project}` to its stdin. Hook exit ≠ 0 → warning
  only, notify.sh still succeeds. See `config/notify-hook.sh.example` for the schema.
- **r1-01 (7c9f4f0):** `$ORCH_STATE_DIR` convention (`${ORCH_STATE_DIR:-$HOME/.orchestrator}`)
  — all daemon runtime state lives there, never in the repo. Hermetic tests override it
  to a mktemp dir; keep that pattern.
- **r1-02/r1-03 (93831ed, 2e4b089):** house style for scripts (`set -euo pipefail`,
  usage(), env-with-defaults config block) and for smoke-tests.sh (temp dirs via
  `mktemp -d`, `trap ... EXIT`, PASS/FAIL counters, exit 0 only when all green).
- Worker gotcha from learnings: bash `printf` with leading `-` lines needs the
  `printf '%s\n'` form.

## Objective

Implement `config/notify-hook.sh`: read the notification JSON from stdin, post it to
Slack via `chat.postMessage` (bot token + channel from `$ORCH_STATE_DIR/slack.env`),
threading all notifications for the same project under one per-project root message
tracked in `$ORCH_STATE_DIR/slack-threads.json`; no-op gracefully when slack.env is
absent; support a `SLACK_MOCK` file sink for hermetic tests. Also add the missing
`checkpoint` event type to `scripts/notify.sh` so checkpoints reach Slack end-to-end.

## Implementation Steps

1. **`config/notify-hook.sh`** (bash, `set -euo pipefail`, jq for all JSON work):

   **Config (env, with defaults):**
   - `ORCH_STATE_DIR` (`$HOME/.orchestrator`)
   - `SLACK_ENV_FILE` (`$ORCH_STATE_DIR/slack.env`) — sourced if present; defines
     `SLACK_BOT_TOKEN` and `SLACK_CHANNEL`
   - `SLACK_THREADS_FILE` (`$ORCH_STATE_DIR/slack-threads.json`)
   - `SLACK_MOCK` (unset) — path to a JSONL sink file; when set, NO network calls
   - `SLACK_MOCK_FAIL` (unset) — when set (mock mode only), simulate an API failure

   **Input:** read stdin JSON → `event`, `phase`, `detail`, `project`, `timestamp`
   (missing fields → empty string, never crash).

   **Graceful no-op rule:** if `SLACK_MOCK` is unset AND (slack.env missing OR
   `SLACK_BOT_TOKEN`/`SLACK_CHANNEL` empty) → print one stderr line
   (`notify-hook: slack not configured, skipping`) and **exit 0**. Mock mode never
   requires slack.env (use channel `mock-channel` when unset).

   **API primitive — one function `slack_post <json-payload>`:**
   - Real mode: `curl -sS -X POST https://slack.com/api/chat.postMessage -H
     "Authorization: Bearer $SLACK_BOT_TOKEN" -H 'Content-type: application/json; charset=utf-8'
     -d "$payload"`; parse response with jq; `.ok != true` → stderr warning with `.error`
     and exit 1 (notify.sh tolerates). NEVER echo the token (no `set -x`, no logging of
     headers).
   - Mock mode: append `{"api":"chat.postMessage","payload":<payload>}` as ONE line to
     `$SLACK_MOCK`; synthesize deterministic `ts` = `"1000000000.00000N"` where N = line
     count of the mock file after append. `SLACK_MOCK_FAIL` set → behave like `.ok=false`
     (warning + exit 1, nothing appended... actually append the line first, THEN fail —
     tests assert the attempted payload).

   **Threading logic:**
   - Load `SLACK_THREADS_FILE` (map `{"<project>": {"thread_ts": "...", "channel": "..."}}`).
     Missing or unparseable (jq fails) → treat as `{}` and rewrite fresh.
   - No entry for `$project` → post ROOT message first: text
     `📦 *<project>* — orchestration thread`, no `thread_ts`; store returned `ts` +
     channel into the map (atomic write: tmp file + `mv`). Then post the actual
     notification as a THREADED reply (`thread_ts` = stored ts).
   - Existing entry → single threaded `chat.postMessage` with stored `thread_ts`.

   **Message format:** `<emoji> [<project>] <event>: <phase> — <detail>` (omit empty
   phase/detail segments cleanly). Emoji map: `phase_complete` ✅ · `phase_failed` ❌ ·
   `verification_failed` ⚠️ · `regression_failed` ⚠️ · `project_complete` 🏁 ·
   `ai_escalation_recommended` 🚨 · `checkpoint` 🛑 · unknown events 🔔.
   Attention events (`ai_escalation_recommended`, `phase_failed`, `checkpoint`,
   `project_complete`) additionally set `"reply_broadcast": true` on the threaded
   message so they surface in the channel, not just the thread.

2. **`scripts/notify.sh` — minimal edit:** add `checkpoint` to the accepted event types
   (usage text + `format_message` case → `Checkpoint: ${phase}`). NO other behavioral
   changes; existing event types and file outputs must be byte-compatible.

3. **Smoke tests** → `.planning/phases/r2-04-slack-notify/smoke-tests.sh` covering the
   Smoke Tests section below. Hermetic: `T=$(mktemp -d)`, `ORCH_STATE_DIR=$T/state`,
   `SLACK_MOCK=$T/calls.jsonl`, fake project dir with `.planning/`; `trap ... EXIT`
   cleanup; PASS/FAIL counters; exit 0 only when all pass; idempotent on re-run.

## Files to Create

- `config/notify-hook.sh` (executable)
- `.planning/phases/r2-04-slack-notify/smoke-tests.sh`
- `.planning/phases/r2-04-slack-notify/result.md` (+ result.json)

## Files to Modify

- `scripts/notify.sh` — ONLY the `checkpoint` event-type addition (step 2).

## Do NOT Touch

- `scripts/pm-iterate.sh`, `services/pm-daemon.js`, `scripts/queue-phase.sh`,
  `scripts/register-project.sh`, all other existing scripts/templates
- `config/notify-hook.sh.example` (stays as generic documentation), `config/workers.json`
- `CLAUDE.md`, `docs/` (docs land in r1r2-06); no `scripts/slack-poll-resolutions.sh`
  (that's r2-05)
- NO real network calls anywhere in tests; NO tokens/webhooks in the repo or in test
  fixtures; no new dependencies beyond bash/jq/curl

## Cleanup

All test state under `mktemp -d` (fake ORCH_STATE_DIR, fake project, mock sink),
removed via `trap ... EXIT`. Suite idempotent on re-run.

## Expected Files Changed

```
config/notify-hook.sh
scripts/notify.sh
.planning/phases/r2-04-slack-notify/smoke-tests.sh
.planning/phases/r2-04-slack-notify/result.md
.planning/phases/r2-04-slack-notify/result.json
```

## Acceptance Criteria

- [ ] Hook with no `SLACK_MOCK` and no slack.env exits 0, posts nothing, creates no threads file (graceful no-op).
- [ ] First notification for a project (mock mode) produces exactly 2 mock calls — root message (no `thread_ts`, text contains the project name) then threaded reply (`thread_ts` == root's synthesized ts) — and `slack-threads.json` gains the project entry (atomic write).
- [ ] Second notification for the same project produces exactly 1 new call, threaded under the SAME `thread_ts`.
- [ ] A second project gets its own root message and a DIFFERENT `thread_ts`; both entries coexist in `slack-threads.json`.
- [ ] `ai_escalation_recommended` message text contains 🚨 and its threaded payload has `reply_broadcast: true`; `phase_complete` does NOT set `reply_broadcast`.
- [ ] Corrupt `slack-threads.json` (garbage bytes) does not crash the hook — it is rebuilt and the notification still posts.
- [ ] `SLACK_MOCK_FAIL` → hook exits non-zero, and `notify.sh` still exits 0 (prints its hook warning) with notifications.md/latest-notification.json written.
- [ ] End-to-end: `scripts/notify.sh checkpoint <proj> --phase p --detail d` (with SLACK_MOCK set) writes a Checkpoint heading to notifications.md AND the mock sink receives the 🛑 payload.
- [ ] With a dummy token in a test slack.env (mock mode), the token string appears NOWHERE in the hook's stdout/stderr.
- [ ] `bash -n` clean on `config/notify-hook.sh` + `scripts/notify.sh`; smoke-tests.sh exits 0; prior suites still green (r1-01 11/11, r1-02 16/16, r1-03 19/19).

## Smoke Tests

```bash
# Preamble: T=$(mktemp -d); export ORCH_STATE_DIR=$T/state SLACK_MOCK=$T/calls.jsonl
# fake project: P=$T/proj; mkdir -p $P/.planning
# helper: note() { jq -n --arg e "$1" --arg ph "$2" --arg d "$3" --arg p "$4" \
#   '{timestamp:"2026-07-02T15:00:00Z",event:$e,phase:$ph,detail:$d,project:$p}'; }
HOOK=config/notify-hook.sh

# Test 1: graceful no-op without config
env -u SLACK_MOCK ORCH_STATE_DIR=$T/state bash $HOOK <<<"$(note phase_complete p1 ok projA)"
# Expected: exit 0, $T/state/slack-threads.json absent, no network attempted

# Test 2: first notification → root + threaded reply
note phase_complete r2-04 "16/16 passed" projA | bash $HOOK
test "$(wc -l < "$SLACK_MOCK")" = 2
jq -es '.[0].payload | has("thread_ts") | not' "$SLACK_MOCK" >/dev/null
jq -es '.[1].payload.thread_ts == "1000000000.000001"' "$SLACK_MOCK" >/dev/null
jq -e '."projA".thread_ts' "$ORCH_STATE_DIR/slack-threads.json"
# Expected: root then reply, mapping stored

# Test 3: second notification → 1 call, same thread
note verification_failed r2-04 "2 failed" projA | bash $HOOK
test "$(wc -l < "$SLACK_MOCK")" = 3
# Expected: line 3 has thread_ts == line 2's thread_ts

# Test 4: second project → separate thread
note phase_complete x1 done projB | bash $HOOK
# Expected: 2 more lines (root+reply); projB thread_ts != projA thread_ts; both in threads file

# Test 5: escalation formatting + broadcast
note ai_escalation_recommended r2-04 "both low confidence" projA | bash $HOOK
tail -1 "$SLACK_MOCK" | jq -e '.payload.reply_broadcast == true and (.payload.text | contains("🚨"))'
# Expected: pass; phase_complete lines have no reply_broadcast

# Test 6: corrupt threads file recovered
echo 'garbage{{{' > "$ORCH_STATE_DIR/slack-threads.json"
note phase_complete p9 ok projC | bash $HOOK
jq -e '."projC"' "$ORCH_STATE_DIR/slack-threads.json"
# Expected: exit 0, valid JSON rebuilt

# Test 7: mock failure tolerated by notify.sh
mkdir -p $P/.planning
SLACK_MOCK_FAIL=1 ./scripts/notify.sh phase_failed "$P" --phase p1 --detail boom
# Expected: notify.sh exit 0, warning on stderr, notifications.md written

# Test 8: checkpoint end-to-end through notify.sh
./scripts/notify.sh checkpoint "$P" --phase r1-03-pm-daemon --detail "3/6 complete"
grep -q "Checkpoint" "$P/.planning/notifications.md"
tail -1 "$SLACK_MOCK" | jq -e '.payload.text | contains("🛑")'
# Expected: both assertions pass

# Test 9: token never leaked
printf 'SLACK_BOT_TOKEN=xoxb-TESTSECRET123\nSLACK_CHANNEL=C0TEST\n' > "$ORCH_STATE_DIR/slack.env"
OUT="$(note phase_complete p1 ok projA | bash $HOOK 2>&1)"
! grep -q 'TESTSECRET123' <<<"$OUT"
# Expected: no token in any output

# Test 10: regressions
bash -n config/notify-hook.sh && bash -n scripts/notify.sh
bash .planning/phases/r1-01-dispatch-ledger/smoke-tests.sh   # 11/11
bash .planning/phases/r1-02-pm-iterate/smoke-tests.sh        # 16/16
bash .planning/phases/r1-03-pm-daemon/smoke-tests.sh         # 19/19
# Expected: all green
```

## Completion Instructions

1. `chmod +x config/notify-hook.sh`; `bash -n` both shell files; run THIS phase's
   smoke-tests.sh AND all three r1 suites — all green.
2. Write result.md + result.json in this phase dir.
3. Commit with prefix `[orchestrator-r2-04]` and push to origin master.
