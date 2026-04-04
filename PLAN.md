# Orchestrator — Autonomous Multi-Phase Project Execution Framework

## Problem Statement

Claude Code sessions have context window limits. Large implementation projects (3+ features, multi-file changes, multi-day work) inevitably exceed a single session. Today we handle this ad-hoc: manually writing specs, manually queuing tasks, manually tracking progress. This works but doesn't scale, isn't reusable, and requires constant user babysitting.

**We need a general-purpose orchestration framework** that:
- Breaks any project into executable phases
- Survives unlimited context resets
- Coordinates PM (lipo-360) and DEV (>>hetzner/>>wsl2) instances
- Runs autonomously with minimal user involvement
- Works for both new and existing projects
- Verifies results independently, not just trusting DEV self-reports

## Architecture

### Participants

```
┌─────────────────────────────────────────────────────┐
│                      USER                           │
│  Provides: project brief, credentials, boundaries   │
│  Reviews: checkpoints + final output                 │
└──────────────┬──────────────────────────────────────┘
               │ (initial input + optional checkpoints)
               ▼
┌─────────────────────────────────────────────────────┐
│              ORCHESTRATOR (lipo-360)                 │
│  Plans, breaks into phases, writes specs             │
│  Queues work, INDEPENDENTLY verifies results         │
│  Runs smoke tests, advances or revises phases        │
│  Autonomous — stops only at checkpoints or dead ends │
└──────────────┬──────────────────────────────────────┘
               │ (queue via add-task.sh)
               ▼
┌─────────────────────────────────────────────────────┐
│           DEV WORKER (>>hetzner / >>wsl2)           │
│  Pulls spec from git, implements, tests              │
│  Commits results, writes completion report           │
│  Never plans — only executes current phase           │
└─────────────────────────────────────────────────────┘
```

### Communication Channel

- **Git** is the source of truth for specs, results, and code
- **SQLite queue** (add-task.sh) is the task dispatch mechanism
- **Event log** (events.jsonl) is the append-only execution history
- **status.json** is the derived cross-session resume point
- No Slack, no email, no external tools required

## Entry Points

The orchestrator handles three scenarios:

### A. New Project (no existing code)

```
orchestrator init --new <project-path>
```

