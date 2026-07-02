# Phase r1-02: Headless PM Iteration Runner (pm-iterate.sh)

## Context

Project **orchestrator-r1r2** ("Resident PM") — see `.planning/brief.md` and
`.planning/project.md`. The future daemon (phase r1-03) will detect worker responses for
orchestrated projects and needs a safe, bounded way to run ONE orchestration-loop
iteration headlessly. This phase builds that runner. It is the highest-risk component:
it invokes `claude -p` non-interactively, so every guardrail (locking, caps, kill
switches, escalation gate) lives HERE, not in the daemon.

## Prior Work Summary

- Phase r1-01 (commit 7c9f4f0) shipped `scripts/register-project.sh` +
  `scripts/queue-phase.sh` and the state-dir convention: everything under
  `${ORCH_STATE_DIR:-$HOME/.orchestrator}`; project registry at
  `$ORCH_STATE_DIR/active-projects.json` (fields: name, local_path, worker, remote_path,
  active, registered_at); dispatch ledger at `$ORCH_STATE_DIR/dispatch-ledger.jsonl`
  (task_id as JSON string). `register-project.sh get <name>` prints an entry; project-name
  resolution order used there: registry → status.json `.project` → basename. Reuse it.
- The orchestration loop the headless PM must execute is defined in this repo's
  `CLAUDE.md` ("The Orchestration Loop", "Verification", "Autonomy Rules"). The runner
  does NOT reimplement that logic — it hands it to Claude via the prompt.
- Escalation rule (P2-D): a phase with an unresolved `ai_escalation_recommended` event in
  the project's `.planning/events.jsonl` must NEVER be auto-revised. The runner enforces
  a cheap mechanical version of this gate before spending any tokens.
- `claude` CLI ≥2.1 is installed on the controller. Headless mode:
  `claude -p "<prompt>" --allowedTools Bash,Read,Write,Edit,Glob,Grep --max-turns <N> [--model <m>] --output-format text`.
  In headless mode, tools outside --allowedTools are denied. DO NOT invoke the real CLI
  in tests — this DEV machine must run everything through the mock (see below).
- House style: bash, `set -euo pipefail`, usage(), hermetic smoke tests under `mktemp -d`
  with `trap ... EXIT` (see `.planning/phases/r1-01-dispatch-ledger/smoke-tests.sh`).

## Objective

Create `scripts/pm-iterate.sh`: given a project path and a trigger, apply all guardrails
(pause, interrupt, per-project lock, hourly cap, escalation gate), build a bounded
single-iteration PM prompt, invoke headless claude (or a mock), log the transcript and an
iterations-ledger line, and exit with a machine-readable disposition — proven by hermetic
smoke tests that never call the real claude CLI.

## Implementation Steps

1. **Interface.**
   `pm-iterate.sh <project-path> [--trigger response|tick|resolution] [--response-file <path>] [--dry-run]`
   - `--trigger` defaults to `tick`. `--response-file` points at a worker-response JSON
     to inline into the prompt (typical for `--trigger response`).
   - `--dry-run`: run ALL guardrails and write the prompt file, but skip the claude
     invocation; print `DRYRUN: prompt at <path>` and exit 0.
   - Env knobs (all with defaults): `ORCH_STATE_DIR` ($HOME/.orchestrator),
     `PM_MAX_ITER_PER_HOUR` (6), `PM_MAX_TURNS` (80), `PM_ITERATE_TIMEOUT` (1800 s),
     `PM_CLAUDE_MODEL` (empty → CLI default), `PM_CLAUDE_BIN` (claude),
     `PM_ITERATE_MOCK` (path to canned transcript → mock mode).

2. **Guardrails, checked in this order.** Guard-skips are NOT errors: print
   `SKIP: <reason>` to stdout and exit 0 (the daemon treats exit 0 + SKIP as a no-op).
   1. **Paused:** `$ORCH_STATE_DIR/paused` exists → `SKIP: paused`.
   2. **Interrupt:** `<project-path>/.planning/interrupt.json` exists → `SKIP: interrupted`.
   3. **Lock:** non-blocking `flock` on `$ORCH_STATE_DIR/locks/<name>.lock`; already held
      → `SKIP: locked`. The lock must be held for the entire remainder of the run
      (guards 4–5, prompt build, claude invocation, ledger write).
   4. **Hourly cap:** count lines in `$ORCH_STATE_DIR/iterations.jsonl` with this project
      name and `ts` within the last 3600 s (jq + epoch comparison); if ≥ cap →
      `SKIP: rate-capped (<n>/<cap> in last hour)`.
   5. **Escalation gate:** read the project's current phase from
      `.planning/status.json` (`.current_phase`). If `.planning/events.jsonl` contains an
      `ai_escalation_recommended` event for that phase with NO later
      `escalation_resolved` event for the same phase, and `--trigger` is NOT
      `resolution` → `SKIP: escalated-awaiting-human`. (A `resolution` trigger bypasses
      the gate — that is exactly how a human unblocks it in r2-05.)

