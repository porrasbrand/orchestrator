# Phase r2-05: Slack Reply Polling → Resolutions (scripts/slack-poll-resolutions.sh)

## Context

Project **orchestrator-r1r2** — see `.planning/brief.md` + `.planning/project.md`.
R1 (dispatch ledger, pm-iterate, pm-daemon) and r2-04 (outbound Slack hook) are complete.
This phase delivers the INBOUND half of R2: human replies in the per-project Slack
threads ("continue", "retry", "abort", "override: <text>") are polled, translated into
resolutions, and fed back into the orchestration loop — so an escalated or
checkpoint-gated project resumes from a phone, without a laptop session.

Token/channel arrive at DEPLOY time via `$ORCH_STATE_DIR/slack.env` (NEVER committed).
All smoke tests are hermetic: mock inbound replies via a JSON fixture file, mock
outbound ACKs via the r2-04 `SLACK_MOCK` sink, mock pm-iterate via `PM_ITERATE_BIN`.
$0 cost, no network, no lipo services.

## Prior Work Summary (contracts you must honor)

- **pm-iterate.sh escalation gate (G5, r1-02):** for the current phase, the latest of
  {`ai_escalation_recommended`, `escalation_resolved`} events in
  `<project>/.planning/events.jsonl` decides the gate. Latest == `ai_escalation_recommended`
  → `SKIP: escalated-awaiting-human` (exit 0) UNLESS `--trigger resolution`, which
  bypasses the gate. So the resolution flow MUST (a) append `escalation_resolved`,
  (b) invoke `pm-iterate.sh <path> --trigger resolution`.
- **pm-iterate.sh guard style (r1-02):** guards print `SKIP: <reason>` and exit 0; the
  daemon treats exit 0 + `SKIP:` as benign no-op. New guards must follow this exactly.
- **notify-hook.sh (r2-04, 4982864):** `$ORCH_STATE_DIR/slack-threads.json` maps
  `{"<project>": {"thread_ts": "...", "channel": "..."}}`. Mock convention: when
  `SLACK_MOCK` is set, every `chat.postMessage` appends ONE JSONL line
  `{"api":"chat.postMessage","payload":<payload>}` to that file and NO network happens.
  Reuse this exact outbound-mock convention for the poller's thread ACKs.
- **pm-daemon.js (r1-03, 2e4b089):** `numEnv()` env knobs, `safeReadJSON`/`safeReadJSONL`,
  per-cycle try/catch (a cycle error never kills the daemon), `--once` runs each cycle
  exactly once synchronously. `PM_ITERATE_BIN` overrides the pm-iterate path — copy this
  pattern for the poller binary.
- **notify.sh (r2-04):** accepted event types are enumerated (usage + `format_message`
  case). r2-04 added `checkpoint` with a two-line edit; add `phase_aborted` the same way.
- **House style:** `set -euo pipefail`, usage(), env-with-defaults config block, jq for
  all JSON, atomic writes (tmp + `mv`), `printf '%s\n'` for lines that may start with `-`.
  Smoke tests: `T=$(mktemp -d)`, `trap ... EXIT`, PASS/FAIL counters, exit 0 only all-green.
- **Poller efficiency (learnings):** only call `conversations.replies` for projects that
  have a `slack-threads.json` entry AND are actually awaiting a human (see eligibility).

## Objective

1. `scripts/slack-poll-resolutions.sh` — one polling pass over awaiting projects: fetch
   new thread replies, parse commands, append resolutions + gate-release events, ACK in
   thread, and kick `pm-iterate.sh --trigger resolution`.
2. A **checkpoint gate (G6)** in `scripts/pm-iterate.sh` so checkpoints actually pause
   the daemon-driven loop until a human replies "continue" (today only escalations gate).
3. Daemon wiring: pm-daemon.js runs the poller on its own interval.
4. `phase_aborted` event type in `scripts/notify.sh`.

## Implementation Steps

