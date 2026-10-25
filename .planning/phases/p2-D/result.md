# P2 Phase D — Smart escalation + second-opinion (RESULT, P2 FINAL)

**Dispatch:** ORCHESTRATOR P2 PHASE D
**Repos touched:** orchestrator only (ai-consult prompt was already provider-agnostic, no edit needed)
**Push:** NOT done (per dispatch — wait for explicit push approval)

---

## Three capabilities shipped

### 1. Escalation routing
- `ai-diagnose.js` now detects `escalate_now=true AND confidence=high` after writing the diagnosis JSON. On match, it (a) appends an `ai_escalation_recommended` event to `.planning/events.jsonl`, (b) invokes `scripts/notify.sh ai_escalation_recommended <project> --phase <name> --detail "<reason · confidence · diagnosis-path · model · cost>"`, (c) prints the highly-visible `🚨 ESCALATION RECOMMENDED — see <path>` line. Exit code remains 0 (the diagnostic itself succeeded; escalation is a downstream signal).
- `scripts/notify.sh` — registered the new `ai_escalation_recommended` event type with subject `🚨 [<project>] AI escalation recommended: <phase>`. Standard flow: writes to `notifications.md` + `latest-notification.json` + invokes the optional `config/notify-hook.sh`.
- `CLAUDE.md` — new **NEVER** rule under the autonomy section: PM MUST NOT write a revision spec while an unresolved `ai_escalation_recommended` event exists for the phase. Surface to user, wait for direction. Auto-revise only after user explicitly resolves/overrides.

### 2. Second-opinion fallback
- `ai-diagnose.js` — when primary Gemini returns `confidence=low`, auto-runs `ai-consult` with `provider=openai, model=gpt-5.2-pro` on the same context. Confidence comparison ranks `high(2) > medium(1) > low(0)`:
  - **Secondary > Primary:** swap — secondary becomes the canonical `ai-diagnosis-NN.json`, rejected primary saved as `ai-diagnosis-NN-secondary.json`. The new primary is tagged with `second_opinion_used: true`, `primary_provider: "gemini"`, `primary_confidence: "low"`.
  - **Both low:** save both files, force `escalate_now=true` with reason "both providers low-confidence" (appended to any existing reason), trigger the escalation flow above.
  - **Secondary ≤ Primary (but not both low):** keep primary, save secondary anyway, tag with `second_opinion_used: true`.
- New event `ai_second_opinion_consulted` with `{phase, diagnosis_num, primary_provider, primary_confidence, secondary_provider, secondary_confidence, cost: secondary-only, both_low}`. **By design `cost` here is the secondary-only cost** — keeps `ai-stats.sh` summation trivial.
- `AI_DIAGNOSE_MOCK` extended: accepts either the original `{feedback, usage, cost}` single shape OR the new `{primary: {...}, secondary: {...}}` pair shape. Tests cover both paths.
- `ai-consult` `prompts/documentReview.js` — verified the existing `diagnosis` reviewType works for both Gemini AND OpenAI without changes (strict-JSON system prompt + verbatim user content is provider-agnostic). **No ai-consult commit needed this phase.**
- `templates/ai-diagnosis-schema.json` — added optional fields `second_opinion_used` (boolean), `primary_provider`, `primary_confidence`. Conditional rule: when `second_opinion_used=true`, both `primary_provider` and `primary_confidence` are required (added via `allOf` so the existing `escalate_now → escalation_reason` conditional still fires).

### 3. A/B benchmark mode
- `ai-diagnose.sh` — accepts `--variant=base` (default) or `--variant=customtools`. Maps to `AI_DIAGNOSE_MODEL` env var (`gemini-3.1-pro-preview` or `gemini-3.1-pro-preview-customtools`) which `ai-diagnose.js` honors as the primary model override.
- `ai_diagnostic_run` event now includes the `model` field so downstream analysis can correlate variant vs. quality.

### ai-stats new metrics
- `second_opinions_consulted` — count of `ai_second_opinion_consulted` events
- `second_opinion_rate` — `second_opinions_consulted / diagnostics_run * 100`
- `both_low_escalations` — count where the event has `data.both_low === true`
- `cost.total` — now sums primary (`ai_diagnostic_run.cost`) + secondary (`ai_second_opinion_consulted.cost`, which holds secondary-only by convention)
- Text format surfaces these inline under the Outcomes section.

