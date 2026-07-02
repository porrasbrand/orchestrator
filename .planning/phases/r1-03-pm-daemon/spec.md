# Phase r1-03: Resident PM Daemon (pm-daemon.js)

## Context

Project **orchestrator-r1r2** — see `.planning/brief.md` + `.planning/project.md`.
Phases r1-01 (dispatch ledger) and r1-02 (pm-iterate.sh runner) are complete. This phase
builds the resident service that provides the CADENCE: it watches the super-agent
responses directory, claims ledger-matched responses after a grace period, and spawns
`pm-iterate.sh`. It also runs a periodic tick that nudges active projects that have
actionable state. After this phase, the orchestration loop no longer needs an open
interactive session.

## Prior Work Summary

- **r1-01 (7c9f4f0):** `$ORCH_STATE_DIR` convention (`${ORCH_STATE_DIR:-$HOME/.orchestrator}`);
  registry `active-projects.json` (array of `{name, local_path, worker, remote_path,
  active, registered_at}`); ledger `dispatch-ledger.jsonl` — one line per dispatched
  phase: `{ts, task_id (STRING), project, project_path, phase, worker}`.
- **r1-02 (93831ed):** `scripts/pm-iterate.sh <project-path> [--trigger response|tick|resolution]
  [--response-file <path>] [--dry-run]`. It self-guards (paused, interrupt.json, flock,
  hourly cap, escalation gate) — guard-skips print `SKIP: <reason>` and exit 0; real runs
  print `RAN: exit=<n> ...` and propagate claude's exit code. The daemon therefore does
  NOT need to re-implement those guards; it only decides WHEN to invoke.
- **Controller flow (production, described for design context — NOT reachable from this
  DEV machine):** a response-fetcher writes worker responses to
  `$SUPER_AGENT_DIR/tasks/responses/new/<task_id>.json`; a separate watcher pings any open
  interactive session, which handles the response and moves it to
  `tasks/responses/archive/`. The daemon must be the FALLBACK: only touch files that are
  still in `new/` after a grace period.
- House style + hermetic test convention: see the two prior phase smoke-tests.sh files.
  Node.js (≥18) is available; the daemon must use ONLY the Node standard library (this
  repo has no package.json/node_modules — do not add dependencies).

## Objective

Create `services/pm-daemon.js` (stdlib-only Node, polling-based) + `scripts/run-pm-daemon.sh`
pm2 wrapper: claim ledger-matched responses via atomic rename after a grace period, spawn
`pm-iterate.sh` one-at-a-time, archive on success with retry/give-up handling on failure,
tick active projects only when their state is actionable — with a `--once` mode proven by
hermetic smoke tests using a mock pm-iterate. Also make `pm-iterate.sh --dry-run`
side-effect-free (bugfix from r1-02 verification).

## Implementation Steps

1. **Bugfix first (small, isolated):** in `scripts/pm-iterate.sh`, do NOT append the
   `pm_iteration` event to the project's events.jsonl when `--dry-run` is set. Dry-run
   must write the prompt file and nothing else.

