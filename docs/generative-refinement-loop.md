# Generative Refinement Loop — 3-Tier Architecture

## What It Is
An autonomous improvement loop where Level 1 (wsl2 Planner) iteratively improves a project by dispatching implementation tasks to Level 2 (hetzner), evaluating results, and repeating until quality criteria are met. Analogous to evolutionary optimization — build → evaluate fitness → mutate → repeat.

## When to Use

| Signal | Use This |
|--------|----------|
| "Run N improvement cycles" | Yes |
| "Iterate until quality X" | Yes |
| Quality is subjective (visual, creative) | Yes |
| Expected to exceed 1 context window | Yes |
| User wants to step away and check later | Yes |
| Single bug fix | No — use 2-tier `>>hetzner` |
| Multi-phase project with clear specs | No — use orchestrator |

## How to Dispatch

From lipo-360:
```bash
./scripts/add-task-local.sh "GENERATIVE REFINEMENT LOOP — [objective]. Target: [criteria]. Evaluation: [command]."
```

Or tell the PM: `>>wsl2 GENERATIVE REFINEMENT LOOP — [description]`

The trigger phrase "GENERATIVE REFINEMENT LOOP" activates Role A (Planner) in wsl2's CLAUDE.md.

## What the Planner Does (Autonomously)

```
1. SSH into hetzner, read project CLAUDE.md + source files
2. Run evaluation (script, tests, visual analysis)
3. Score against acceptance criteria
4. If score >= target → report to Level 0, STOP
5. Identify weakest dimension
6. Write spec fixing ONE thing (< 2000 chars)
7. Dispatch to hetzner via add-task.sh
8. Wait for response (SSH poll hetzner queue)
9. Verify results, log generation
10. Go to step 2
```

## Requirements

### The project MUST have:
1. **An evaluation method** — a script, test suite, or measurable metric that produces a score
2. **Clear acceptance criteria** — numeric threshold (e.g., >= 8.0, >= 90%, all tests pass)
3. **Codebase on hetzner** — the Planner reads via SSH, executor implements locally

### The evaluation method can be:
- **Automated script**: `node scripts/evaluate.mjs` → JSON score (best — loop runs fastest)
- **Test suite**: `npm test` → pass/fail count (good — clear signal)
- **LLM-as-judge**: send screenshots to AI for scoring (slower but handles subjective quality)
- **External tool**: Lighthouse, PageSpeed, etc. (good for performance)

## Convergence Detection

The Planner tracks the last 5 generation scores:

| Pattern | Action |
|---------|--------|
| Oscillating (±0.5 for 5 gens) | PAUSE — fix ONE dimension, freeze rest |
| Plateau (same ±0.3 for 5+ gens) | DISRUPTIVE — try radically different approach |
| Regression (>1.0 drop from peak) | REVERT to best-ever generation |
| Steady improvement | CONTINUE |

Always tracks best-ever generation separately.

## State Management

The Planner stores state in the project's `.planning/` directory:
```
.planning/
├── generations.jsonl     — {gen, score, changes, result} per generation
├── current-score.json    — latest evaluation
├── criteria.json         — acceptance thresholds
├── tried.jsonl           — {approach, gen, result, keep} — structured learnings
├── rules.md              — evolving style guide ("always do X, never do Y")
├── anti-patterns.md      — "don't try X — failed in gen N"
└── screenshots/gen-NNN/  — visual snapshots per generation (if applicable)
```

## Communication

- **Slack**: Planner posts every 3 generations + on milestone scores + on convergence/stuck
- **Webhook**: Slack incoming webhook, configured per-environment (stored in the Planner env / secrets, never committed)
- **Level 0 review**: Planner pauses for user review on threshold crossings (7.0, 8.0, 9.0) and when stuck

## Session Continuation

When the Planner's context fills (~20 generations):
1. Writes `.planning/session-handoff.md` with current state
2. Session ends
3. New session reads `.planning/` → resumes seamlessly
4. The loop is theoretically infinite

## Known Limitations (as of 2026-04-19)

1. **Response fetching gap**: lipo-360's response-fetcher grabs responses before wsl2 sees them. Current workaround: Level 0 nudges Planner with results. Permanent fix: Planner SSH-polls hetzner queue directly.
2. **Old queue tasks**: wsl2 queue may have stale tasks from previous sessions. Clear before dispatching new loops.
3. **wsl2 Node module**: better-sqlite3 may need `npm rebuild` after Node version changes.

## Example: One Prompt Video Project (First Real Test)

- **Dispatched**: "All 5 projects scoring >= 8.0 on evaluate.mjs"
- **Baseline**: scores ranged 5.0 to 9.5
- **Generations**: 5 total
  - Gen 1: URL Shortener 8→9 (added Recent Links card)
  - Gen 2: Pomodoro 8→8 (gradient overshoot)
  - Gen 3: Pomodoro 8→9 (gradient retune — self-corrected)
  - Gen 4: Weather 9→10 (center gradient lightened — PERFECT)
  - Gen 5: Divorce 8→9 (reused Gen 4 pattern)
- **Result**: ALL 5 projects >= 9.0 in 5 generations
- **Planner learned**: recognized a pattern (Gen 4 fix) and reused it (Gen 5)