### CLAUDE.md — Event Logging additions
- `ai_second_opinion_consulted` documented with full data schema.
- `ai_escalation_recommended` documented with both trigger paths (high-confidence-escalate-now + both-low).

---

## Smoke results (all pass)

### (1) Escalation routing
```
🚨 ESCALATION RECOMMENDED — see /tmp/p2-d-smoke-escalate/ai-diagnosis-01.json. Reason: spec wrong. notify.sh invoked.
Notification sent: ai_escalation_recommended (p2-d-smoke-escalate)
```
- `ESCALATE_TRIGGERED` ✓
- `ESCALATE_EVENT_LOGGED` ✓

### (2) Second-opinion
```
ℹ️  Primary diagnosis low-confidence — consulting OpenAI gpt-5.2-pro for second opinion…
Diagnosis #01 saved to: /tmp/p2-d-smoke-second/ai-diagnosis-01.json
Secondary saved to: /tmp/p2-d-smoke-second/ai-diagnosis-01-secondary.json
Provider: openai (gpt-5.2-pro)
Confidence: high
Cost: $0.003000 (primary + secondary)
```
- `SECOND_OPINION_RAN` ✓
- `PRIMARY_WRITTEN` ✓
- `SECONDARY_SAVED` ✓
- Swap verified: primary file has `provider=openai, primary_provider=gemini, primary_confidence=low, second_opinion_used=true`

### (3) A/B variant
- Base run: `model = "gemini-3.1-pro-preview"`
- `--variant=customtools` run: `model = "gemini-3.1-pro-preview-customtools"`
- Variant model name correctly recorded in diagnosis JSON + event

### (4) ai-stats with second-opinion data
```json
{
  "diagnostics_run": 1,
  "second_opinions_consulted": 1,
  "second_opinion_rate": 100,
  "both_low_escalations": 0,
  "cost": { "total": 0.004, "avg": 0.002, "max": 0.002 }
}
```
Cost summation correct: $0.002 primary + $0.002 secondary = $0.004 total.

### (5) Integration test — 9/9 scenarios pass
```
Scenario 1: Verify pass → notify           ✅ PASS (5 assertions)
Scenario 2: Verify fail → report           ✅ PASS (6 assertions)
Scenario 3: Regression → rollback          ✅ PASS (5 assertions)
Scenario 4: No merge → no-op               ✅ PASS (3 assertions)
Scenario 5: verify → ai-diagnose           ✅ PASS (3 assertions)
Scenario 6: ai-stats counts                ✅ PASS (4 assertions)
Scenario 7: AI escalation routing          ✅ PASS (4 assertions)
Scenario 8: Second-opinion fallback        ✅ PASS (7 assertions)
Scenario 9: A/B variant — model recorded   ✅ PASS (3 assertions)

Results: 9/9 scenarios passed (40 assertions passed, 0 failed)
```

---

## Files changed

| File | Change |
|------|--------|
| `scripts/ai-diagnose.js` | Refactor: mock loader supports both single + {primary, secondary} shapes; helper `diagnoseOnce/parseDiagnose/augment` enables dual-call; second-opinion swap logic; both-low forces escalate_now; primary-model from `AI_DIAGNOSE_MODEL` env var; events: `ai_diagnostic_run` (now includes model), `ai_second_opinion_consulted` (secondary-only cost), `ai_escalation_recommended`; notify.sh invocation on escalation; project-root walk now checks phase-dir itself first. |
| `scripts/ai-diagnose.sh` | New `--variant=base\|customtools` flag → sets `AI_DIAGNOSE_MODEL` env var. |
| `scripts/notify.sh` | New event type `ai_escalation_recommended` with `🚨 [<project>] AI escalation recommended: <phase>` heading. `PROJECT_NAME` assignment moved before `format_message` (used by the new heading). |
| `templates/ai-diagnosis-schema.json` | New optional fields `second_opinion_used`, `primary_provider`, `primary_confidence`. Conditional: `second_opinion_used=true` requires both `primary_provider` and `primary_confidence`. Wrapped both conditionals in `allOf` so the existing `escalate_now → escalation_reason` rule still applies. |
| `scripts/ai-stats.sh` | New metrics: `second_opinions_consulted`, `second_opinion_rate`, `both_low_escalations`. `cost.total` sums primary + secondary. Text format renders the new rows. |
| `CLAUDE.md` | New NEVER rule under Autonomy: PM must halt auto-revision while `ai_escalation_recommended` event is unresolved. Event Logging entries for `ai_second_opinion_consulted` + `ai_escalation_recommended`. |
| `scripts/integration-test.sh` | New scenarios 7/8/9 (escalation routing / second-opinion / A/B variant). `SC_TOTAL` bumped 6 → 9. |
| `.planning/phases/p2-D/result.md` | This file. |

