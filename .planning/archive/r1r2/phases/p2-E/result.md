# P2 Phase E — Gemini structured output (JSON conformance hotfix)

**Dispatch:** ORCHESTRATOR P2 PHASE E
**Repos touched:** ai-consult + orchestrator
**Push:** NOT done (per dispatch — wait for explicit push approval)

---

## Commits

| Repo | Hash | Prefix + title |
|------|------|----------------|
| ai-consult   | `b818724` | `[ai-consult-p2-E] Add responseSchema option to gemini + openai providers` |
| orchestrator | `bfefa9e` | `[orchestrator-p2-E] Wire MODEL_RESPONSE_SCHEMA through ai-diagnose.js for API-enforced JSON` |

## What changed

### ai-consult

| File | Change |
|------|--------|
| `providers/gemini.js` | `getReview(prompt, options)` now reads `options.responseSchema`. When present, passes `generationConfig: { responseMimeType: 'application/json', responseSchema }` to `getGenerativeModel`. Constrains the model to produce a JSON object conforming to the schema. |
| `providers/openai.js` | Same option support; wires to `response_format: { type: 'json_schema', json_schema: { name, schema, strict: true } }` so gpt-5.2-pro emits conforming JSON. Reads `options.responseSchemaName` for the json_schema entry name (default `'response'`). |
| `index.js` | `reviewDocument(options)` accepts new top-level shortcuts (`model`, `responseSchema`, `responseSchemaName`) merged into `providerOptions` before calling the provider. Backwards-compatible — existing nested `providerOptions` form still works. |

### orchestrator

| File | Change |
|------|--------|
| `scripts/ai-diagnose.js` | New `MODEL_RESPONSE_SCHEMA` constant — the response-schema for the model-emitted 6 fields (NOT the canonical augmented schema). `toGeminiSchema(node)` walks recursively and strips Gemini-incompatible keywords (`additionalProperties`, `$schema`, `$id`). `diagnoseOnce()` selects the right schema per provider and passes via `responseSchema` option. |

## Smoke + validation (all pass)

### A) Synthetic fixture regression (no .raw.txt)
```
Phase: p2-e-synthetic
Diagnosis #01 saved to: /tmp/p2-e-synthetic/ai-diagnosis-01.json
Confidence: high
Root cause: Missing app.listen(4080) call at the end of src/server.js...
Cost: $0.004956
```
- `ai-diagnosis-01.json` produced ✓
- No `.raw.txt` fallback ✓

### B) B3X real-world validation — the test that PREVIOUSLY FAILED
Input: same 38KB `~/awsc-new/awesome/b3x-account-expert/.planning/phases/06.5-quality-eval/spec.md` + the same `verification-report.json` from `/tmp/p2-validation/real-failure/` that triggered the pre-fix JSON parse error at position 587 (backslash-backtick illegal escape inside string values).

**Result:** **B3X_VALIDATION_PASS** — clean JSON, no `.raw.txt` fallback.

Recovered diagnosis content (this is what would have been written PRE-fix had the JSON parsed):
```json
{
  "diagnosis": "The worker failed due to scope violations and schema errors ('topic_id' instead of 'topic_cluster_id') when attempting to generate the test set. This occurred because the spec mandates complex generation logic but omits a designated generation script in 'Files to Create', leading the worker to hijack and modify the out-of-scope Phase 04 'scripts/eval-harness.js'.",
  "root_cause": "The spec lacks a designated generation script in the 'Files to Create' and directory layout lists, forcing the worker to improvise by modifying existing out-of-scope scripts to run the phase logic.",
  "confidence": "high",
  "escalate_now": false,
  "suggested_revisions": [
    {
      "section": "### 6.5A.1 — Directory + initial files",
      "change": "Insert `scripts/generate-candidates.js (NEW — script to execute generation logic)` on a new line before `tools/apply-md-edits.js`."
    },
    {
      "section": "## Files to Create",
      "change": "Insert `- scripts/generate-candidates.js (one-off script to execute candidate generation)` on a new line before `- lib/eval-runner.js (exports-only library)`."
    },
    {
      "section": "## Do NOT Touch",
      "change": "Replace `- All Phase 01–05 modules.` with `- All Phase 01–05 modules (explicitly DO NOT modify scripts/eval-harness.js or lib/extraction.js).`"
    }
  ]
}
```
**This is exactly the architectural insight (planted+spec-omission diagnosis) and surgical revisions the prior dispatch debrief praised — but now mechanically usable because the JSON parses every time.**

