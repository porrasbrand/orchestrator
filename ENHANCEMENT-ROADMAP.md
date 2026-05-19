# Orchestrator Enhancement Roadmap

**Created:** 2026-04-04
**Source:** Internal analysis + Gemini AI consultation
**Current State:** v1 complete (CLAUDE.md + templates + scripts). Successfully dogfooded on GitHub Portfolio Build (10 phases, 0 revisions).

---

## Context

After completing the first real orchestration (ai-chances GitHub portfolio build), we identified limitations and brainstormed improvements. We then consulted Gemini for an independent perspective. This document merges both analyses into an actionable roadmap.

### Real-World Pain Points (from GitHub Portfolio Build)
1. `add-task.sh` broke on special characters — had to use temp files and direct SQLite insertion
2. No timeout/retry on SSH — silent failures possible
3. No way to cancel a queued phase if spec was wrong
4. No delivery confirmation — assumed queue insert = worker received it
5. Manual verification parsing — smoke tests are text in markdown

---

## Enhancement Priority (Merged Analysis)

### Sprint 1: Reliability Fixes (estimated: 1 day)

These fix real bugs we already hit. No new features — just making what exists actually work.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 1.1 | **Fix add-task.sh escaping** | Write task to temp file, pass via `cat`. Eliminate inline string escaping. | Broke twice during portfolio build. Blocking bug. | 30 min |
| 1.2 | **SSH timeout + retry** | Add 30s timeout, 2 retries with backoff to verify.sh and all SSH commands. | Silent failures on network issues. Verification can hang forever. | 1 hr |
| 1.3 | **Delivery ACK** | Worker confirms receipt by writing ACK event to queue. Orchestrator checks ACK before marking QUEUED. | Currently no confirmation the worker actually received the task. | 2 hr |
| 1.4 | **SSH key auth** | Replace sshpass + credential files with SSH key-based auth. | sshpass files are a security risk — one git push away from exposure. | 1 hr |

**Acceptance criteria:** All 4 fixes pass manual testing against >>hetzner.

---

### Sprint 2: Quality & Intelligence ✅ COMPLETE

Make the orchestrator smarter — catch problems earlier, learn from history.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 2.1 | **Structured learnings (JSONL)** | Replace learnings.md with learnings.jsonl. Schema: `{phase, category, discovery, impact}`. Keep learnings.md as human-readable view generated from JSONL. | Can't query "what failed in auth phases?" Currently just a flat markdown file. | 2 hr |
| 2.2 | **Context reset / handoff** ✅ | Add summary handoff template. Each phase spec includes a "Prior Work Summary" section (max 500 words) instead of assuming DEV has full context. Add `--fresh-context` flag to queue command. | Long projects degrade as Claude context fills. Gemini flagged this as top concern. | 3 hr | **DONE** |
| 2.3 | **Spec quality pre-check** ✅ | Before queuing, orchestrator scores spec on: has smoke tests? has acceptance criteria? has clear scope? Missing elements → warning. | Vague specs cause most revisions. Catch bad specs before they waste a phase cycle. | 2 hr | **DONE** |
| 2.4 | **Diff-based verification** ✅ | Spec includes `expected_files_changed: [list]`. Verification checks git diff and warns if unrelated files were modified. | Prevents DEV scope creep — touching files outside spec. | 2 hr | **DONE** |

**Acceptance criteria:** Learnings queryable by category. Spec pre-check catches intentionally vague test spec. Diff check flags out-of-scope file changes.

---

### Sprint 3: Structured Results & Verification ✅ COMPLETE

Replace fragile text parsing with machine-readable formats.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 3.1 | **Structured result.json** | DEV worker writes `result.json` alongside result.md: `{status, files_modified[], tests_run[], blockers[], summary}` | Currently parsing markdown for verification. Fragile. Claude can reliably output JSON. | 2 hr |
| 3.2 | **Executable smoke tests** ✅ | Smoke tests as `.sh` scripts in phase dir (not markdown text). verify.sh runs them directly. Exit code 0 = pass. | Regex parsing of markdown smoke tests is brittle. Scripts are deterministic. | 3 hr | **DONE** |
| 3.3 | **Cancellation mechanism** ✅ | Add `cancel-task.sh` — marks phase as CANCELLED in queue and events. Worker checks cancellation flag before starting. | No way to abort a bad spec once queued. Worker wastes full cycle. | 2 hr | **DONE** |
| 3.4 | **Phase idempotency** ✅ | Add cleanup section to spec template. DEV runs cleanup before implementation. Re-running a phase produces same result. | Partial completions + reruns could create duplicate state. | 1 hr | **DONE** |

