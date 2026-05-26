# AI Feedback Loop — Consult Between Cycles

## What It Is

A pattern where external AI models (Gemini, OpenAI) review completed work and provide creative/technical feedback **between** orchestrated batches or phases. Their feedback adjusts the next batch spec before dispatch — preventing blind execution of a pre-made plan.

## When To Use

- **Iterative creative work** — video production, UI/UX design, content generation
- **Multi-cycle improvement loops** — "run N improvement cycles" where each cycle builds on the last
- **Ambiguous quality targets** — you don't have a binary pass/fail, you need taste/judgment
- **When the user says** "consult between cycles", "get feedback between batches", or "use AI review"

Do NOT use for:
- Standard phase-based projects with clear specs and smoke tests
- Bug fixes or deterministic implementation work
- Projects where verification is binary (tests pass or fail)

## The Pipeline

```
┌─────────────────────────────────────────────────────┐
│                   BATCH N                           │
│                                                     │
│  1. Dispatch batch to worker                        │
│     └── Worker implements cycles, commits, renders  │
│                                                     │
│  2. Response arrives → verify results               │
│     └── SSH check: files exist, renders complete    │
│                                                     │
│  3. Consult AI on results + next batch plan         │  ← KEY STEP
│     └── Write context file with:                    │
│         - What was built so far (current state)     │
│         - What's planned next (remaining batches)   │
│         - Specific questions (what to cut/add)      │
│     └── SCP to worker, queue consult-gemini         │
│                                                     │
│  4. AI feedback arrives → adjust next batch spec    │
│     └── Cut cycles AI says are noise                │
│     └── Add suggestions AI recommends               │
│     └── Reorder priorities based on impact           │
│                                                     │
│  5. Dispatch adjusted Batch N+1                     │
│     └── Spec includes: "Based on Gemini feedback:   │
│         [specific adjustments]"                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## How To Execute

### Step 1: Dispatch Batch + Consultation in Parallel

When a batch goes to the worker, simultaneously send a consultation request:

```bash
# Dispatch the implementation batch
./scripts/add-task.sh "PROJECT <name> BATCH N: <implementation details>"

# Write context for AI review
cat > /tmp/<project>-review.md << 'EOF'
# <Project Name> — Batch N Review

## Current State
[What has been built so far — features, architecture, component list]

## Batch N In Progress
[What this batch is implementing]

## Remaining Plan
[What batches N+1 through N+K will do]

## Questions
1. Are we over-engineering? Which planned cycles should we CUT?
2. What are we MISSING that would have more impact?
3. [Domain-specific questions — pacing, aesthetics, UX, etc.]
EOF

# Transfer and consult
scp -i ~/.ssh/id_remote_claude -P 22 /tmp/<project>-review.md ubuntu@remote.manuelporras.com:~/super-agent-shared/
./scripts/add-task.sh "consult-gemini on ~/super-agent-shared/<project>-review.md — [specific ask]"
```

### Step 2: Merge Feedback Into Next Batch

When both responses arrive:

1. Read the implementation response — verify renders/builds succeeded
2. Read the Gemini response — extract actionable recommendations
3. Adjust the next batch spec:
   - **CUT** cycles Gemini flagged as noise or counterproductive
   - **ADD** suggestions Gemini recommended (replace cut cycles to maintain batch size)
   - **REORDER** remaining cycles by impact (Gemini's priority ranking)
4. Include in the next batch spec: `"Gemini feedback applied: [summary of changes]"`

### Step 3: Alternate AI Providers

For balanced feedback, alternate between providers across batches:

| Batch | Implementation | Consultation |
|-------|---------------|--------------|
| 1     | >>hetzner     | consult-gemini |
| 2     | >>hetzner     | consult-openai |
| 3     | >>hetzner     | consult-gemini |
| 4     | >>hetzner     | consult-openai |

Different models catch different things. Gemini tends to be stronger on creative direction; OpenAI tends to be stronger on technical precision.

## Context File Template

```markdown
# <Project> — Batch N Review

## Project Summary
[1-2 sentences: what this project is and its target audience]

## Current State (after N-1 batches)
[List of features/improvements already implemented]

## Batch N (in progress)
[What this batch is adding — numbered cycle list]

## Remaining Plan (Batches N+1 through end)
[Full list of remaining planned cycles]

## Specific Questions
1. Which planned cycles should we CUT? (visual noise, diminishing returns)
2. What are we MISSING? (techniques competitors use that we don't)
3. [Domain-specific: pacing, aesthetics, UX, sound design, etc.]
4. Priority ranking: if we can only do 3 more cycles, which 3?

## Constraints
- [Technical: framework, render time, file size limits]
- [Creative: target audience, platform requirements, brand guidelines]
```

## Rules

1. **Never skip the consultation.** The whole point is external perspective. Dispatching batch after batch without review is just blind execution.
2. **Ask specific questions.** "Is this good?" gets generic answers. "Should we cut the matrix code rain transition — is it dated?" gets actionable answers.
3. **Include what to CUT, not just what to ADD.** Scope creep kills iterative projects. Every consultation should ask "what should we remove?"
4. **Don't blindly follow AI feedback.** The PM (you) makes the final call. AI consultation is input, not instruction. If Gemini says to cut something the user specifically asked for, keep it.
5. **Log the feedback.** Append a summary of AI feedback + decisions to `events.jsonl` or learnings so context survives resets.
6. **Cap total cycles.** Even with AI feedback, set a maximum. Diminishing returns are real. Default cap: user-specified count. If user says "25 cycles", do 25 — not 30 because Gemini suggested more.
