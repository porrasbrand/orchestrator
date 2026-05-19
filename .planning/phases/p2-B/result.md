# P2 Phase B — Wire ai-diagnose into the revision flow (RESULT)

**Dispatch:** ORCHESTRATOR P2 PHASE B
**Repo:** orchestrator only (ai-consult untouched this phase)
**Push:** NOT done (per dispatch — wait for explicit push approval)

---

## Files changed

| File | Change |
|------|--------|
| `scripts/verify.sh` | On verification failure (after the existing failure summary + events.jsonl write, before `exit 1`), invokes `scripts/ai-diagnose.sh` if executable. Three exit-code bands (0 ok / 1 transient / 2 schema fail) each print a distinct status line. If `ai-diagnose.sh` is absent or non-executable, skip silently (bare-install backward compat). verify.sh still exits 1 regardless of diagnostic outcome — supplementary, never blocking. |
| `scripts/ai-diagnose.js` | Added `AI_DIAGNOSE_MOCK=<path>` env-var support: when set, bypasses the ai-consult call and reads a canned `{feedback, usage, cost}` JSON. Used by integration-test for deterministic, cost-free CI runs. Documented in script header. |
| `templates/revision.md` | New `## AI Diagnostic (auto-generated)` section between "Learnings Since Original Spec" and "Additional Guidance". Placeholder `{{ai_diagnostic_block}}` plus an HTML comment with explicit substitution rules for the PM: how to render the diagnosis fields, the fallback line when no `ai-diagnosis-*.json` exists, and the directive to apply `suggested_revisions` literally in the Additional Guidance section. |
| `CLAUDE.md` | Three additions: (1) new **Step 4: AI Diagnostic** subsection under Verification documenting the auto-invocation, exit-code bands, and the PM directive to read the diagnostic before composing revisions; (2) new event types `ai_diagnostic_run` (emitted by ai-diagnose.js) and `ai_diagnostic_used` (manual / Phase C tooling, documented for forward compat); (3) new Autonomy Rule bullet covering high-confidence auto-apply vs. low-confidence / escalate_now=true pause-for-user behavior. |
| `scripts/integration-test.sh` | New `run_scenario_5` exercising verify → ai-diagnose with `AI_DIAGNOSE_MOCK`. Stages the existing test-fixture into the mock project, runs ai-diagnose.sh, asserts exit 0 + `ai-diagnosis-01.json` produced + required schema keys present. Echoes a `verify → ai-diagnose chain scenario completed` marker for the smoke grep. `SC_TOTAL` bumped from 4 → 5. |

## Smoke results

### A) Real Gemini call (via fixture)
```
Phase: test-failed
Diagnosis #01 saved to: /tmp/p2-b-smoke/.planning/phases/test-failed/ai-diagnosis-01.json
Confidence: high
Escalate: no
Root cause: Missing port binding (`app.listen(4080)`) in `src/server.js`.
Cost: $0.005658
REAL_SMOKE_PASS
```
Model again produced a surgical, high-confidence diagnosis on the fixture. Cost in the expected $0.005-0.010 band.

### B) Integration test (mocked Gemini, no network, $0)
```
Scenario 1: Verify pass → notify    ✅ PASS (5 assertions)
Scenario 2: Verify fail → report    ✅ PASS (6 assertions)
Scenario 3: Regression → rollback   ✅ PASS (5 assertions)
Scenario 4: No merge → no-op        ✅ PASS (3 assertions)
Scenario 5: verify → ai-diagnose    ✅ PASS (3 assertions — exit 0 + file produced + schema keys)

Results: 5/5 scenarios passed (22 assertions passed, 0 failed)
INTEGRATION_PASS
```

## Acceptance criteria

- [x] `verify.sh` calls `ai-diagnose.sh` on failure, handles all 3 exit codes gracefully (0/1/2 + unknown fallback)
- [x] `verify.sh` still exits 1 on failure regardless of ai-diagnose outcome (supplementary, not blocking)
- [x] If `ai-diagnose.sh` missing/non-executable, `verify.sh` skips silently (backwards compat — `[ -x "$AI_DIAGNOSE_BIN" ]` guard)
- [x] `templates/revision.md` has new "AI Diagnostic (auto-generated)" section with clear substitution rules (HTML comment block defines the substitution shape verbatim)
- [x] `CLAUDE.md` documents new flow (Step 4: AI Diagnostic), `ai_diagnostic_run` + `ai_diagnostic_used` events, new autonomy rule
- [x] `ai-diagnose.js` supports `AI_DIAGNOSE_MOCK=<path>` env var
- [x] `scripts/integration-test.sh` has scenario 5 covering verify → ai-diagnose chain (mocked)
- [x] Combined result.md at `.planning/phases/p2-B/result.md`
- [x] Commit with `[orchestrator-p2-B]` prefix
- [x] No push (awaiting approval)

## Out of scope (per dispatch, NOT touched)
- `scripts/ai-diagnose.sh` itself — only `ai-diagnose.js` mutated to add the MOCK env var
- `scripts/notify.sh` (Phase D wires `ai_escalation_recommended`)
- OpenAI fallback (Phase D)
- `scripts/ai-stats.sh` (Phase C)
- `templates/ai-diagnosis-schema.json` (unchanged from Phase A)

## Operational notes for Phase C/D

- The `{{ai_diagnostic_block}}` template substitution is **PM-driven** (no automated filler) per the dispatch's note: "If revision.md is currently filled by ad-hoc orchestrator instructions, document the substitution rules in the template as comments." Phase C could add a small `scripts/render-revision.sh` to mechanize this if the manual cadence becomes a bottleneck.
- The `AI_DIAGNOSE_MOCK` env var is the canonical mock interface for downstream test scenarios; reuse it for Phase D's escalation-routing tests so notify.sh changes can be tested without burning Gemini cost.
- Backward compat: the `[ -x "$AI_DIAGNOSE_BIN" ]` guard means the orchestrator continues to work on hosts where ai-consult is not installed. Worth keeping forever (some bare-install or rollback scenarios may need it).
