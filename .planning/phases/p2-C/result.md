# P2 Phase C — Events + ai-stats tracking (RESULT)

**Dispatch:** ORCHESTRATOR P2 PHASE C
**Repo:** orchestrator only
**Push:** NOT done (per dispatch — wait for explicit push approval)

---

## Files changed

| File | Change |
|------|--------|
| `CLAUDE.md` | (a) Promoted `ai_diagnostic_used` emission instruction directly under the "Step 4: AI Diagnostic" autonomy directive — added a MANDATORY callout with the canonical bash one-liner the PM should run after writing a revision spec that incorporated diagnostic suggestions. (b) Tightened the Event Logging entry for `ai_diagnostic_used` — removed the "Phase C will add tooling" placeholder and pointed to the autonomy rule + `scripts/ai-stats.sh` correlation. |
| `scripts/ai-stats.sh` (new) | Aggregates `.planning/events.jsonl`. Flags: `--project --since --format --phase`. Two output formats: text (sectioned, human-readable) + json (machine-readable). Computes: diagnostics_run, diagnostics_used, adoption_rate, ai_assisted_success_rate (correlates `ai_diagnostic_used` → next-same-phase `phase_complete` vs. `phase_verification_failed`), cost {total/avg/max}, confidence_distribution {high/medium/low}, escalation_rate, top_phases (top 5), time_range, warnings (malformed JSONL + missing-cost events). Tails the file when > 10K lines for bounded memory. Edge cases: empty / missing / malformed all return clean output, exit 0. |
| `scripts/generate-status-page.sh` | New "AI Diagnostic Stats" card placed after Summary. Best-effort: if `ai-stats.sh` is missing/non-executable or returns no data, falls back to 0/n/a defaults — page generation never blocks. Compact 5-row table: Diagnostics run / Adoption rate / Total cost / AI-assisted success rate / Escalation rate. Matches existing page visual style. |
| `scripts/integration-test.sh` | New `run_scenario_6` "ai-stats reports expected counts" using a hermetic project dir (separate from the main test project, so prior scenarios' events don't contaminate the assertions). Synthesizes a clean `ai_diagnostic_run` + `ai_diagnostic_used` pair, runs `ai-stats.sh` in both json and text formats, asserts 1 run / 1 used / 100% adoption / text format renders the count. `SC_TOTAL` bumped 5 → 6. |
| `.planning/phases/p2-C/result.md` (new) | This file. |

## Smoke results

### A) Per-spec text + json output on the dispatch's 5-event stream
```
AI Diagnostic Stats
===================
Time range: 2026-05-19T10:00:00Z → 2026-05-19T11:01:00Z

-- Usage --
Diagnostics run:   2
Diagnostics used:  1
Adoption rate:     50%

-- Outcomes --
AI-assisted revision success rate: 100%
Escalation rate:   50%

-- Cost --
Total:  $0.0130
Avg:    $0.0065
Max:    $0.0080

-- Confidence distribution --
high:   1
medium: 0
low:    1

-- Top diagnosed phases --
phase-1: 1
phase-2: 1
```
- `grep -q "Diagnostics run.*2"` → **TEXT_COUNT_PASS**
- `jq -e ".diagnostics_run == 2 and .diagnostics_used == 1"` → **JSON_PARSE_PASS** (true)

### B) Edge cases (all clean, exit 0)
- empty events.jsonl → `events.jsonl empty`
- missing events.jsonl → `No events.jsonl at <path>/.planning/events.jsonl`
- malformed JSONL lines → counted in `warnings.malformed_lines` and surfaced in the text Warnings section; valid lines still aggregated

### C) Integration test
```
Scenario 1: Verify pass → notify    ✅ PASS (5 assertions)
Scenario 2: Verify fail → report    ✅ PASS (6 assertions)
Scenario 3: Regression → rollback   ✅ PASS (5 assertions)
Scenario 4: No merge → no-op        ✅ PASS (3 assertions)
Scenario 5: verify → ai-diagnose    ✅ PASS (3 assertions)
Scenario 6: ai-stats counts         ✅ PASS (4 assertions)

Results: 6/6 scenarios passed (26 assertions passed, 0 failed)
```

### D) Status page renders the AI section
```
<tr><td>Diagnostics run</td><td>2</td></tr>
<tr><td>Adoption rate</td><td>50%</td></tr>
<tr><td>Total cost</td><td>$0.0130</td></tr>
<tr><td>AI-assisted success rate</td><td>100%</td></tr>
<tr><td>Escalation rate</td><td>50%</td></tr>
```

## Acceptance criteria

- [x] CLAUDE.md documents `ai_diagnostic_used` event with emission rules (canonical bash one-liner)
- [x] CLAUDE.md instruction is **prominent** — placed directly under Step 4 (the Phase B autonomy rule), labeled MANDATORY, not buried in the event-log section
- [x] `scripts/ai-stats.sh` exists, executable, supports `--project`, `--since`, `--format`, `--phase` flags
- [x] Handles empty / missing / malformed input gracefully (no crashes, exit 0)
- [x] Text output is human-readable with clear sections (Usage / Outcomes / Cost / Confidence / Top phases / Warnings)
- [x] JSON output is parseable and contains all metrics
- [x] `scripts/generate-status-page.sh` includes AI Diagnostic Stats section (best-effort, doesn't block page gen on missing data)
- [x] `scripts/integration-test.sh` has scenario 6 asserting ai-stats produces expected counts
- [x] Combined result.md at `.planning/phases/p2-C/result.md`
- [x] Commit with `[orchestrator-p2-C]` prefix
- [x] No push (awaiting approval)

## Out of scope (per dispatch, NOT touched)
- `scripts/ai-diagnose.sh` / `ai-diagnose.js` — unchanged from Phase B
- `scripts/verify.sh` — unchanged from Phase B
- `scripts/notify.sh` — Phase D wires `ai_escalation_recommended`
- OpenAI second-opinion logic — Phase D
- `{{ai_diagnostic_block}}` substitution automation — deferred to a later phase per the Phase B handoff note
- `templates/ai-diagnosis-schema.json` — unchanged

## Operational notes

- **Adoption rate** is the primary leading indicator: `ai_diagnostic_used / ai_diagnostic_run`. Low adoption means the PM isn't reading the diagnostics — likely a CLAUDE.md / runbook problem rather than a model-quality one.
- **AI-assisted success rate** is computed via in-order correlation: for each `ai_diagnostic_used` event, find the next same-phase `phase_complete` or `phase_verification_failed`. Returns `null` (text: "n/a") when no resolved-used events exist yet — avoids misleading 0% on cold-start.
- **Cost monitoring:** baseline ~$0.005-0.010 per diagnosis on small specs. The `cost.max` metric flags outliers (large specs / oversize contexts) for tuning.
- **Status-page section is compact** (5 rows) per dispatch. Matches existing card style. Falls back to zeros + "n/a" if `ai-stats.sh` returns malformed/empty JSON — page generation is never blocked.
- **Hermetic tests:** scenario 6 uses a separate `$TEST_DIR/ai-stats-project` so it doesn't depend on prior scenarios' events.jsonl state.