**Requires from user:**
- Project brief (what to build, why)
- Tech stack preferences (or "you decide")
- Target environment (where it runs)
- Success criteria (how we know it's done)

**Orchestrator does:**
1. Create project directory + `.planning/` structure
2. Generate Level-0 plan — high-level scope for ALL phases
3. Generate Level-1 detail for Phase 1 only
4. Begin Phase 1 autonomously

### B. Existing Project (add features / refactor)

```
orchestrator init --existing <project-path>
```

**Requires from user:**
- Project path (where the code lives)
- What to change (new features, refactors, fixes)
- Boundaries (what NOT to touch)
- Success criteria

**Orchestrator does:**
1. Scan codebase (medium depth — see Codebase Scan Strategy)
2. Generate snapshot.md (~500 lines, not a full dump)
3. Create `.planning/` structure informed by actual code
4. Generate Level-0 plan for all phases
5. Generate Level-1 detail for Phase 1
6. Begin Phase 1 autonomously

### C. Resume (`.planning/` already exists)

```
orchestrator resume <project-path>
```

**Requires from user:** Nothing. Reads status.json and continues.

**Orchestrator does:**
1. Read `status.json` — identify current phase
2. Check if pending results need verification
3. Continue from where it left off

### D. Dry Run (plan without executing)

```
orchestrator plan --dry-run <project-path>
```

**Orchestrator does:**
1. Generate Level-0 plan for all phases
2. Generate Level-1 detail (scope + key decisions) for all phases
3. Output full plan for user review — NO queuing, NO execution
4. User reviews, adjusts, then runs `orchestrator execute` to begin

## Project Brief Template

The initial user input that determines how autonomous the execution can be.

```markdown
# Project Brief

## What
[1-3 sentences: what are we building or changing]

## Why
[1-2 sentences: what problem does this solve]

## Where
- Project path: [/home/mp/awesome/project-name/]
- Target environment: [hetzner / wsl2 / both]
- Live URL (if any): [https://...]

## Boundaries
- Do NOT touch: [files, systems, databases to leave alone]
- Do NOT deploy to: [production / staging restrictions]
- Budget constraints: [API costs, time limits]

## Success Criteria
[How do we know the project is DONE? Be specific.]
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

## Access & Credentials
- [Any API keys, DB passwords, SSH access needed]
- [Or: "already configured in .env"]

## Preferences (optional)
- Tech stack: [or "you decide"]
- Code style: [or "match existing"]
- Testing: [required / nice-to-have / skip]
- Checkpoint frequency: [every N phases / never / always]
```

**Rule: If the brief answers these sections clearly, the orchestrator should be able to complete the project without asking the user anything until the next checkpoint or final review.**

## Autonomy Model

### Level 0: FULL STOP — Need User

Orchestrator halts and waits for user input:

- **Initial project brief** — can't start without knowing what to build
- **Missing credentials / access** — can't authenticate without keys
- **Destructive actions** — deleting production data, force-pushing to main, modifying live infrastructure
- **Dead end** — technical blocker that can't be resolved autonomously
- **Revision failed** — DEV worker failed 3 times on same phase (or 5 times for complex phases)
- **Project complete** — final review before closing

### Level 0.5: CHECKPOINT — Optional User Review

Orchestrator pauses at defined intervals. User can review progress or skip:

- **Every 3rd completed phase** (default, configurable in brief)
- **When plan changes significantly** — phases merged, split, reordered, or new phases added
- **User can pre-authorize skip:** `"checkpoint_frequency": "never"` in brief = full autonomy

Checkpoint format:
```
CHECKPOINT: Phases 1-3 complete.
- Phase 1: [summary] ✅
- Phase 2: [summary] ✅
- Phase 3: [summary] ✅
- Next: Phase 4 [description]
- Plan changes: [none / description]

Reply "continue" to proceed or provide feedback.
```

### Level 1: NOTIFY — Keep Going, Tell User Later

Orchestrator continues working but appends to notifications.md:

- Phase completed successfully
- Plan revised (phases merged, split, or reordered)
- Unexpected technical constraint discovered (but worked around)
- DEV worker failed and was re-queued with corrections
- Budget/time threshold reached (e.g., "5 of 8 phases complete")

### Level 2: SILENT — Just Do It

No notification, no stopping:

- Architecture decisions within stated constraints
- Task/phase breakdown granularity
- Bug fixes and retry logic with DEV worker
- Code style, naming, file structure choices
- Phase transitions when acceptance criteria pass
- Choosing between equivalent technical approaches

## Planning Model: Hybrid Progressive Detail

Instead of fully upfront or fully progressive, we use two levels of detail:

### Level-0: Full Scope (all phases, done once at init)
- Phase names, one-line descriptions, dependencies
- Execution order and parallelization opportunities
- High-level architecture decisions that affect multiple phases
- Written to `project.md`

### Level-1: Implementation Detail (per phase, done just before execution)
- Full spec.md with implementation steps, files to modify, acceptance criteria, smoke tests
- Informed by current codebase state (not stale assumptions from init time)
- Written to `phases/XX-<name>/spec.md`

**Why hybrid:** Level-0 gives the DEV worker big-picture context and lets the orchestrator plan dependencies. Level-1 waits until execution time so specs reflect reality after prior phases changed the codebase.

## Directory Structure

Every orchestrated project gets this structure:

```
<project-root>/
├── .planning/
│   ├── brief.md                  # Original user brief (immutable)
│   ├── project.md                # Level-0 plan (evolves)
│   ├── status.json               # Machine-readable progress (derived from events)
│   ├── events.jsonl              # Append-only execution log
│   ├── snapshot.md               # Codebase scan results (Path B only)
│   ├── learnings.md              # Discoveries that inform future phases
│   ├── notifications.md          # Level 1 notifications for user
│   └── phases/
│       ├── 01-<phase-name>/
│       │   ├── spec.md           # Level-1 detail (written by orchestrator)
│       │   ├── result.md         # Completion report (written by DEV worker)
│       │   └── revisions/       # Re-queue specs if first attempt failed
│       │       ├── rev-01.md    # Includes: what failed + prior context
│       │       └── rev-02.md
│       ├── 02-<phase-name>/
│       │   ├── spec.md
│       │   └── result.md
│       └── ...
```

## Event Log (events.jsonl)

Append-only log of everything that happened. More debuggable than mutable status.json.

```jsonl
{"ts":"2026-03-14T12:00:00Z","event":"project_init","data":{"path":"/home/mp/awesome/blog-publisher","type":"existing"}}
{"ts":"2026-03-14T12:01:00Z","event":"phase_specified","data":{"phase":"01-publish-history"}}
{"ts":"2026-03-14T12:02:00Z","event":"phase_queued","data":{"phase":"01-publish-history","task_id":"1773494398424"}}
{"ts":"2026-03-14T12:30:00Z","event":"phase_response","data":{"phase":"01-publish-history","task_id":"1773494398424"}}
{"ts":"2026-03-14T12:31:00Z","event":"smoke_test_pass","data":{"phase":"01-publish-history","test":"curl /api/health → 200"}}
{"ts":"2026-03-14T12:31:00Z","event":"smoke_test_pass","data":{"phase":"01-publish-history","test":"curl /api/history → 200"}}
{"ts":"2026-03-14T12:31:00Z","event":"phase_complete","data":{"phase":"01-publish-history","commit":"3a26442"}}
{"ts":"2026-03-14T12:32:00Z","event":"phase_specified","data":{"phase":"02-categories-tags"}}
```

**status.json is derived from events.jsonl** — can be reconstructed at any time. Events are the source of truth.

## Learnings Log (learnings.md)

Discoveries made during execution that inform future phases:

```markdown
# Learnings

## Phase 01
- pg_trgm extension IS available on this PostgreSQL instance
- Codebase uses ESM (import/export), not CommonJS
- Express server has no test suite — acceptance testing is via curl
- Frontend uses vanilla JS, no framework — DOM manipulation only

## Phase 02
- WordPress API returns max 100 items per request for categories/tags
- Some sites have 0 tags — UI must handle empty state
```

**Why:** Each phase's spec can reference learnings to avoid the DEV worker re-discovering the same things. Reduces revision cycles.

## status.json Schema

```json
{
  "project": "project-name",
  "created": "2026-03-15",
  "updated": "2026-03-15",
  "status": "in-progress",
  "current_phase": "02-categories-tags",
  "checkpoint_frequency": 3,
  "phases_since_checkpoint": 1,
  "phases": {
    "01-publish-history": {
      "status": "complete",
      "complexity": "standard",
      "queued_at": "2026-03-14T12:00:00Z",
      "completed_at": "2026-03-14T12:30:00Z",
      "task_id": "1773494398424",
      "commit": "3a26442",
      "revisions": 0,
      "smoke_tests_passed": 3,
      "smoke_tests_total": 3
    },
    "02-categories-tags": {
      "status": "queued",
      "complexity": "standard",
      "queued_at": "2026-03-14T12:35:00Z",
      "task_id": "1773494803467",
      "revisions": 0
    },
    "03-images": {
      "status": "pending",
      "complexity": "complex",
      "depends_on": ["01-publish-history"]
    }
  },
  "execution_order": ["01-publish-history", "02-categories-tags", "03-images"],
  "blocked": false,
  "blocked_reason": null,
  "metrics": {
    "phases_complete": 1,
    "phases_total": 3,
    "total_revisions": 0,
    "total_smoke_tests": 3,
    "started_at": "2026-03-14T12:00:00Z"
  }
}
```

## Phase Lifecycle

```
                    ┌──────────────────────┐
                    │      PENDING         │
                    │  (not yet detailed)  │
                    └──────────┬───────────┘
                               │ orchestrator writes spec.md
                               ▼
                    ┌──────────────────────┐
                    │      SPECIFIED       │
                    │  (spec.md ready)     │
                    └──────────┬───────────┘
                               │ queued via add-task.sh
                               ▼
                    ┌──────────────────────┐
                    │      QUEUED          │
                    │  (sent to DEV)       │
                    └──────────┬───────────┘
                               │ DEV completes, writes result.md
                               ▼
                    ┌──────────────────────┐
                    │    VERIFYING         │
                    │  (smoke tests +      │
                    │   criteria check)    │
                    └──────────┬───────────┘
                              ╱ ╲
                             ╱   ╲
                    pass?  ╱     ╲  fail?
                          ╱       ╲
                         ▼         ▼
              ┌─────────────┐  ┌──────────────────┐
              │  COMPLETE   │  │    REVISION       │
              │  (advance)  │  │  (re-queue with   │
              └──────┬──────┘  │   prior context)  │
                     │         └────────┬──────────┘
                     │                  │ revision < max?
                     │                  │ yes → back to QUEUED
                     │                  │ no ↓
                     │         ┌────────────────────┐
                     │         │  REVISION_FAILED   │
                     │         │  (escalate to user)│
                     │         └────────────────────┘
                     │
                     │ checkpoint due?
                     ├── yes → CHECKPOINT (pause for user)
                     └── no  → next phase (continue loop)

Additional states:
  BLOCKED  — waiting on external dependency (credential, API access, user decision)
  SKIPPED  — user marked phase as not needed
  MERGED   — combined into another phase mid-execution
```

## Verification Strategy

The orchestrator INDEPENDENTLY verifies results. Does NOT trust DEV self-reports alone.

### Step 1: Basic Checks
- result.md exists and is non-empty
- Git commit exists with correct prefix
- No uncommitted changes left behind

### Step 2: Smoke Tests (NEW — from Gemini feedback)
Each spec.md includes a `## Smoke Tests` section with concrete, executable checks:

```markdown
## Smoke Tests
Run these AFTER pulling the DEV worker's changes:

1. `curl -s http://localhost:3851/api/health` → expect JSON with `"status":"ok"`
2. `curl -s http://localhost:3851/api/history` → expect JSON with `"success":true`
3. `curl -s -X POST http://localhost:3851/api/history/check-content -H "Content-Type: application/json" -d '{"title":"test","content":"test"}' ` → expect JSON with `"contentHash"`
```

The orchestrator runs these via SSH on the DEV worker's machine and checks the response. This is independent verification — not reading result.md.

### Step 3: Acceptance Criteria Cross-Check
- Compare each criterion in spec.md against result.md
- Check that DEV worker addressed each one (not just claimed "done")

### Step 4: Regression Check
- Re-run smoke tests from ALL previous phases to catch regressions
- If phase 3 breaks phase 1's endpoints → revision

### Verdict
- All smoke tests pass + acceptance criteria met → **COMPLETE**
- Any smoke test fails → **REVISION** (include failure output in revision spec)
- Max revisions exceeded → **REVISION_FAILED** (escalate)

### Revision Decay (cumulative context)
Each revision spec includes ALL prior context so DEV doesn't repeat mistakes:

```markdown
# Phase 02 — Revision 2

## What Failed in Revision 1
- Smoke test: `curl /api/sites/x/categories` returned 404
- Root cause: route not mounted in server.js

## What Failed in Original
- Categories fetched but not cached (acceptance criterion 5)

## Full Spec (unchanged)
[original spec.md content]
```

## Codebase Scan Strategy (Path B)

Medium depth — enough context for good specs without overwhelming:

### Include
1. **File tree** — with .gitignore patterns applied (skip node_modules, dist, etc.)
2. **package.json / requirements.txt** — dependencies, scripts
3. **Entry points** — server.js, main.py, index.html, app entry
4. **Config files** — .env.example, tsconfig, database schemas
5. **CLAUDE.md / README** — existing project documentation
6. **Key exports** — `grep 'export function\|export class\|module.exports'` across src/
7. **Route definitions** — `grep 'router\.\|app\.\(get\|post\|put\|delete\)'`
8. **Database schemas** — SQL files, migration files, model definitions

### Skip
- Full function implementations (too much context)
- Test files (unless testing strategy is relevant)
- Build artifacts, generated files
- node_modules, vendor directories
- Binary files, images

### Output
- `snapshot.md` — ~500 lines max
- Structured sections: Tech Stack, File Structure, Key Components, Database, API Routes, Dependencies
- This file is included in every phase spec as context

## Phase Spec Template

What the orchestrator generates for each phase before queuing to DEV:

```markdown
# Phase XX: <Phase Name>

## Context
[What exists now. Reference snapshot.md for codebase overview.]
[What was built in previous phases. Reference learnings.md.]

## Objective
[What this phase must accomplish — clear, specific, measurable]

## Implementation Steps
[Ordered list of what to build/change]

## Files to Create
[New files with purpose]

## Files to Modify
[Existing files and what changes]

## Do NOT Touch
[Files/systems that must remain unchanged]

## Acceptance Criteria
- [ ] Criterion 1 (testable)
- [ ] Criterion 2 (testable)
- [ ] Criterion 3 (testable)

## Smoke Tests
Run these to verify the phase works:
1. `command` → expected output
2. `command` → expected output

## Completion Instructions
1. Run all smoke tests and confirm they pass
2. Write result to: .planning/phases/XX-<name>/result.md
3. Commit with prefix: [project-prefix-XX]
4. Push to origin
```

## Queue Command Template

How the orchestrator dispatches work:

```bash
./scripts/add-task.sh "PROJECT <NAME> PHASE XX: cd <project-path> && git pull && read .planning/phases/XX-<name>/spec.md and implement the FULL phase. All acceptance criteria must pass. Run all smoke tests. Write result to .planning/phases/XX-<name>/result.md. Commit with prefix [<project>-XX] and push."
```

## Orchestrator Loop (Core Algorithm)

```
function orchestrate(project_path):
    status = read status.json
    learnings = read learnings.md

    if status.blocked:
        STOP → notify user with blocked_reason
        return

    current = get_current_phase(status)

    if current is null:
        ALL PHASES COMPLETE → final review (Level 0 STOP)
        return

    switch current.status:
        case "pending":
            # Progressive detail: write Level-1 spec NOW
            scan current codebase state (git pull first)
            write spec.md with smoke tests, informed by learnings
            append event: phase_specified
            update status → "specified"
            continue loop

        case "specified":
            # Queue to DEV worker
            queue_task(current.spec)
            append event: phase_queued
            update status → "queued"
            WAIT for response

        case "queued":
            # Waiting for DEV — nothing to do
            WAIT for "check response <id>" trigger

        case "response_received":
            # Pull and verify INDEPENDENTLY
            git pull
            result = read result.md
            smoke_results = run_smoke_tests(current.spec)
            regression_results = run_previous_smoke_tests(all_completed_phases)

            all_pass = smoke_results.all_pass AND regression_results.all_pass
            append event: verification_complete

            if all_pass:
                update learnings.md with discoveries from this phase
                update status → "complete"
                append event: phase_complete
                log Level 1 notification

                # Check if checkpoint is due
                phases_since_checkpoint++
                if phases_since_checkpoint >= checkpoint_frequency:
                    CHECKPOINT → pause for optional user review
                    phases_since_checkpoint = 0

                continue loop  # → next phase automatically

            else:
                if current.revisions >= max_revisions(current.complexity):
                    update status → "revision_failed"
                    append event: phase_escalated
                    STOP → escalate to user (Level 0)
                else:
                    write revision spec WITH:
                      - what failed (smoke test output)
                      - all prior revision context (decay)
                      - updated learnings
                    current.revisions++
                    update status → "queued" (re-queue)
                    append event: phase_revision
                    continue loop

        case "blocked":
            STOP → notify user
            return

        case "skipped":
        case "merged":
            # Skip to next phase
            advance to next in execution_order
            continue loop

        case "revision_failed":
            STOP → escalate to user
            return

    # Max revisions by complexity
    function max_revisions(complexity):
        if complexity == "complex": return 5
        return 3
```

## Rollback Strategy

If a phase breaks previous work:

1. **Detection:** Regression smoke tests catch it during verification
2. **First attempt:** Include regression details in revision spec — DEV worker fixes
3. **If revision fails:** Orchestrator can `git revert <phase-commit>` to restore last-known-good state
4. **Escalate:** If revert doesn't cleanly apply, STOP and escalate to user

Rollback is a last resort. The revision cycle should fix most regressions.

## Metrics & Observability

Tracked automatically from events.jsonl:

| Metric | Purpose |
|--------|---------|
| Phases complete / total | Overall progress |
| Total revisions | Quality indicator |
| Avg time per phase | Planning estimate for future projects |
| Smoke tests pass rate | Verification reliability |
| Revisions per phase | Identifies problematic phases |
| Time from queue to response | DEV worker throughput |

Available via: `orchestrator status <project-path>` (reads events.jsonl)

## What This Framework Does NOT Do

- **Does not replace DEV workers** — It orchestrates, not implements
- **Does not handle deployment** — Separate concern (CI/CD, PM2, nginx)
- **Does not manage credentials** — User provides access, orchestrator uses it
- **Does not make product decisions** — User defines what to build, orchestrator decides how
- **Does not do AI consultation** — That's a separate workflow (consult-gemini, consult-openai)
- **Does not run tests** — Unless smoke tests are curl/CLI commands it can execute via SSH
- **Does not optimize images or assets** — Out of scope

## Implementation Strategy

### Phase 1: CLAUDE.md + Templates (start here)
- Write orchestrator instructions as CLAUDE.md in the orchestrator project
- Template files for brief.md, spec.md, status.json, events.jsonl
- Manual invocation: user says "orchestrate <project>" and orchestrator follows CLAUDE.md
- **Dogfood:** Re-run blog-publisher v2 through the framework to validate

### Phase 2: Helper Scripts (if Phase 1 works)
- `scripts/init.sh` — scaffold .planning/ directory
- `scripts/scan.sh` — codebase snapshot generation
- `scripts/verify.sh` — run smoke tests, check acceptance criteria
- `scripts/status.sh` — read events.jsonl, show progress

### Phase 3: CLI Tool (if Phase 2 proves valuable)
- Node.js CLI wrapping the scripts
- `orchestrator init | resume | status | verify`
- Proper argument parsing, error handling
- **Only build this if the workflow is proven**

## Success Criteria for the Orchestrator Itself

- [ ] Can initialize a new project from a brief and run to completion
- [ ] Can retrofit an existing project (scan → plan → execute)
- [ ] Can resume from any interruption point via status.json + events.jsonl
- [ ] Completes a 3+ phase project with minimal user interaction after initial brief
- [ ] Independently verifies results via smoke tests (not just reading result.md)
- [ ] Handles DEV worker failures gracefully (revision with cumulative context)
- [ ] Catches regressions via previous-phase smoke test re-runs
- [ ] Works with both >>hetzner and >>wsl2 as DEV workers
- [ ] All state persists in git (no external databases)
- [ ] Learnings accumulate and improve later phase specs
- [ ] Checkpoints give user visibility without requiring babysitting

## Resolved Questions

| Question | Resolution |
|----------|-----------|
| Parallel phases? | No for v1. Sequential is simpler, parallel adds verification complexity. |
| Codebase scan depth? | Medium — file tree, deps, entry points, exports, routes. ~500-line snapshot. |
| Learnings log? | Yes — `learnings.md` accumulates discoveries, included in future specs. |
| Cross-project deps? | Out of scope for v1. Each orchestrated project is self-contained. |
| CLI vs CLAUDE.md? | Start CLAUDE.md → scripts → CLI. Prove concept before building tool. |
| Rate limiting? | Not for v1. Queue one phase at a time, natural throttle. |
| Dogfood strategy? | Yes — re-run blog-publisher through framework as validation. |
| Revision max? | 3 for standard phases, 5 for complex phases. Configurable per phase. |
| Event log vs status.json? | Both. Events are source of truth, status.json is derived convenience. |
