# Phase r1-01: Dispatch Ledger & Project Registry

## Context

Project **orchestrator-r1r2** ("Resident PM") makes the orchestration loop run unattended:
a daemon on the controller machine (lipo-360) will detect DEV-worker responses that belong
to orchestrated projects and spawn a headless single-iteration PM run. Read
`.planning/brief.md` and `.planning/project.md` for the full picture.

This phase builds the **foundation**: a machine-readable record of (a) which projects are
under active orchestration and (b) which queue task_id maps to which project/phase. Without
this ledger, the future daemon (phase r1-03) cannot tell an orchestrator phase-response
apart from any other super-agent task response.

## Prior Work Summary

- This repo (orchestrator) is a bash-script framework. Scripts live in `scripts/`, follow
  `set -euo pipefail`, and have `usage()` functions. See `scripts/notify.sh` and
  `scripts/cancel-task.sh` for the house style.
- On the controller machine, tasks are dispatched to workers via a **super-agent** repo
  (default location `$HOME/awesome/super-agent`, NOT present on this DEV machine — do not
  try to call it for real). Its dispatch scripts are:
  - `scripts/add-task.sh "<task text>"` → queues to worker `hetzner`
  - `scripts/add-task-local.sh "<task text>"` → queues to worker `wsl2`
  - Both accept optional leading flags `--repo <id>` and `--priority <n>`.
  - Both print, among other lines, exactly: `ID: <task_id>` (task_id = 16–19 digit number)
    early in stdout, and on success `Task queued: <task_id>`. Non-zero exit or a final
    fallback message `Task saved locally:` means queueing to the worker FAILED.
- Worker responses later arrive on the controller as `tasks/responses/new/<task_id>.json`
  inside the super-agent repo (not this phase's concern, but it is why the task_id mapping
  matters).
- Test convention: `scripts/integration-test.sh` (sprint 8) builds hermetic tests using
  temp dirs + PATH/env overrides + mock executables. Reuse that pattern.

## Objective

Create `scripts/register-project.sh` and `scripts/queue-phase.sh` so that every phase
dispatch is recorded in an append-only JSONL ledger under a configurable state dir
(default `~/.orchestrator/`), and active orchestrated projects are tracked in a JSON
registry — with hermetic smoke tests proving both against a mock add-task script.

## Implementation Steps

1. **Shared state-dir convention.** Both scripts resolve the state dir as
   `${ORCH_STATE_DIR:-$HOME/.orchestrator}` and create it (mode 700) if missing.

2. **`scripts/register-project.sh`** — manage `$ORCH_STATE_DIR/active-projects.json`
   (a JSON array of objects). Subcommand-style interface:
   - `register-project.sh add <project-path> [--name <name>] [--worker hetzner|wsl2] [--remote-path <path>]`
     - `--name` defaults to the `project` field of `<project-path>/.planning/status.json`
       (via jq), falling back to `basename <project-path>`.
     - `--worker` defaults to `hetzner`. `--remote-path` defaults to
       `~/awsc-new/awesome/<name>`.
     - Writes/updates entry: `{name, local_path (absolute), worker, remote_path, active: true, registered_at (ISO-8601 UTC)}`.
     - Re-adding an existing name UPDATES it in place (idempotent), preserving `registered_at`.
   - `register-project.sh deactivate <name>` — sets `active: false` (keeps the entry).
   - `register-project.sh list [--json]` — human table by default; `--json` prints raw array.
   - `register-project.sh get <name>` — prints the entry JSON; exit 1 if not found.
   - Use jq for all JSON manipulation; write atomically (tmp file + `mv`).