Cost on the b3x run: **$0.030230** (large 39820-char context bundle).

### C) Integration test (mocked, $0)
```
Results: 9/9 scenarios passed (40 assertions passed, 0 failed)
```

## Schema compatibility notes

**The two providers accept different schema shapes:**

- **Gemini** — OpenAPI 3.0 subset. Rejects `additionalProperties`, `$schema`, `$id`, `allOf`, `oneOf`, `anyOf`, `if/then/else`, `$ref`. Returns HTTP 400 with "Unknown name 'additionalProperties' at 'generation_config.response_schema'" if you send draft-07 features. First attempt of P2-E hit exactly this 400; fix was the `toGeminiSchema()` walker that strips the keyword.
- **OpenAI strict mode** — JSON Schema draft 2020-12 with restrictions. REQUIRES `additionalProperties: false` at every object level. Required must enumerate ALL properties (no conditional required). Rejects `allOf`/conditional logic.

**Solution adopted:** define a single canonical `MODEL_RESPONSE_SCHEMA` (OpenAI-strict shape with `additionalProperties: false` and every field in `required`). Transform via `toGeminiSchema()` for the Gemini wire. No separate `templates/ai-diagnosis-schema-gemini.json` file needed — the transform is small + lives next to the canonical const.

**Canonical templates/ai-diagnosis-schema.json untouched** — it stays draft-07 for the ajv defense-in-depth validation pass that runs AFTER the model returns. ajv still validates the FULL augmented row (model fields + provider/timestamp/cost) including the `escalate_now → escalation_reason` conditional that neither provider's structured-output mode can enforce.

**escalation_reason:** schema requires it unconditionally (empty string acceptable). The conditional "must be non-empty iff escalate_now=true" rule is enforced at the ajv layer + by the system prompt's operational rule.

**Prompt change:** none. The diagnosis system prompt's "STRICT JSON output (no prose, no markdown fence)" instruction stays as belt-and-suspenders. Cost of keeping it: ~50 input tokens per call (~$0.0001) — negligible vs the safety margin.

## Acceptance criteria

- [x] ai-consult/providers/gemini.js accepts `options.responseSchema`, wires to `generationConfig.responseSchema` + `responseMimeType: 'application/json'`
- [x] ai-consult/providers/openai.js accepts `options.responseSchema`, wires to `response_format` json_schema strict mode
- [x] ai-consult/index.js forwards `responseSchema` (and `model`, `responseSchemaName`) through `providerOptions`
- [x] orchestrator/scripts/ai-diagnose.js passes the schema to BOTH primary and secondary calls
- [x] Schema compatibility: works with both providers (`toGeminiSchema` strips draft-07-only keywords)
- [x] B3X validation rerun produces valid `ai-diagnosis-01.json` (was failing pre-fix)
- [x] Synthetic fixture regression: still produces valid diagnosis
- [x] Integration test: 9/9 still pass
- [x] Combined result.md with commits + b3x diagnosis content + schema-compat notes
- [x] Commits with `[ai-consult-p2-E]` and `[orchestrator-p2-E]` prefixes
- [x] No push

## Out of scope (per dispatch, NOT touched)
- Diagnosis prompt content (system prompt unchanged — only the JSON enforcement mechanism changed)
- `scripts/verify.sh`, `scripts/notify.sh`, `scripts/ai-stats.sh` (no change needed; structured output is internal to ai-diagnose)
- `templates/ai-diagnosis-schema.json` (canonical draft-07 schema unchanged; ajv pass still validates augmented row)

## Operational notes

- **The bug was insidious.** Pre-fix, on most specs the model emitted clean JSON and ai-diagnose worked. The b3x spec was the first to trigger illegal `\`` escape inside string values, exposing the brittleness. Structured output makes this class of failure impossible.
- **Cost impact: ~$0.** Gemini doesn't charge extra for `responseSchema`. OpenAI strict mode doesn't either.
- **Latency impact: imperceptible.** Both providers process the schema constraint during generation; no extra round trips.
- **The `toGeminiSchema` walker is the only piece that may need extension** when new draft-07 keywords appear in future schemas. Keep it tight: drop only what Gemini doesn't recognize, never silently mutate types or required lists.
- **Defense in depth retained:** ajv still validates the augmented JSON after the model returns. If a future provider regression returns something the structured-output guarantee should have prevented, ajv catches it. Two-tier safety.