**Acceptance criteria:** result.json parseable by verify.sh. Smoke test scripts execute and return proper exit codes. Cancel stops a queued-but-not-started phase.

---

### Sprint 4: Scaling Foundation ✅ COMPLETE

Prepare for parallel execution and more workers. Don't scale yet — build the foundation.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 4.1 | **Worker registry** ✅ | `config/workers.json`: list of workers with name, ssh, capabilities, status. Scripts read from registry instead of hardcoded paths. | Adding a worker currently requires editing multiple scripts. | 2 hr | **DONE** |
| 4.2 | **Dependency DAG** ✅ | Phase specs include `depends_on: [phase-ids]`. Orchestrator builds DAG and identifies parallelizable phases. | Required foundation for parallel execution. | 3 hr | **DONE** |
| 4.3 | **Branch-per-phase** ✅ | Each phase works on `phase-XX-name` branch. Orchestrator merges to main after verification. | Multiple workers pushing to same branch = merge conflicts. | 3 hr | **DONE** |
| 4.4 | **Status web page** ✅ | Generate static HTML from status.json + events.jsonl. Publish to manuelporras.com/orchestrator/. | Can't monitor progress from phone or share with others. | 3 hr | **DONE** |
| 4.5 | **Per-phase token/cost tracking** ✅ | Track tokens used and wall-clock time per phase. Store in events.jsonl. Summary in status page. | No visibility into what phases actually cost. Runaway risk. | 2 hr | **DONE** |

**Acceptance criteria:** New worker addable via config only. DAG correctly identifies parallel opportunities. Branch workflow doesn't break existing sequential flow. Status page renders in browser.

---

### Sprint 5: Parallel Execution ✅ COMPLETE

The big one. Requires Sprint 4 foundation.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 5.1 | **Parallel dispatch** ✅ | Orchestrator queues independent phases simultaneously to different workers. | 2-3x faster for projects with independent tracks. | 4 hr | **DONE** |
| 5.2 | **Merge orchestration** ✅ | After parallel phases complete, orchestrator merges branches in dependency order. Handles conflicts. | Branch-per-phase needs coordinated merging. | 3 hr | **DONE** |
| 5.3 | **Worker load balancing** ✅ | Route phases to least-busy worker based on queue depth / current task. | Prevents one worker being overloaded while another idles. | 2 hr | **DONE** |
| 5.4 | **Parallel regression testing** ✅ | After merge, run ALL smoke tests from ALL completed phases as one batch. | Need to verify nothing broke during parallel work. | 2 hr | **DONE** |

**Acceptance criteria:** Two independent phases run simultaneously on two workers. Merge produces clean main branch. Regression tests pass post-merge.

---

## Sprint 6: Spec Templating

Reduce boilerplate and improve consistency by providing typed phase templates.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 6.1 | **Phase type templates** ✅ | Create `templates/phase-types/` with 6 typed templates: new-bash-script, modify-bash-script, config-change, documentation, bugfix, integration. Each has pre-filled sections and {{PLACEHOLDER}} vars. | Every spec repeats similar structure. Templates eliminate boilerplate and enforce consistency. | 2 hr | **DONE** |

**Acceptance criteria:** All 6 templates exist with correct REQUIRED_VARS, sections match spec.md structure, and placeholders use {{VAR}} syntax.

---

### Sprint 7: Verification Intelligence