3. **Prompt build.** Write `$ORCH_STATE_DIR/runs/<name>/<UTC-ts>-prompt.md` containing,
   in order:
   - Role header: "You are the orchestrator PM (headless). Execute EXACTLY ONE iteration
     of the orchestration loop for the project below, then STOP. Do not loop. Do not
     start a second state transition."
   - Pointers: orchestrator repo dir (resolve from the script's own location), project
     path, project name, trigger, current UTC timestamp.
   - Instruction to read `<orchestrator-dir>/CLAUDE.md` (loop + verification + autonomy
     rules) and the project's `.planning/status.json` before acting.
   - If `--response-file` given: a "Worker response (task awaiting verification)" section
     with the file's full JSON content inlined, plus its path.
   - Hard rules block (verbatim in the prompt):
     * ONE state transition only (e.g. verify-and-complete OR verify-and-revise OR
       spec-and-queue next phase), then exit.
     * Dispatch ONLY via `<orchestrator-dir>/scripts/queue-phase.sh` — never call
       add-task.sh directly (the ledger must stay consistent).
     * Never implement project code yourself; never skip verification; respect all
       CLAUDE.md NEVER rules including the escalation rule.
     * On checkpoint due, escalation, max-revisions, or project completion: call
       `scripts/notify.sh <event> <project-path> ...` and STOP.
     * Update `.planning/status.json` + `events.jsonl`, commit `.planning/` with prefix
       `[<project>-orchestrator]`, and push, before exiting.
   - Also emit an `iteration_started` event to the project's events.jsonl BEFORE invoking
     claude: `{"ts":"...","event":"pm_iteration","data":{"trigger":"<t>","runner":"pm-iterate"}}`.

4. **Invocation.**
   - Mock mode (`PM_ITERATE_MOCK` set): copy that file's content as the transcript;
     exit code from `PM_ITERATE_MOCK_EXIT` (default 0). No claude call. Mock mode must
     still exercise everything else (guards, prompt build, logging).
   - Real mode: run
     `timeout "$PM_ITERATE_TIMEOUT" "$PM_CLAUDE_BIN" -p "$(cat <prompt-file>)" --allowedTools Bash,Read,Write,Edit,Glob,Grep --max-turns "$PM_MAX_TURNS" --output-format text`
     with `--model "$PM_CLAUDE_MODEL"` appended only when non-empty, `cwd` =
     `<project-path>`, stdout+stderr → `$ORCH_STATE_DIR/runs/<name>/<UTC-ts>-transcript.log`
     (same ts as the prompt file).
   - Afterwards append to `$ORCH_STATE_DIR/iterations.jsonl`:
     `{"ts":"<ISO-8601 UTC>","project":"<name>","trigger":"<t>","exit_code":<n>,"duration_s":<n>,"prompt":"<path>","transcript":"<path>"}`
   - Final stdout line: `RAN: exit=<n> transcript=<path>`; propagate claude's exit code
     (timeout → 124 propagates too).

5. **Smoke tests** → `.planning/phases/r1-02-pm-iterate/smoke-tests.sh`, hermetic:
   temp `ORCH_STATE_DIR` + fake project dir with minimal `.planning/status.json`
   (`{"project":"demo","current_phase":"01-x"}`) and events.jsonl; ALWAYS set
   `PM_ITERATE_MOCK` (and never install a real `claude`). Cover the Smoke Tests section
   below. Also create `templates/test-fixtures/mock-pm-transcript.txt` (a few plausible
   transcript lines) used as the mock payload.

## Files to Create

- `scripts/pm-iterate.sh`
- `templates/test-fixtures/mock-pm-transcript.txt`
- `.planning/phases/r1-02-pm-iterate/smoke-tests.sh`
- `.planning/phases/r1-02-pm-iterate/result.md` (+ result.json)

## Files to Modify

- None.

## Do NOT Touch

- `scripts/register-project.sh`, `scripts/queue-phase.sh` (consume, don't edit)
- All other existing scripts, templates, CLAUDE.md, docs/ (docs land in r1r2-06)
- Anything outside this repo; NEVER invoke a real `claude` CLI, no SSH, no network

## Cleanup

All test state under `mktemp -d`, removed via `trap ... EXIT`. Re-running the suite must
pass identically.

## Expected Files Changed

```
scripts/pm-iterate.sh
templates/test-fixtures/mock-pm-transcript.txt
.planning/phases/r1-02-pm-iterate/smoke-tests.sh
.planning/phases/r1-02-pm-iterate/result.md
.planning/phases/r1-02-pm-iterate/result.json
```

## Acceptance Criteria

- [ ] Guard order + messages exactly as specified; every guard-skip prints `SKIP: <reason>` and exits 0 without writing a transcript or iterations.jsonl line.
- [ ] Concurrent second invocation while the lock is held skips with `SKIP: locked` (test with a background invocation using a slow mock).
- [ ] Hourly cap counts ONLY this project's iterations within 3600 s; older lines and other projects don't count; cap reached → `SKIP: rate-capped...`.
- [ ] Escalation gate: unresolved `ai_escalation_recommended` for the current phase blocks `tick`/`response` triggers but NOT `--trigger resolution`; a subsequent `escalation_resolved` event unblocks all triggers.
- [ ] Prompt file contains: the ONE-iteration rule, the queue-phase.sh-only dispatch rule, project path + name + trigger, and (when `--response-file` given) the inlined response JSON.
- [ ] Mock run writes transcript, appends a valid iterations.jsonl line (jq-parseable, correct project/trigger/exit_code), prints `RAN: exit=0 ...`, and `PM_ITERATE_MOCK_EXIT=7` propagates exit 7 while still logging the line with `exit_code:7`.
- [ ] `--dry-run` writes the prompt but no transcript and no iterations line.
- [ ] `bash -n` clean; smoke-tests.sh exits 0, all tests pass, nothing written outside the temp dirs.

## Smoke Tests

```bash
# Preamble: T=$(mktemp -d); export ORCH_STATE_DIR="$T/state" PM_ITERATE_MOCK="$T/mock.txt"
# fake project: $T/proj/.planning/{status.json,events.jsonl}; cp fixture to $T/mock.txt

# Test 1: paused kill switch
touch "$ORCH_STATE_DIR/paused"  # (mkdir -p first)
./scripts/pm-iterate.sh "$T/proj" | grep -q '^SKIP: paused'
# Expected: exit 0, no transcript written

# Test 2: interrupt.json
echo '{}' > "$T/proj/.planning/interrupt.json"
./scripts/pm-iterate.sh "$T/proj" | grep -q '^SKIP: interrupted'
# Expected: exit 0

# Test 3: normal mock run
./scripts/pm-iterate.sh "$T/proj" --trigger tick | grep -q '^RAN: exit=0'
tail -1 "$ORCH_STATE_DIR/iterations.jsonl" | jq -e '.project=="demo" and .trigger=="tick" and .exit_code==0'
# Expected: exit 0, transcript file exists and equals mock content

# Test 4: response-file inlined into prompt
echo '{"id":123,"response":"UNIQUE_MARKER_XYZ"}' > "$T/resp.json"
./scripts/pm-iterate.sh "$T/proj" --trigger response --response-file "$T/resp.json"
grep -q UNIQUE_MARKER_XYZ "$(ls -t "$ORCH_STATE_DIR/runs/demo/"*-prompt.md | head -1)"
# Expected: exit 0

# Test 5: hourly cap
PM_MAX_ITER_PER_HOUR=2 ./scripts/pm-iterate.sh "$T/proj"   # (after 2 runs already logged)
# Expected: 'SKIP: rate-capped' once ledger has 2 recent lines for demo; a 1h-old line must NOT count

# Test 6: lock contention (slow mock in background, second call skips)
# Expected: second invocation prints 'SKIP: locked', exit 0

# Test 7: escalation gate
echo '{"ts":"2026-07-02T00:00:00Z","event":"ai_escalation_recommended","data":{"phase":"01-x"}}' >> "$T/proj/.planning/events.jsonl"
./scripts/pm-iterate.sh "$T/proj" | grep -q '^SKIP: escalated-awaiting-human'
./scripts/pm-iterate.sh "$T/proj" --trigger resolution | grep -q '^RAN:'
echo '{"ts":"2026-07-02T00:10:00Z","event":"escalation_resolved","data":{"phase":"01-x"}}' >> "$T/proj/.planning/events.jsonl"
./scripts/pm-iterate.sh "$T/proj" | grep -q '^RAN:'
# Expected: blocked, bypassed by resolution trigger, unblocked after resolved event

# Test 8: mock exit propagation + dry-run
PM_ITERATE_MOCK_EXIT=7 ./scripts/pm-iterate.sh "$T/proj"; test $? -eq 7
./scripts/pm-iterate.sh "$T/proj" --dry-run | grep -q '^DRYRUN:'
# Expected: exit 7 with iterations line exit_code==7; dry-run writes prompt only
```

## Completion Instructions

1. `bash -n scripts/pm-iterate.sh`, then run smoke-tests.sh — all green.
2. Write result.md + result.json in this phase dir.
3. Commit with prefix `[orchestrator-r1-02]` and push to origin master.
