# Phase XX: {{PHASE_NAME}}
# Template: new-bash-script
# REQUIRED_VARS: PHASE_NAME, PHASE_DIR, SCRIPT_NAME, PURPOSE, ARGS_DESCRIPTION, VALID_ARGS, EXPECTED_OUTPUT

## Context
You are working on the **orchestrator** project at `~/awsc-new/awesome/orchestrator/` on hetzner.
[Reference snapshot.md for codebase overview. Reference learnings.md for discoveries.]

## Prior Work Summary
[Concise summary of what prior phases built — max 500 words. Include: key files created,
architecture decisions made, any learnings that affect this phase.]

## Objective
Create a new bash script `{{SCRIPT_NAME}}` that {{PURPOSE}}.

## Implementation Steps
1. **Create `{{SCRIPT_NAME}}`** with proper structure:
   - Shebang line: `#!/bin/bash`
   - `set -e` for fail-fast behavior
   - Argument parsing for: {{ARGS_DESCRIPTION}}
   - Usage/help output on `--help` or `-h`
   - Valid arguments: {{VALID_ARGS}}
   - All informational output to stderr, machine-readable output to stdout
   - Exit code 0 on success, 1 on error, 2 on usage error
2. **Make script executable:** `chmod +x {{SCRIPT_NAME}}`
3. **Test with valid inputs** — verify {{EXPECTED_OUTPUT}}
4. **Test with invalid inputs** — verify usage message and exit code 1
5. **Update `ENHANCEMENT-ROADMAP.md`** — Mark this phase as done

## Files to Create
- `{{SCRIPT_NAME}}` — {{PURPOSE}} (make executable: chmod +x)

## Files to Modify
- `ENHANCEMENT-ROADMAP.md` — Mark this phase as done

## Do NOT Touch
- `CLAUDE.md`, `PLAN.md`
- Other scripts not referenced in this spec
- `templates/`

## Cleanup
No cleanup needed.

## Expected Files Changed
- `{{SCRIPT_NAME}}` (create) — New bash script
- `ENHANCEMENT-ROADMAP.md` (modify) — Mark phase done
- `{{PHASE_DIR}}/result.md` (create) — Phase result
- `{{PHASE_DIR}}/result.json` (create) — Structured result

## Acceptance Criteria
- [ ] `{{SCRIPT_NAME}}` exists and is executable
- [ ] Script has shebang `#!/bin/bash` and `set -e`
- [ ] `--help` flag prints usage to stderr and exits 0
- [ ] Valid arguments produce expected output: {{EXPECTED_OUTPUT}}
- [ ] Invalid arguments print usage and exit with code 1 or 2
- [ ] Informational messages go to stderr, data output goes to stdout
- [ ] ENHANCEMENT-ROADMAP.md shows this phase as done

## Smoke Tests
Run these AFTER implementation:

```bash
# Test 1: File exists and is executable
test -x ~/awsc-new/awesome/orchestrator/{{SCRIPT_NAME}} && echo EXECUTABLE
# expect: EXECUTABLE

# Test 2: --help prints usage and exits 0
bash ~/awsc-new/awesome/orchestrator/{{SCRIPT_NAME}} --help 2>&1; echo "EXIT:$?"
# expect: EXIT:0 (and usage text in output)

# Test 3: Valid input produces expected output
bash ~/awsc-new/awesome/orchestrator/{{SCRIPT_NAME}} {{VALID_ARGS}}; echo "EXIT:$?"
# expect: EXIT:0 and {{EXPECTED_OUTPUT}}

# Test 4: Invalid input exits with error
bash ~/awsc-new/awesome/orchestrator/{{SCRIPT_NAME}} --nonexistent-flag 2>&1; echo "EXIT:$?"
# expect: EXIT:1 or EXIT:2
```

## Completion Instructions
1. Run all smoke tests above and confirm they pass
2. Write `result.json` alongside `result.md` (see `templates/result-schema.md` for schema)
3. Write result to: `{{PHASE_DIR}}/result.md`
4. Commit all changes with prefix: `[<project>-XX]`
5. Do NOT push
