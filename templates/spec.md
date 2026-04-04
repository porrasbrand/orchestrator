# Phase XX: <Phase Name>

## Context
[What exists now. Reference snapshot.md for codebase overview.]
[What was built in previous phases. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase. This section ensures
DEV workers have clean context without needing to read all prior specs.]

## Objective
[What this phase must accomplish — clear, specific, measurable]

## Implementation Steps
1. [Step 1]
2. [Step 2]
3. [Step 3]

## Files to Create
- `path/to/new-file.js` — [purpose]

## Files to Modify
- `path/to/existing-file.js` — [what changes]

## Do NOT Touch
- [Files/systems that must remain unchanged]

## Expected Files Changed
Files this phase should create or modify. Verification will warn if other files are touched.
- `path/to/file.js` (create | modify) — [purpose]

## Acceptance Criteria
- [ ] Criterion 1 (testable)
- [ ] Criterion 2 (testable)
- [ ] Criterion 3 (testable)

## Smoke Tests
Run these AFTER implementation to verify the phase works:

```bash
# Test 1: [description]
[command] → expect [expected output]

# Test 2: [description]
[command] → expect [expected output]
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `.planning/phases/XX-<name>/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Push to origin