### 1. `scripts/pm-iterate.sh` — add G6 checkpoint gate (small, surgical)

Insert AFTER G5, same style. Gate rule for the project (not per-phase): consider the
latest event among {`checkpoint`, `checkpoint_acknowledged`, `phase_queued`} in
events.jsonl. If that latest event is `checkpoint` AND `$TRIGGER != resolution` →
`echo "SKIP: checkpoint-awaiting-human"; exit 0`.

Rationale (encode exactly this): a `phase_queued` after a checkpoint means the loop
already resumed (e.g. an interactive session continued past it), so the gate must be
OPEN — this keeps existing projects with historical checkpoint events from stalling.
`--trigger resolution` bypasses G6 exactly like G5. No other pm-iterate changes.

### 2. `scripts/notify.sh` — add `phase_aborted` event type

Usage text + `format_message` case → `Phase aborted: ${phase}`. Nothing else changes;
existing outputs stay byte-compatible. (notify-hook.sh needs NO change — unknown events
already render with 🔔.)

### 3. `scripts/slack-poll-resolutions.sh` (the core deliverable)

**Usage:** `slack-poll-resolutions.sh [--project <name>]` — one pass, then exit
(the daemon provides cadence). `--project` restricts to one registry entry (for tests).

**Config (env, with defaults):**
- `ORCH_STATE_DIR` (`$HOME/.orchestrator`)
- `SLACK_ENV_FILE` (`$ORCH_STATE_DIR/slack.env`) — sourced if present
- `SLACK_THREADS_FILE` (`$ORCH_STATE_DIR/slack-threads.json`)
- `RESOLUTIONS_STATE_FILE` (`$ORCH_STATE_DIR/slack-resolutions-state.json`) — cursor map
  `{"<project>": {"last_ts": "<slack ts>"}}`
- `PM_ITERATE_BIN` (`<repo>/scripts/pm-iterate.sh`)
- `SLACK_MOCK` — outbound JSONL sink (r2-04 convention) for ACK posts
- `SLACK_REPLIES_MOCK` — inbound fixture: JSON file mapping thread_ts →
  `conversations.replies`-shaped response, e.g.
  `{"1000000000.000001": {"ok": true, "messages": [{"ts":"...","user":"U1","text":"continue"}, ...]}}`.
  When set, NO network; a thread_ts absent from the fixture behaves as zero new replies.

**Graceful no-op:** if `SLACK_REPLIES_MOCK` unset AND (slack.env missing OR
`SLACK_BOT_TOKEN`/`SLACK_CHANNEL` empty) → one stderr line
(`slack-poll: slack not configured, skipping`), exit 0. Missing/corrupt threads file,
registry, or cursor file → treat as `{}`/empty, never crash.

**Eligibility (compute per registry project, active !== false):** poll a project IFF it
has a `slack-threads.json` entry AND at least one gate is CLOSED:
- *escalation gate closed*: latest {`ai_escalation_recommended`,`escalation_resolved`}
  event for `status.json.current_phase` is `ai_escalation_recommended` (same jq as G5)
- *checkpoint gate closed*: latest {`checkpoint`,`checkpoint_acknowledged`,`phase_queued`}
  event is `checkpoint` (same jq as G6)
Blocked/aborted projects are NOT polled (unblocking requires a laptop session — decision
noted in Level-0 learnings). Print a one-line summary at the end:
`slack-poll: eligible=<n> processed=<m>`.

**Fetch:** real mode — `GET https://slack.com/api/conversations.replies` with
`channel=<entry.channel>&ts=<thread_ts>&oldest=<cursor last_ts or 0>&limit=200`, bearer
token header; `.ok != true` → stderr warning, skip project (exit stays 0). NEVER echo
the token. Mock mode — read the fixture entry for that thread_ts.

**Reply filtering:** from `messages[]`, drop the thread parent (`.ts == thread_ts`),
drop bot messages (`.bot_id` present — this also hides our own ACKs), drop anything with
`.ts <= cursor`. Process the rest in ascending ts order.

