# Phase test-failed: /api/users smoke endpoint

> Synthetic test fixture for orchestrator/scripts/ai-diagnose.sh.
> Used by P2 Phase A smoke + future B/C iterations as a stable failure input.
> Pre-loaded to simulate a realistic phase: builds a tiny CRUD users API,
> verifies via curl, and (intentionally) ships a missing port binding so
> the smoke test fails.

## Objective

Add a minimal users CRUD API to the existing Express service:

- `GET /api/users` → returns 200 with `{ users: [...] }`
- Server starts on port 4080
- Drop-in addition to `src/server.js`; no new dependencies

## Implementation Steps

1. Add a new file `src/routes/users.js` exporting an Express router.
2. Mount the router at `/api/users` in `src/server.js`.
3. Add `app.listen(4080, ...)` to `src/server.js` if not already present.
4. Ensure the seed data file `data/users.json` is read on startup.

## Expected Files Changed

- src/server.js
- src/routes/users.js (new)
- data/users.json (new)

## Acceptance Criteria

- [ ] `GET /api/users` returns HTTP 200
- [ ] Response body is `{ users: [...] }` with at least one user
- [ ] Server log shows `listening on :4080`

## Smoke Tests

1. `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4080/api/users` → `200`
2. `curl -s http://localhost:4080/api/users | jq '.users | length'` → `>= 1`
