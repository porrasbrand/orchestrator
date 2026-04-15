# Phase XX: {{PHASE_NAME}}
# Template: config-change
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, CONFIG_PATH, CONFIG_PURPOSE, SCHEMA_DESCRIPTION

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Create or modify the configuration file `{{CONFIG_PATH}}` for {{CONFIG_PURPOSE}}.

## Implementation Steps
1. **Create or modify `{{CONFIG_PATH}}`** with the following schema:
   {{SCHEMA_DESCRIPTION}}
2. **Validate JSON with jq:** `jq . {{CONFIG_PATH}}` — must parse without errors
3. **Identify consuming scripts** — Find all scripts that read from or should read from `{{CONFIG_PATH}}`
4. **Update consuming scripts** — Ensure they correctly read the new/modified config
5. **Test the full chain** — Config file + consuming scripts work end-to-end
6. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
- `{{CONFIG_PATH}}` — {{CONFIG_PURPOSE}} (if new)

## Files to Modify
- `{{CONFIG_PATH}}` — {{CONFIG_PURPOSE}} (if existing)
- `ENHANCEMENT-ROADMAP.md` — Mark this phase as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Scripts not consuming this config
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- `{{CONFIG_PATH}}` (create | modify) — Configuration file
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] `{{CONFIG_PATH}}` exists and is valid JSON
- [ ] Config matches schema: {{SCHEMA_DESCRIPTION}}
- [ ] `jq . {{CONFIG_PATH}}` parses without errors
- [ ] All required keys are present
- [ ] Consuming scripts correctly read and use the config
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: Config file exists
test -f ~/awsc-new/awesome/orchestrator/{{CONFIG_PATH}} && echo EXISTS
# expect: EXISTS

# Test 2: Valid JSON
jq . ~/awsc-new/awesome/orchestrator/{{CONFIG_PATH}} > /dev/null 2>&1 && echo VALID_JSON
# expect: VALID_JSON

# Test 3: Required keys present
jq 'keys' ~/awsc-new/awesome/orchestrator/{{CONFIG_PATH}}
# expect: list containing all required top-level keys

# Test 4: Consuming scripts still work
# [Fill in test for scripts that read {{CONFIG_PATH}}]
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