Improve verify.sh output quality so failures are actionable without manual interpretation.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 7.1 | **Verify.sh Error Clarity** ✅ | Contextual error messages with suggestions, failure summary block, machine-readable verification-report.json | Minimal error messages cost 30+ min per revision cycle. Clearer errors + suggested fixes cut revision time in half. | 3 hr | **DONE** |
| 7.2 | **Notification Hooks** ✅ | `scripts/notify.sh` writes notifications to project files on events (phase complete/failed, verification failed, regression failed, project complete). Optional user hook via `config/notify-hook.sh`. | PM has no way to know when phases complete or fail without manually checking. | 2 hr | **DONE** |
| 7.3 | **Auto-Rollback on Regression Failure** ✅ | `scripts/auto-rollback.sh` runs regression tests, and if they fail, auto-reverts the last merged phase with `git revert`. Updates status.json (`rolled_back`), logs to events.jsonl, notifies via notify.sh. Exits 2 on revert conflict for manual escalation. | If regression tests fail after merge, broken code stays on main. PM must manually investigate and revert. | 2 hr | **DONE** |

**Acceptance criteria:** verify.sh prints actionable suggestions on failure, writes verification-report.json (valid JSON, parseable by jq), and provides copy-paste revision notes. notify.sh writes notifications.md + latest-notification.json and calls optional hook. auto-rollback.sh reverts last merge on regression failure, updates status to "rolled_back", and escalates on revert conflict.

---

### Sprint 8: Integration Testing

End-to-end testing of script chains to catch handoff bugs between interconnected scripts.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 8.1 | **Integration Test Suite** ✅ | `scripts/integration-test.sh` tests the verify → notify → rollback chain end-to-end using mock SSH (PATH override). 4 scenarios: verify pass, verify fail, regression rollback, no-merge no-op. | Scripts were tested individually but never as a chain. Handoff bugs between verify/notify/rollback could go undetected until a real failure. | 3 hr | **DONE** |
| 8.2 | **Worker Failover** ✅ | `scripts/failover.sh` monitors queued/in-progress phases and auto-re-queues to another worker if current worker is unreachable (3 retries) or phase exceeds timeout. `--check-only` mode for monitoring. Uses get-worker.sh + select-worker.sh. | If a worker goes down mid-phase, the phase stays queued forever. PM must manually detect timeout, cancel, and re-queue. | 2 hr | **DONE** |

**Acceptance criteria:** All 4 scenarios pass with mock SSH, no network dependency, cleanup after test. failover.sh detects worker-down and stale phases, selects alternative worker, updates status.json + events.jsonl, notifies via notify.sh.

---

## All Sprints Complete (8/8)

**Updated 2026-04-08.** The orchestrator enhancement roadmap is now fully implemented:

- **Sprint 1:** Reliability Fixes (SSH key auth, timeouts, delivery ACK)
- **Sprint 2:** Quality & Intelligence (structured learnings, context handoff, spec quality check, diff verification)
- **Sprint 3:** Structured Results (result.json, executable smoke tests, cancellation, idempotency)
- **Sprint 4:** Scaling Foundation (worker registry, dependency DAG, branch-per-phase, status page, timing)
- **Sprint 5:** Parallel Execution (parallel dispatch, merge orchestration, load balancing, regression testing)
- **Sprint 6:** Spec Templating (phase type templates for 6 common patterns)
- **Sprint 7:** Verification Intelligence (contextual errors, failure summaries, verification-report.json, notification hooks)
- **Sprint 8:** Integration Testing (end-to-end chain tests with mock SSH)

Total: 26 enhancements across 8 sprints. The orchestrator is now production-ready for parallel multi-worker execution with templated spec generation, actionable verification output, and end-to-end integration test coverage.

---

## What We Deliberately Defer

| Item | Why Defer |
|------|-----------|
| CLI wrapper (Node.js) | Current CLAUDE.md approach works. Build CLI only if usage increases significantly. |
| Deployment phase type | Separate concern. PM2/nginx are project-specific, not orchestrator-level. |
| Multi-project orchestration | Solve single-project parallel first. Multi-project adds complexity with little current benefit. |
| Live SSE streaming | Nice-to-have. Status page with manual refresh is sufficient. |
| AI consultation integration | Already works via consult-gemini task. No need to formalize. |

---

## Implementation Strategy

### Option A: Self-Orchestrate (Dogfooding)

Use the orchestrator itself to implement these sprints. Each sprint becomes an orchestration project with phases dispatched to >>hetzner.

