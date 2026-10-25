# Result JSON Schema

Structured completion report for machine-readable verification. DEV workers write `result.json` alongside `result.md`.

## Schema

{"status":"complete","phase":"01","commit":"abc","files_modified":[],"files_created":[],"tests_run":[],"blockers":[],"summary":"x"}










Formatted example:
```json
{
  "status": "complete",
  "phase": "01-structured-results",
  "commit": "abc1234",
  "files_modified": ["scripts/verify.sh", "templates/result.md"],
  "files_created": ["templates/result-schema.md"],
  "tests_run": [
    {"name": "result.json exists", "passed": true},
    {"name": "schema validates", "passed": true}
  ],
  "blockers": [],
  "summary": "Added result.json schema and updated verify.sh to read it"
}
```

## Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | enum | Yes | "complete", "partial", or "blocked" |
| `phase` | string | Yes | Phase identifier (e.g., "01-structured-results") |
| `commit` | string | Yes | Git commit hash (short or full) |
| `files_modified` | string[] | Yes | List of modified file paths |
| `files_created` | string[] | Yes | List of newly created file paths |
| `tests_run` | object[] | Yes | Array of {name, passed} test results |
| `blockers` | string[] | Yes | List of blocking issues (empty if none) |
| `summary` | string | Yes | One-line description of what was done |

## Status Values

- `complete` — All acceptance criteria met, all tests passing
- `partial` — Some work done but not all criteria met (explain in summary)
- `blocked` — Cannot proceed due to external dependency (list in blockers)

## Test Results Format

Each test in `tests_run` array:
```json
{"name": "descriptive test name", "passed": true}
```

## Example: Complete Phase

```json
{
  "status": "complete",
  "phase": "03-auth-setup",
  "commit": "e5f6a7b",
  "files_modified": ["src/auth.ts", "src/middleware.ts"],
  "files_created": ["src/guards/auth.guard.ts"],
  "tests_run": [
    {"name": "auth middleware loads", "passed": true},
    {"name": "token validation works", "passed": true},
    {"name": "guard blocks unauthorized", "passed": true}
  ],
  "blockers": [],
  "summary": "Implemented JWT auth with middleware and route guards"
}
```

## Example: Blocked Phase

```json
{
  "status": "blocked",
  "phase": "04-payment-integration",
  "commit": "f8g9h0i",
  "files_modified": [],
  "files_created": ["src/payments/stripe.ts"],
  "tests_run": [
    {"name": "stripe client initializes", "passed": false}
  ],
  "blockers": [
    "STRIPE_SECRET_KEY not set in environment",
    "Need production API credentials"
  ],
  "summary": "Stripe client scaffolded but blocked on missing credentials"
}
```

## Usage by verify.sh

The orchestrator's verify.sh reads result.json when present:
1. Checks status field (complete/partial/blocked)
2. Reports files_modified + files_created counts
3. Calculates tests_run pass rate
4. If status is "blocked", reports blockers

This enables programmatic verification decisions without parsing markdown.