## Acceptance criteria (14/14)

- [x] ai-diagnose.js triggers escalation when `escalate_now=true AND confidence=high`
- [x] notify.sh recognizes `ai_escalation_recommended`, generates appropriate subject/body
- [x] CLAUDE.md updated: PM halts auto-revision when escalation event fires; new event documented
- [x] ai-diagnose.js runs second-opinion (OpenAI gpt-5.2-pro) when primary confidence is low
- [x] When second opinion is higher confidence, primary file uses second opinion; rejected one saved as -secondary
- [x] When both providers low, both saved + escalation forced ("both providers low-confidence" reason)
- [x] templates/ai-diagnosis-schema.json includes `second_opinion_used` + conditional fields
- [x] ai-stats.sh has new metrics: `second_opinions_consulted`, `second_opinion_rate`, `both_low_escalations`
- [x] ai-stats.sh sums BOTH primary + secondary cost
- [x] ai-diagnose.sh accepts `--variant=customtools` flag, passes through to underlying model
- [x] `AI_DIAGNOSE_MOCK` supports `{primary, secondary}` object for testing second-opinion flow
- [x] integration-test.sh has new scenarios (7/8/9) covering escalation routing, second-opinion fallback, A/B variant
- [x] Combined result.md at `.planning/phases/p2-D/result.md`
- [x] Commit with `[orchestrator-p2-D]` prefix (no `[ai-consult-p2-D]` needed — prompts/documentReview.js already provider-agnostic)
- [x] No push (awaiting approval)

## Out of scope (per dispatch, NOT touched)
- `{{ai_diagnostic_block}}` substitution remains PM-driven
- No third provider beyond Gemini + OpenAI
- No quality evaluation of A/B variant outputs — just enables the variant + records it
- `scripts/regression-test.sh`, `scripts/merge-phases.sh` untouched

## Operational notes

- **Cost asymmetry visible.** OpenAI gpt-5.2-pro is ~3× Gemini ($3.50/$28 vs $2/$12 per 1M). Second-opinion adds ~$0.025-0.040 per low-confidence case. `ai-stats.sh second_opinion_rate` is the dial to watch.
- **The "both low → escalate" path is the safety net.** When both AI models are uncertain, the user MUST intervene — verified by scenario 8's forced-escalation logic + the `both_low_escalations` metric.
- **`AI_DIAGNOSE_MODEL` env var is the canonical model-override hook.** Setting it directly bypasses the `--variant` flag and lets future A/B testing pin arbitrary Gemini variants without modifying ai-diagnose.sh.
- **Notify.sh integration is best-effort.** If notify.sh fails (missing config, hook crashes, etc.) the escalation event is still in events.jsonl + the diagnosis file exists — the PM/operator can recover from those artifacts even if the notification didn't land.
- **Schema compatibility.** The new optional fields are tagged with `additionalProperties: true` so existing tooling that doesn't know about them won't break. ajv validates the conditional only when `second_opinion_used=true`.

## P2 arc closing notes

P2 (AI-driven failure recovery) is now feature-complete across all 4 phases (A.0 → A → B → C → D). The orchestrator can:
- Run gemini-3.1-pro-preview on every verify failure (A)
- Auto-surface diagnostics to the PM via verify.sh + revision.md (B)
- Aggregate adoption / success / cost / confidence metrics (C)
- Escalate to user on high-confidence-spec-wrong + run OpenAI second-opinion on low-confidence + A/B benchmark variants (D)

Total cost baseline: ~$0.005-0.010 per straightforward case; ~$0.025-0.040 when second-opinion triggers. Test infrastructure: 40 deterministic, $0 assertions across 9 hermetic scenarios.