2. **`services/pm-daemon.js`** — plain Node, stdlib only (`fs`, `path`, `child_process`,
   `os`). No chokidar: use polling (grace periods are minutes; a 60 s scan is plenty).

   **Config (env, with defaults):**
   - `ORCH_STATE_DIR` ($HOME/.orchestrator), `SUPER_AGENT_DIR` ($HOME/awesome/super-agent)
   - `PM_GRACE_PERIOD` (600 s) — response must sit in `new/` at least this long
   - `PM_POLL_INTERVAL` (60 s) — responses scan cadence
   - `PM_TICK_INTERVAL` (900 s) — project tick cadence
   - `PM_STALL_TIMEOUT` (14400 s) — how long a phase may stay `queued` before a tick pokes it
   - `PM_MAX_ATTEMPTS` (2) — pm-iterate attempts per claimed response before give-up
   - `PM_ITERATE_BIN` (`<repo>/scripts/pm-iterate.sh`) — override for tests
   - CLI: `--once` = run exactly one scan cycle + one tick cycle synchronously, then exit
     (required for tests); default = daemonize with setInterval loops.

   **Response scan cycle:**
   1. If `$ORCH_STATE_DIR/paused` exists → log + do nothing this cycle.
   2. Load ledger into a Map keyed by task_id (string). Load registry; skip projects with
      `active: false`.
   3. For each `<task_id>.json` in `$SUPER_AGENT_DIR/tasks/responses/new/`: if task_id is
      in the ledger AND its project is active AND file mtime is older than
      `PM_GRACE_PERIOD` → **claim** it: atomic `fs.renameSync` to
      `$SUPER_AGENT_DIR/tasks/responses/claimed/<task_id>.json` (create dir; if rename
      throws ENOENT someone else took it — skip silently).
   4. For each claimed file (including leftovers from previous runs): spawn
      `PM_ITERATE_BIN <project_path> --trigger response --response-file <claimed-path>`
      **sequentially** (never more than one pm-iterate at a time, across all projects).
   5. Disposition by pm-iterate outcome:
      - exit 0 → move file to `tasks/responses/archive/`, reset attempts.
      - non-zero → increment attempts in `$ORCH_STATE_DIR/daemon-state.json`
        (`{"claims":{"<task_id>":{"attempts":N,"last_exit":n,"last_ts":"..."}}}`, atomic
        write). If attempts < `PM_MAX_ATTEMPTS` leave in `claimed/` (retried next cycle);
        else move to `tasks/responses/failed/`, append
        `{"ts":"...","event":"pm_daemon_gave_up","data":{"task_id":"<id>","phase":"<phase>","attempts":N,"last_exit":n}}`
        to the project's `.planning/events.jsonl`, and log loudly.
      - Note: a `SKIP:`-guarded exit 0 (e.g. rate-capped prints SKIP and exits 0) must NOT
        archive the response — detect `SKIP:` in pm-iterate stdout and leave the file in
        `claimed/` with attempts unchanged (it will be retried next cycle).

   **Tick cycle:** for each ACTIVE registry project, read `<local_path>/.planning/status.json`:
   - current phase status `pending`, `specified`, or `verifying` → actionable → spawn
     `PM_ITERATE_BIN <local_path> --trigger tick` (sequential, same single-flight rule).
   - status `queued` → actionable ONLY if the newest `phase_queued` event for that phase
     in events.jsonl is older than `PM_STALL_TIMEOUT` (stall poke).
   - anything else (`complete`, `blocked`, `revision_failed`, project done, unreadable
     status.json) → skip. This keeps steady-state token cost ~zero: waiting-on-worker
     projects trigger nothing.
   - Log one summary line per tick cycle: which projects were poked and why.

   **Logging:** timestamped lines to stdout (pm2 captures); every claim, spawn, exit code,
   disposition, and skip-reason must be visible in the log.

3. **`scripts/run-pm-daemon.sh`** — thin pm2 wrapper: resolve repo dir from its own
   location, `exec node "$REPO/services/pm-daemon.js" "$@"`. Header comment documents
   deployment: `pm2 start scripts/run-pm-daemon.sh --name pm-daemon` and the env knobs.

4. **`templates/test-fixtures/mock-pm-iterate.sh`** — records each invocation (all args,
   one JSON line) to `$MOCK_PM_LOG`; behavior via env: `MOCK_PM_EXIT` (default 0),
   `MOCK_PM_STDOUT` (default `RAN: exit=0 transcript=/dev/null`; set to `SKIP: rate-capped`
   to test the SKIP path).

5. **Smoke tests** → `.planning/phases/r1-03-pm-daemon/smoke-tests.sh` covering the Smoke
   Tests section below, all via `--once`, temp dirs, `PM_GRACE_PERIOD=1`, mock pm-iterate.

## Files to Create

- `services/pm-daemon.js`
- `scripts/run-pm-daemon.sh`
- `templates/test-fixtures/mock-pm-iterate.sh`
- `.planning/phases/r1-03-pm-daemon/smoke-tests.sh`
- `.planning/phases/r1-03-pm-daemon/result.md` (+ result.json)

## Files to Modify

- `scripts/pm-iterate.sh` — ONLY the dry-run side-effect fix (step 1). No other changes.

## Do NOT Touch

- `scripts/register-project.sh`, `scripts/queue-phase.sh`, all other existing scripts/templates
- `CLAUDE.md`, `docs/` (docs land in r1r2-06)
- No npm installs / package.json; no SSH; no network; never invoke a real `claude`

## Cleanup

All test state under `mktemp -d` (fake `SUPER_AGENT_DIR` tree, `ORCH_STATE_DIR`, fake
projects), removed via `trap ... EXIT`. Suite idempotent on re-run.

## Expected Files Changed

```
services/pm-daemon.js
scripts/run-pm-daemon.sh
scripts/pm-iterate.sh
templates/test-fixtures/mock-pm-iterate.sh
.planning/phases/r1-03-pm-daemon/smoke-tests.sh
.planning/phases/r1-03-pm-daemon/result.md
.planning/phases/r1-03-pm-daemon/result.json
```

## Acceptance Criteria