**Pros:** Ultimate dogfooding. Every bug we hit IS the product.
**Cons:** If Sprint 1 fixes are needed for reliability, we're building on a shaky foundation.
**Verdict:** Start Sprint 1 manually (it's just bug fixes). Orchestrate Sprint 2+ through the framework.

### Option B: Direct Implementation

Implement everything directly — no orchestration overhead.

**Pros:** Faster for small changes. No meta-overhead.
**Cons:** Doesn't test the orchestrator. Misses dogfooding opportunity.
**Verdict:** Only for Sprint 1.

### Option C: Hybrid

Sprint 1: Direct (fix the tool before using the tool).
Sprint 2-5: Orchestrated (use the improved tool to build its own features).

**Verdict: Option C is the right approach.**

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Over-engineering | Each sprint has clear acceptance criteria. Ship when criteria met, not when "perfect". |
| Breaking existing functionality | Sprint 1 fixes are backwards-compatible. Sprint 3+ changes are additive. |
| Scope creep | Deferred items list is explicit. Don't pull items forward without justification. |
| Context window degradation (meta-risk) | Sprint 2.2 specifically addresses this. Until then, keep phases small. |

---

## Gemini Consultation Archive

Full Gemini response archived at: `docs/gemini-consultation-2026-04-04.md`

Key Gemini insights not in our original analysis:
1. **Context reset between phases** — Biggest blind spot. Quality degrades in long projects.
2. **Delivery ACK** — We assumed queue insert = delivery. Wrong.
3. **Diff-based verification** — Catch scope creep at code level, not just test level.
4. **Branch-per-phase for scaling** — Prevents git conflicts before they happen.
5. **Spec quality scoring** — Catch bad specs before wasting a dispatch cycle.
6. **Idempotency** — Partial completions + reruns need explicit handling.
7. **Split-brain risk** — events.jsonl in git vs queue in SQLite can diverge.
8. **Cancellation path** — No abort mechanism exists for queued phases.

---

*Next action: Execute Sprint 1 (reliability fixes) directly, then orchestrate Sprint 2+ through the framework.*

---

# P2 — AI-Driven Failure Recovery (Shipped 2026-05-19)

## What it does

Every verification failure now auto-triggers a Gemini 3.1 Pro Preview diagnostic before the orchestrator (or human) writes a revision spec. The model reads the structured `verification-report.json`, the original `spec.md`, accumulated revisions, learnings, recent events, and the relevant git diff — then produces a JSON object with: root cause, surgical (line-positioned) suggested revisions, confidence rating, and an `escalate_now` flag for fundamentally broken specs.

When primary model confidence is low, the system auto-consults OpenAI gpt-5.2-pro as second opinion. When both are low, escalation is forced. When `escalate_now: true` fires with high confidence, the orchestrator halts the auto-revision cycle and routes through `notify.sh` — user must intervene rather than burning the 3-revision budget.

## Phases shipped

| Phase | Commits | Purpose |
|---|---|---|
| A.0 | ai-consult `fc401cc`, `33c1d47` | Add `gemini-3.1-pro-preview` + `-customtools` variant as default in ai-consult, pricing entries ($2/$12 ≤200K, $4/$18 >200K) |
| A | ai-consult `788af7b`, orchestrator `d34f370`, `fb118c5` | `scripts/ai-diagnose.{sh,js}`, `templates/ai-diagnosis-schema.json`, synthetic fixture, new `diagnosis` reviewType in ai-consult |
| B | orchestrator `715e72a` | Wire into `verify.sh` (non-blocking, behind `[ -x ]` guard), `templates/revision.md` placeholder, CLAUDE.md autonomy rule, `AI_DIAGNOSE_MOCK` env var |
| C | orchestrator `501dfa3` | `scripts/ai-stats.sh` (text+json), status page card, `ai_diagnostic_used` event |
| D | orchestrator `66cff71` | Escalation routing via `notify.sh`, OpenAI gpt-5.2-pro second-opinion on low-confidence, `--variant=customtools` A/B flag, 3 new integration scenarios |
| E | ai-consult `b818724`, orchestrator `bfefa9e`, `41ed397` | Hotfix: Gemini native `responseSchema` API for guaranteed JSON conformance (replaces prompt-only enforcement) |

**Integration tests:** 9 hermetic scenarios, 40 assertions, `$0` to run (uses `AI_DIAGNOSE_MOCK`).

**Cost baseline:**
- Standard diagnosis: ~$0.005–0.030 (input-size dependent)
- Second-opinion fallback: ~$0.025–0.040 extra (gpt-5.2-pro)
- b3x validation (12.8K input tokens): $0.030

## Real-world validation methodology

We synthesized a realistic failure scenario from `b3x-account-expert/.planning/phases/06.5-quality-eval/spec.md` (38KB complex spec) — fabricated a `verification-report.json` mimicking what `verify.sh` would produce for a DEV worker who (a) used the wrong column name (`topic_id` instead of `topic_cluster_id`) and (b) modified out-of-scope files (`scripts/eval-harness.js`).

The model's response:
1. Caught both planted failures
2. Produced architectural insight we didn't anticipate: "spec lacks a designated generation script in 'Files to Create', forcing the worker to improvise by modifying existing out-of-scope scripts"
3. Generated 3 surgical, line-positioned revisions — including adding a new script entry to the directory layout, adding it to "Files to Create", and strengthening the "Do NOT Touch" callout

This is the gold standard: not just "find the bug" but "fix the spec design flaw that caused the bug."

## Key engineering decisions (worth remembering)

1. **API native structured output > prompt-only JSON enforcement.** First implementation used "STRICT JSON output (no prose, no markdown fence)" in the system prompt. Looked clean on the simple fixture; failed at JSON position 587 on real complex output (model used `\`` to escape backticks in markdown code samples — invalid JSON). Phase E switched to Gemini's `responseSchema` + OpenAI's `json_schema strict` mode. **Zero cost, imperceptible latency, guaranteed conformance.**

2. **Schema compatibility transform.** Canonical schema stays draft-07 (for ajv defense-in-depth). At call time, `toGeminiSchema()` walker strips Gemini-incompatible keywords (`additionalProperties`, `$schema`, `$id` — OpenAPI 3.0 subset). OpenAI retains them under strict mode. Per-provider transform, not separate schema files.

3. **Supplementary-not-blocking integration.** `verify.sh` calls `ai-diagnose.sh` but ignores its exit code for the verdict — diagnostic failure never breaks verification. If `ai-diagnose.sh` doesn't exist (bare install), `verify.sh` skips it silently via `[ -x ]` guard.

4. **`AI_DIAGNOSE_MOCK` env var.** Single-path: takes canned response JSON. Dual-path: takes `{primary, secondary}` object for second-opinion testing. Used by all integration test scenarios — deterministic, network-free, $0.

5. **`{{ai_diagnostic_block}}` is PM-driven** (Claude fills it from `ai-diagnosis-NN.json`), not automated. Phase B chose this deliberately — adds zero new code, lets the PM exercise judgment. Future Phase could mechanize via `render-revision.sh` if cadence becomes a bottleneck.

6. **The `--variant=customtools` flag** flows through via `AI_DIAGNOSE_MODEL` env var. Same input → different model. Recorded in `ai-diagnosis-NN.json`'s `model` field for audit. Foundation for future quality benchmarking; no comparison logic ships in P2.

## What's next on the roadmap

Master roadmap from the strategic review still stands. In recommended order:

- **P1** — Live observability + mid-flight interrupt (SSE/WebSocket status page; `interrupt.json` flag checked at phase boundaries)
- **P3** — Portfolio orchestration (lift `.planning/` to portfolio root; round-robin dispatch across workers; cross-project regression registry; 2-3× throughput)
- **P4** — Brief auto-generation (one-line goal → clarifying Q&A → `brief.md`; unlocks the autonomous front-end)
- **P5** — Deploy + monitor modules (new `deploy` phase type; `monitor-prod.js` service; closes the build→ship→learn→fix loop)
- **P6** — Self-improvement loop (mine `learnings.jsonl` + `events.jsonl` across N projects; auto-update `spec.md` template and `check-spec.sh` rules; orchestrator orchestrates its own improvements)
