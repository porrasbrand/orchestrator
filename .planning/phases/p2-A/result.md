# P2 Phase A — ai-diagnose.sh + diagnosis prompt (RESULT)

**Dispatch:** ORCHESTRATOR P2 PHASE A
**Repos touched:** ai-consult + orchestrator
**Push:** NOT done (per dispatch — wait for explicit push approval)

---

## Commits

| Repo | Hash | Prefix + title |
|------|------|----------------|
| ai-consult | `788af7b` | `[ai-consult-p2-A] Add diagnosis reviewType for orchestrator failure recovery` |
| orchestrator | (this commit) | `[orchestrator-p2-A] Add ai-diagnose.sh + schema + fixture` |

## Files changed

### ai-consult
- `prompts/documentReview.js` — new `diagnosis` reviewType (system + user). Strict-JSON contract with 6 required keys + operational rules (surgical revisions, escalate-when-fundamentally-wrong, confidence calibration, evidence-insufficient fallback). Existing handoff/codeReview/general types untouched.

### orchestrator
- `scripts/ai-diagnose.js` (new) — Node helper: bundles spec.md + verification-report.json + revisions + learnings + last-50 events + scoped git diff into a structured markdown context; calls ai-consult with `provider:'gemini', reviewType:'diagnosis'`; parses + validates `r.feedback` JSON against templates/ai-diagnosis-schema.json (ajv if available, else manual key check); augments with provider/model/timestamp/cost; writes `ai-diagnosis-NN.json` to phase-dir; appends `ai_diagnostic_run` event to `.planning/events.jsonl`.
- `scripts/ai-diagnose.sh` (new) — thin bash wrapper around the Node helper. Default `AI_CONSULT_PATH=~/awsc-new/awesome/ai-consult`. Exit codes: 0/1/2.
- `templates/ai-diagnosis-schema.json` (new) — draft-07 JSON Schema for ai-diagnosis-NN.json (9 top-level required fields + conditional escalation_reason when escalate_now=true).
- `templates/test-fixtures/failed-phase/spec.md` (new) — synthetic small spec ("/api/users smoke endpoint").
- `templates/test-fixtures/failed-phase/verification-report.json` (new) — synthesized verification report with 2 smoke-test failures (port 4080 connection refused) — realistic failure mode (missing `app.listen`).

## Smoke test (executed, captured at `/tmp/p2-a-smoke.log`)

```
[ai-diagnose] context bundled: 2681 chars
Phase: failed-phase
Diagnosis #01 saved to: /tmp/p2-a-smoke/failed-phase/ai-diagnosis-01.json
Confidence: high
Escalate: no
Root cause: Missing app.listen(4080) call at the end of src/server.js, causing the Express application to exit without starting the HTTP server.
Cost: $0.005862
---
SMOKE_PASS
SCHEMA_PASS
```

Both assertion gates pass:
- `test -f /tmp/p2-a-smoke/failed-phase/ai-diagnosis-01.json` → SMOKE_PASS
- `jq -e ".diagnosis and .root_cause and .confidence and (.escalate_now == true or .escalate_now == false)"` → SCHEMA_PASS

## Schema validation result

`scripts/ai-diagnose.js` uses ajv (loaded from `ai-consult/node_modules/ajv`) to validate the augmented JSON against `templates/ai-diagnosis-schema.json`. The smoke-run output passed (no validation errors).

## Sample ai-diagnosis-01.json (truncated to key fields)

```json
{
  "diagnosis": "The Express server fails to accept connections because it does not bind to port 4080, leading to 'Failed to connect' errors during smoke tests. The logs explicitly show the process starting up and mounting routes, but exiting before any app.listen call.",
  "root_cause": "Missing app.listen(4080) call at the end of src/server.js, causing the Express application to exit without starting the HTTP server.",
  "suggested_revisions": [
    {
      "section": "## Implementation Steps",
      "change": "Replace '3. Add `app.listen(4080, ...)` to `src/server.js` if not already present.' with '3. Explicitly add `app.listen(4080, () => console.log(\"listening on :4080\"));` at the bottom of `src/server.js`.'"
    }
  ],
  "confidence": "high",
  "escalate_now": false,
  "provider": "gemini",
  "model": "gemini-3.1-pro-preview",
  "timestamp": "2026-05-19T10:47:31.693Z",
  "cost": { "inputTokens": 1551, "outputTokens": 230, "totalCost": 0.005862, "currency": "USD" }
}
```

The model's diagnosis is **surgical, mechanical, and high-confidence** — exactly the quality bar the dispatch identified as the early signal for P2 success. It pinpointed the missing `app.listen` call from the verification-report's "(no app.listen output before process exited)" log line and proposed the exact replacement text for spec step 3.

## Event appended to test events.jsonl

```
{"ts":"2026-05-19T10:47:31.695Z","event":"ai_diagnostic_run","data":{"phase":"failed-phase","diagnosis_num":1,"confidence":"high","escalate_now":false,"cost":0.005862}}
```

## Acceptance criteria

- [x] ai-consult: prompts/documentReview.js has new `diagnosis` entry, additive only.
- [x] ai-consult: smoke command produces strict JSON with all 6 required keys.
- [x] ai-consult: committed with `[ai-consult-p2-A]` prefix (`788af7b`).
- [x] orchestrator: scripts/ai-diagnose.sh exists, executable, runs end-to-end against the test fixture.
- [x] orchestrator: templates/ai-diagnosis-schema.json validates the test output.
- [x] orchestrator: test-fixtures/failed-phase/ scaffolded with realistic content (missing port-binding failure).
- [x] orchestrator: smoke test produces ai-diagnosis-01.json that validates against schema.
- [x] orchestrator: ai_diagnostic_run event appended to test events.jsonl.
- [x] orchestrator: committed with `[orchestrator-p2-A]` prefix.
- [x] Combined result.md written (this file).

## Operational notes for Phase B (verify.sh integration) and beyond

- **API surface stable:** `r.feedback` (not `r.content`) — Phase B should call ai-diagnose.sh via subprocess and read the produced `ai-diagnosis-NN.json`, not re-invoke ai-consult directly.
- **NN file naming:** scripts/ai-diagnose.js counts existing `ai-diagnosis-*.json` files in phase-dir and zero-pads NN=count+1 — supports multiple revision cycles per phase naturally.
- **Schema is normative:** any future Phase that emits diagnosis files must validate against `templates/ai-diagnosis-schema.json`. Add ajv-cli to the orchestrator's runtime deps later if we want belt-and-suspenders schema enforcement outside the Node helper.
- **Exit codes drive retry behavior:** Phase B should distinguish exit 1 (missing required file / ai-consult call failed — likely transient, retry) from exit 2 (schema validation failed — model misbehaved, escalate or use fallback).
- **Cost budget:** $0.005-0.010 per diagnostic on small specs; Phase D may want a per-phase budget cap.
- **No-git-repo silent warnings:** ai-diagnose.js calls `git diff` in the project root; if absent (fixture case), git stderr prints "not a git repository" warnings but the script continues — silent in production usage. Out-of-scope for Phase A polish.

## Out of scope (per dispatch, NOT touched)
- scripts/verify.sh, templates/revision.md, CLAUDE.md, scripts/notify.sh — all Phase B/D territory.
- Push approval: both repos committed locally only; awaiting explicit push approval.
- OpenAI fallback — Phase D handles second-opinion.