- [ ] Ledger-matched response older than grace → claimed (renamed to `claimed/`), mock pm-iterate invoked once with `--trigger response --response-file <claimed-path>` and the correct project_path, then archived to `archive/` on exit 0.
- [ ] Non-ledger response and ledger response younger than grace are both left untouched in `new/`.
- [ ] Response for a DEACTIVATED registry project is left untouched.
- [ ] Failure path: `MOCK_PM_EXIT=1` leaves the file in `claimed/` with attempts=1; a second `--once` retries; at `PM_MAX_ATTEMPTS` the file moves to `failed/` and `pm_daemon_gave_up` (with task_id + attempts) lands in the project's events.jsonl.
- [ ] `SKIP:` stdout from pm-iterate (exit 0) leaves the claimed file in place with attempts unchanged (no archive, no give-up).
- [ ] Tick: project with current phase `specified` gets a `--trigger tick` invocation; project `queued` with a recent `phase_queued` event gets none; `queued` with an old event (beyond `PM_STALL_TIMEOUT`) gets one.
- [ ] `paused` file → `--once` performs no claims and no ticks.
- [ ] Two responses for two projects in one cycle → pm-iterate invocations are sequential (mock log must show no overlap; enforce single-flight in code).
- [ ] `pm-iterate.sh --dry-run` no longer appends any event to events.jsonl (regression test), and the r1-02 suite still passes 16/16.
- [ ] `bash -n` clean on shell files; `node --check services/pm-daemon.js` clean; smoke-tests.sh exits 0.

## Smoke Tests

```bash
# Preamble: T=$(mktemp -d); fake tree: $T/sa/tasks/responses/{new,archive}; $T/state;
# projects $T/projA,$T/projB with .planning/status.json + events.jsonl; registry via
# register-project.sh with ORCH_STATE_DIR=$T/state; ledger lines written for known task ids;
# export SUPER_AGENT_DIR=$T/sa ORCH_STATE_DIR=$T/state PM_GRACE_PERIOD=1 \
#        PM_ITERATE_BIN=$T/mock-pm-iterate.sh MOCK_PM_LOG=$T/mock.log
DAEMON="node services/pm-daemon.js --once"

# Test 1: claim + iterate + archive
echo '{"id":111,"response":"done"}' > "$T/sa/tasks/responses/new/111.json"; sleep 2
$DAEMON
test -f "$T/sa/tasks/responses/archive/111.json" && grep -q '"--trigger","response"' "$T/mock.log"
# Expected: exit 0, file archived, mock invoked with projA path + claimed response path

# Test 2: non-ledger response untouched
# Expected: 999.json still in new/ after --once, mock log unchanged

# Test 3: younger than grace untouched
# Expected: with PM_GRACE_PERIOD=3600, fresh ledger-matched file stays in new/

# Test 4: retry then give-up
MOCK_PM_EXIT=1 $DAEMON   # attempt 1 → stays in claimed/
MOCK_PM_EXIT=1 $DAEMON   # attempt 2 == PM_MAX_ATTEMPTS → failed/
test -f "$T/sa/tasks/responses/failed/222.json"
tail -1 "$T/projA/.planning/events.jsonl" | jq -e '.event=="pm_daemon_gave_up" and .data.task_id=="222"'
# Expected: exit 0 both runs; give-up event present

# Test 5: SKIP output leaves claim in place
MOCK_PM_STDOUT='SKIP: rate-capped (6/6 in last hour)' $DAEMON
# Expected: file remains in claimed/, attempts unchanged, nothing archived

# Test 6: tick actionability
# projA status 'specified' → tick invocation; projB 'queued' + fresh phase_queued → none;
# then rewrite projB's phase_queued ts to 5h ago with PM_STALL_TIMEOUT=14400 → invocation
# Expected: mock log shows exactly the actionable pokes

# Test 7: paused kill switch
touch "$T/state/paused"; $DAEMON
# Expected: no claims, no ticks, log says paused

# Test 8: dry-run regression (r1-02 bugfix)
B=$(wc -l < "$T/projA/.planning/events.jsonl")
ORCH_STATE_DIR=$T/state PM_ITERATE_MOCK=/dev/null ./scripts/pm-iterate.sh "$T/projA" --dry-run
test "$(wc -l < "$T/projA/.planning/events.jsonl")" = "$B"
# Expected: events.jsonl line count unchanged

# Test 9: r1-02 suite still green
bash .planning/phases/r1-02-pm-iterate/smoke-tests.sh
# Expected: 16 passed, 0 failed
```

## Completion Instructions

1. `bash -n` on shell files, `node --check services/pm-daemon.js`, run BOTH this phase's
   smoke-tests.sh AND the r1-02 suite — all green.
2. Write result.md + result.json in this phase dir.
3. Commit with prefix `[orchestrator-r1-03]` and push to origin master.