**Command grammar** (first line of `.text`, trimmed, case-insensitive):
- `continue` or `retry` → kind `continue`
- `abort` → kind `abort`
- `override: <text>` → kind `override`, capture `<text>` (rest of message, may be multiline)
- anything else → kind `unrecognized`

**Actions per command** (let PHASE = status.json `.current_phase`, GATE = whichever
gate(s) are closed):

*continue / override:*
1. Append to `<project>/.planning/resolutions.jsonl`:
   `{"ts":"<utc>","phase":PHASE,"kind":"continue|override","text":"<override text or omitted>","source":"slack","user":"<reply .user>","reply_ts":"<reply .ts>","gate":"escalation|checkpoint"}`
2. Append gate-release event(s) to events.jsonl — `escalation_resolved` if the escalation
   gate is closed, `checkpoint_acknowledged` if the checkpoint gate is closed (both if
   both): `{"ts":"...","event":"<name>","data":{"phase":PHASE,"source":"slack","user":"...","reply_ts":"...","resolution":"continue|override"}}`
3. ACK in thread via `chat.postMessage` (thread_ts, SLACK_MOCK-aware):
   continue → `▶️ [<project>] resuming — <phase>` · override → `✏️ [<project>] override applied — resuming <phase>`
4. Invoke `"$PM_ITERATE_BIN" <local_path> --trigger resolution` (best-effort: log its
   exit/SKIP line; do not fail the poller on non-zero).

*abort:*
1. Append the resolutions.jsonl line (kind `abort`).
2. status.json (atomic tmp+mv): `.phases[PHASE].status = "blocked"`, `.blocked = true`,
   `.blocked_reason = "aborted via Slack by <user>"`, `.updated = <today>`.
