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

### Sprint 5: Parallel Execution (estimated: 2-3 days)

The big one. Requires Sprint 4 foundation.

| # | Enhancement | What | Why | Effort |
|---|-------------|------|-----|--------|
| 5.1 | **Parallel dispatch** ✅ | Orchestrator queues independent phases simultaneously to different workers. | 2-3x faster for projects with independent tracks. | 4 hr | **DONE** |
| 5.2 | **Merge orchestration** | After parallel phases complete, orchestrator merges branches in dependency order. Handles conflicts. | Branch-per-phase needs coordinated merging. | 3 hr |
| 5.3 | **Worker load balancing** | Route phases to least-busy worker based on queue depth / current task. | Prevents one worker being overloaded while another idles. | 2 hr |
| 5.4 | **Parallel regression testing** | After merge, run ALL smoke tests from ALL completed phases as one batch. | Need to verify nothing broke during parallel work. | 2 hr |

**Acceptance criteria:** Two independent phases run simultaneously on two workers. Merge produces clean main branch. Regression tests pass post-merge.

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