3. **`scripts/queue-phase.sh`** — ledger-recording dispatch wrapper:
   - Usage: `queue-phase.sh <project-path> <phase-name> [--worker hetzner|wsl2] [--repo <id>] [--priority <n>] <task-text>`
   - Resolves the dispatch script from `${SUPER_AGENT_DIR:-$HOME/awesome/super-agent}`:
     worker `hetzner` → `scripts/add-task.sh`, worker `wsl2` → `scripts/add-task-local.sh`.
     Error out clearly if the script is missing/non-executable.
   - `--worker` defaults to the registry entry for this project (if registered), else `hetzner`.
   - Runs the dispatch script (passing `--repo`/`--priority` through when given), teeing
     its stdout to the terminal, and parses the task id from the `ID: <digits>` line.
   - On SUCCESS (exit 0 AND stdout contains `Task queued: <id>`):
     1. Append one line to `$ORCH_STATE_DIR/dispatch-ledger.jsonl`:
        `{"ts":"<ISO-8601 UTC>","task_id":"<id>","project":"<name>","project_path":"<abs path>","phase":"<phase-name>","worker":"<worker>"}`
        (task_id as a STRING — these exceed 2^53 and must never be parsed as a JS number).
     2. Append a `phase_queued` event to `<project-path>/.planning/events.jsonl`:
        `{"ts":"...","event":"phase_queued","data":{"phase":"<phase-name>","task_id":"<id>","worker":"<worker>"}}`
        (create the file if missing; skip with a warning if `.planning/` doesn't exist).
     3. Print a confirmation line: `LEDGER: task <id> -> <project>/<phase> (<worker>)`.
   - On FAILURE (non-zero exit, or no `Task queued:` line, or `Task saved locally:`
     fallback detected): write NOTHING to the ledger, print an error, exit 1.
   - Project name resolution: registry entry for `<project-path>` if present, else
     status.json `project` field, else basename.

4. **Hermetic smoke-test fixture.** Create `templates/test-fixtures/mock-add-task.sh`:
   a mock that mimics the real contract — consumes optional `--repo`/`--priority` flags,
   requires a task-text arg, prints `ID: <generated 18-digit id>` and `Task queued: <id>`,
   exits 0. Honor env `MOCK_ADDTASK_FAIL=1` → print an error + `Task saved locally: /tmp/x.json`,
   exit 0 (simulates the local-fallback path, which queue-phase must treat as failure)
   and `MOCK_ADDTASK_EXIT=1` → exit 1.

5. **Write the executable smoke tests** to
   `.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh` (copy the Smoke Tests section
   below verbatim into a runnable script with a pass/fail summary and exit code).

## Files to Create

- `scripts/register-project.sh`
- `scripts/queue-phase.sh`
- `templates/test-fixtures/mock-add-task.sh`
- `.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh`
- `.planning/phases/r1-01-dispatch-ledger/result.md` (+ result.json)

## Files to Modify

- None.

## Do NOT Touch

- Any existing script in `scripts/` (verify.sh, notify.sh, failover.sh, etc.)
- `templates/spec.md`, `templates/result*.md`, existing test fixtures
- `CLAUDE.md`, `docs/` (documentation lands in phase r1r2-06)
- Anything outside this repo (in particular: no SSH to other machines, no real
  super-agent calls)

## Cleanup

Smoke tests must create ALL state under `mktemp -d` dirs (`ORCH_STATE_DIR`,
`SUPER_AGENT_DIR`, fake project dir) and remove them via `trap ... EXIT`. Re-running the
suite must pass identically (idempotent).

## Expected Files Changed

```
scripts/register-project.sh
scripts/queue-phase.sh
templates/test-fixtures/mock-add-task.sh
.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh
.planning/phases/r1-01-dispatch-ledger/result.md
.planning/phases/r1-01-dispatch-ledger/result.json
```

## Acceptance Criteria

- [ ] `register-project.sh add` creates `active-projects.json` under `$ORCH_STATE_DIR` with all 6 fields; `get`/`list --json` return valid jq-parseable JSON; re-`add` is idempotent (no duplicate entries); `deactivate` flips `active` to false.
- [ ] `queue-phase.sh` with the mock dispatch script appends exactly one valid JSONL ledger line per successful dispatch, with `task_id` as a JSON string matching the mock's printed ID.
- [ ] `queue-phase.sh` appends a `phase_queued` event (with task_id) to the project's `.planning/events.jsonl`.
- [ ] `queue-phase.sh` writes NO ledger line and exits 1 when the dispatch script exits non-zero AND when it falls back to `Task saved locally:`.
- [ ] Worker routing: `--worker wsl2` invokes `add-task-local.sh`; default resolves from the registry when the project is registered.
- [ ] All state paths honor `ORCH_STATE_DIR` and `SUPER_AGENT_DIR` overrides; nothing is written to the real `$HOME/.orchestrator` during tests.
- [ ] `bash -n` passes on both new scripts; smoke-tests.sh exits 0 with all tests passing.

## Smoke Tests

```bash
# Setup (each test block assumes this preamble)
T=$(mktemp -d); export ORCH_STATE_DIR="$T/state" SUPER_AGENT_DIR="$T/sa"
mkdir -p "$SUPER_AGENT_DIR/scripts" "$T/proj/.planning"
echo '{"project":"demo-proj"}' > "$T/proj/.planning/status.json"
cp templates/test-fixtures/mock-add-task.sh "$SUPER_AGENT_DIR/scripts/add-task.sh"
cp templates/test-fixtures/mock-add-task.sh "$SUPER_AGENT_DIR/scripts/add-task-local.sh"
chmod +x "$SUPER_AGENT_DIR/scripts/"*.sh

# Test 1: register + get round-trip
./scripts/register-project.sh add "$T/proj" --worker hetzner
./scripts/register-project.sh get demo-proj | jq -e '.active == true and .worker == "hetzner"'
# Expected: exit 0

# Test 2: idempotent re-add (still exactly 1 entry)
./scripts/register-project.sh add "$T/proj"
test "$(./scripts/register-project.sh list --json | jq 'length')" = "1"
# Expected: exit 0

# Test 3: successful dispatch writes ledger + event
./scripts/queue-phase.sh "$T/proj" 01-test "hello world task"
tail -1 "$ORCH_STATE_DIR/dispatch-ledger.jsonl" | jq -e '.project=="demo-proj" and .phase=="01-test" and (.task_id|type)=="string"'
tail -1 "$T/proj/.planning/events.jsonl" | jq -e '.event=="phase_queued" and .data.task_id != null'
# Expected: exit 0 on all three

# Test 4: ledger task_id matches the ID the dispatcher printed
OUT=$(./scripts/queue-phase.sh "$T/proj" 02-test "second task")
PRINTED=$(echo "$OUT" | grep -oE 'ID: [0-9]+' | grep -oE '[0-9]+')
test "$(tail -1 "$ORCH_STATE_DIR/dispatch-ledger.jsonl" | jq -r .task_id)" = "$PRINTED"
# Expected: exit 0

# Test 5: failed dispatch (exit 1) writes nothing
BEFORE=$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")
MOCK_ADDTASK_EXIT=1 ./scripts/queue-phase.sh "$T/proj" 03-test "will fail" && exit 1
test "$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")" = "$BEFORE"
# Expected: queue-phase exits 1, ledger unchanged

# Test 6: local-fallback (Task saved locally) treated as failure
MOCK_ADDTASK_FAIL=1 ./scripts/queue-phase.sh "$T/proj" 04-test "fallback" && exit 1
test "$(wc -l < "$ORCH_STATE_DIR/dispatch-ledger.jsonl")" = "$BEFORE"
# Expected: queue-phase exits 1, ledger unchanged

# Test 7: deactivate flips flag
./scripts/register-project.sh deactivate demo-proj
./scripts/register-project.sh get demo-proj | jq -e '.active == false'
# Expected: exit 0
```

## Completion Instructions

1. Run `bash -n` on both scripts, then run `smoke-tests.sh` — all tests must pass.
2. Write `.planning/phases/r1-01-dispatch-ledger/result.md` (summary, decisions, test
   output) and `result.json` (`{status, files_modified[], tests_run[], blockers[], summary}`).
3. Commit with prefix `[orchestrator-r1-01]` and push to origin master.