3. Append `phase_aborted` event `{phase, source:"slack", user, reply_ts}`.
4. `scripts/notify.sh phase_aborted <local_path> --phase PHASE --detail "aborted via Slack"`
   (this is the abort's Slack confirmation via the r2-04 hook — no separate ACK post).
5. Do NOT invoke pm-iterate.

*unrecognized:* ACK `🤖 [<project>] unrecognized — commands: continue | abort | override: <text>`.
No events, no resolutions line.

**Cursor:** after a project's batch, set `last_ts` to the max `.ts` SEEN in that thread's
messages (including skipped/bot ones) and atomic-write the cursor file. A rerun with the
same fixture must be a complete no-op (idempotent).

**Override consumption note (document in the script header):** revision-spec authoring
(headless PM) reads `.planning/resolutions.jsonl` — the newest `override` entry for the
current phase is injected into the next revision spec. That consumption is prompt-side
(CLAUDE.md, r1r2-06 docs); this phase only produces the file.

### 4. `services/pm-daemon.js` — wiring

- New knobs: `PM_RESOLUTIONS_INTERVAL` (default 120 s), `PM_RESOLUTIONS_BIN`
  (default `<repo>/scripts/slack-poll-resolutions.sh`).
- New `resolutionsCycle()`: honor `paused` file (log + return, like other cycles); if
  the bin is missing/non-executable → silently return (bare install); else spawnSync it
  (inherit env, cwd REPO_DIR), log a trimmed stdout/stderr summary. Errors caught per-cycle.
- Daemon mode: third `setInterval` + one immediate run at startup. `--once`: run it once
  after scan + tick. Log the interval in the startup banner.

### 5. Smoke tests → `.planning/phases/r2-05-slack-resolutions/smoke-tests.sh`

Hermetic preamble: `T=$(mktemp -d)`; `ORCH_STATE_DIR=$T/state`; fake project
`$T/proj/.planning` with status.json (current_phase `p1`, phases.p1.status `verifying`)
+ events.jsonl; registry `$T/state/active-projects.json` pointing at it; threads file
with a `projA` entry (thread_ts `1000000000.000001`); `SLACK_MOCK=$T/out.jsonl`;
`SLACK_REPLIES_MOCK=$T/replies.json`; mock pm-iterate `PM_ITERATE_BIN=$T/mock-iterate.sh`
that appends its argv to `$T/iterate-calls.log` and exits 0. `trap ... EXIT`.

## Files to Create

- `scripts/slack-poll-resolutions.sh` (executable)
- `.planning/phases/r2-05-slack-resolutions/smoke-tests.sh`
- `.planning/phases/r2-05-slack-resolutions/result.md` (+ result.json)

## Files to Modify

- `scripts/pm-iterate.sh` — ONLY the G6 checkpoint gate (step 1)
- `scripts/notify.sh` — ONLY the `phase_aborted` event type (step 2)
- `services/pm-daemon.js` — ONLY the resolutions wiring (step 4)

## Do NOT Touch

- `config/notify-hook.sh` (r2-04 deliverable — reuse, don't modify),
  `scripts/queue-phase.sh`, `scripts/register-project.sh`, `scripts/run-pm-daemon.sh`,
  all other scripts/templates
- `/home/mp/awesome/super-agent` anything
- `CLAUDE.md`, `docs/` (docs land in r1r2-06); no integration-test-pm.sh (also r1r2-06)
- NO real network calls in tests; NO tokens in repo/fixtures; no new dependencies beyond
  bash/jq/curl/node

## Cleanup

All test state under `mktemp -d`, removed via `trap ... EXIT`. Suite idempotent on re-run.

## Expected Files Changed

```
scripts/slack-poll-resolutions.sh
scripts/pm-iterate.sh
scripts/notify.sh
services/pm-daemon.js
.planning/phases/r2-05-slack-resolutions/smoke-tests.sh
.planning/phases/r2-05-slack-resolutions/result.md
.planning/phases/r2-05-slack-resolutions/result.json
```

## Acceptance Criteria

- [ ] Poller with no `SLACK_REPLIES_MOCK` and no slack.env exits 0 with the skip line (graceful no-op).
- [ ] Project with a threads entry but NO closed gate is not polled (`eligible=0`, no fetch, no ACK, cursor file untouched).
- [ ] Escalated project + `continue` reply → `escalation_resolved` event appended (phase, source=slack, user, reply_ts), resolutions.jsonl line written, ▶️ ACK posted threaded under the project's thread_ts, cursor advanced, mock pm-iterate called once with `--trigger resolution`.
- [ ] Immediate second poller run with the same fixture is a complete no-op (idempotency via cursor).
- [ ] `override: use bearer auth` reply → resolutions.jsonl entry has kind=override and the exact text; gate-release event carries resolution=override; pm-iterate invoked.
- [ ] `abort` reply → status.json shows phases.p1.status=blocked, blocked=true with reason containing the Slack user; `phase_aborted` event appended; notify.sh invoked (notifications.md gains "Phase aborted"); pm-iterate NOT called.
- [ ] Unrecognized reply → 🤖 help ACK posted, cursor advanced, NO events/resolutions written.
- [ ] Thread parent and bot messages (`bot_id`) are ignored — a fixture containing only those produces no actions and still advances the cursor.
- [ ] G6: project whose latest {checkpoint, checkpoint_acknowledged, phase_queued} event is `checkpoint` → `pm-iterate.sh --trigger tick` prints `SKIP: checkpoint-awaiting-human`; with `--trigger resolution` it proceeds; after a `checkpoint_acknowledged` event, tick proceeds; a `phase_queued` event AFTER the checkpoint also opens the gate (backward-compat with pre-r2-05 history).
- [ ] Checkpoint-gated project + `continue` → `checkpoint_acknowledged` event (not escalation_resolved) and pm-iterate invoked.
- [ ] `pm-daemon.js --once` with `PM_RESOLUTIONS_BIN` pointing at a recorder script runs it exactly once; with the bin absent, --once completes without error or mention.
- [ ] With a dummy token in a test slack.env (mock mode), the token appears NOWHERE in poller stdout/stderr.
- [ ] `bash -n` clean on all three shell files; `node --check services/pm-daemon.js` clean; smoke-tests.sh exits 0; prior suites still green (r1-01 11/11, r1-02 16/16, r1-03 19/19, r2-04 18/18).

## Smoke Tests

```bash
# Preamble per step 5. Helpers:
#   reply() -> writes $SLACK_REPLIES_MOCK fixture for thread 1000000000.000001
#   esc()   -> appends ai_escalation_recommended event for p1 to fake events.jsonl
POLL=scripts/slack-poll-resolutions.sh

# T1: not configured → graceful no-op
env -u SLACK_REPLIES_MOCK -u SLACK_MOCK ORCH_STATE_DIR=$T/state bash $POLL; # exit 0, skip line on stderr

# T2: no closed gate → not polled
bash $POLL | grep -q 'eligible=0'; test ! -s $T/out.jsonl

# T3: escalation + continue → full resolution flow
esc; reply human "continue"; bash $POLL
grep -q '"event":"escalation_resolved"' $T/proj/.planning/events.jsonl
jq -e '.kind=="continue" and .source=="slack"' <(tail -1 $T/proj/.planning/resolutions.jsonl)
tail -1 $T/out.jsonl | jq -e '.payload.thread_ts=="1000000000.000001" and (.payload.text|contains("▶️"))'
grep -q -- '--trigger resolution' $T/iterate-calls.log

# T4: idempotent re-run → no new lines anywhere
bash $POLL; # counts of events/resolutions/out/iterate-calls unchanged

# T5: override captured verbatim
esc; reply human "override: use bearer auth"; bash $POLL
jq -e '.kind=="override" and .text=="use bearer auth"' <(tail -1 $T/proj/.planning/resolutions.jsonl)

# T6: abort → blocked, phase_aborted, notify, NO pm-iterate
esc; reply human "abort"; bash $POLL
jq -e '.phases.p1.status=="blocked" and .blocked==true' $T/proj/.planning/status.json
grep -q '"event":"phase_aborted"' $T/proj/.planning/events.jsonl
grep -q 'Phase aborted' $T/proj/.planning/notifications.md

# T7: unrecognized → help ACK only
# T8: parent + bot_id messages ignored, cursor still advances

# T9: G6 checkpoint gate on pm-iterate directly (PM_ITERATE_MOCK, hermetic)
#   checkpoint latest → tick prints SKIP: checkpoint-awaiting-human
#   --trigger resolution bypasses; checkpoint_acknowledged reopens; phase_queued-after reopens

# T10: checkpoint-gated + continue → checkpoint_acknowledged event, pm-iterate called

# T11: daemon wiring
PM_RESOLUTIONS_BIN=$T/recorder.sh node services/pm-daemon.js --once  # recorder ran once
PM_RESOLUTIONS_BIN=$T/nonexistent node services/pm-daemon.js --once  # clean, silent

# T12: token never leaked (dummy slack.env, mock mode, grep full output)

# Regressions
bash -n scripts/slack-poll-resolutions.sh scripts/pm-iterate.sh scripts/notify.sh
node --check services/pm-daemon.js
bash .planning/phases/r1-01-dispatch-ledger/smoke-tests.sh   # 11/11
bash .planning/phases/r1-02-pm-iterate/smoke-tests.sh        # 16/16
bash .planning/phases/r1-03-pm-daemon/smoke-tests.sh         # 19/19
bash .planning/phases/r2-04-slack-notify/smoke-tests.sh      # 18/18
```

## Completion Instructions

1. `chmod +x scripts/slack-poll-resolutions.sh`; syntax-check all touched files; run THIS
   phase's smoke-tests.sh AND all four prior suites — all green.
2. Write result.md + result.json in this phase dir.
3. Commit with prefix `[orchestrator-r2-05]` and push to origin master.
