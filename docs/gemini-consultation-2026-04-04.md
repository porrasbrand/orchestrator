# Gemini Consultation: Orchestrator Enhancements

**Date:** 2026-04-04
**Model:** Gemini (via >>hetzner consult-gemini)
**Input:** orchestrator-enhancement-consultation.md (architecture, capabilities, 13 known limitations, 8 questions)

---

## 1. Missing Enhancement Opportunities

**A. Context Window Management**
Biggest hidden bottleneck: Claude instances accumulate context over phases. After 5-6 phases, DEV workers are operating with degraded context windows. Add: explicit context reset points, summary handoffs between phases, or worker rotation per-phase.

**B. Spec Quality Scoring**
Before queuing, run the spec through a quick LLM pass to score clarity (1-10). Vague specs cause 80% of revisions. Catch them before dispatch.

**C. Phase Dependency Graph**
Track linear phases but not dependencies. Some phases could run in parallel, others have implicit deps. Build a DAG, not just a list.

**D. Worker Capability Matching**
>>hetzner may have different installed tools than >>wsl2. Track worker capabilities (node version, Python version, installed CLI tools) and match phases to compatible workers.

**E. Rollback Mechanism**
If phase 7 breaks something phase 3 built, need coordinated rollback. Git revert isn't enough — need to know which phases touched which files and how to unwind.

**F. Diff-Based Verification**
Instead of just smoke tests, verify the git diff matches expected changes. 'This phase should only modify src/api/*.ts' — fail if it touched unrelated files.

---

## 2. Priority Ordering (Top 5)

1. **Fix add-task.sh escaping** — Blocking bug. Use heredoc or temp file. 30 min fix.
2. **SSH timeout + retry** — Verification fails silently on network issues. Add 30s timeout, 2 retries, exponential backoff.
3. **Context reset between phases** — Start each phase with fresh Claude context + summary of prior work. Prevents context window degradation.
4. **Structured learnings (JSONL)** — Query 'what failed in auth-related phases?' Currently impossible.
5. **Parallel phase execution** — Biggest scaling win. Identify independent phases via dependency graph.

---

## 3. Architecture Gaps

**A. No Idempotency Guarantees**
If a phase partially completes (crash mid-execution), rerunning it may cause duplicate work. Each phase should be idempotent or have explicit cleanup-before-retry.

**B. State in Git vs State in SQLite**
Split-brain risk: events.jsonl is in git, queue is in SQLite. If git push fails after queue confirmation, states diverge. Solution: queue should read from git, not maintain separate state.

**C. No Cancellation Path**
Once a phase is queued, can't cancel it. If spec is wrong mid-execution, DEV worker completes garbage work before intervention. Add: kill signal mechanism.

**D. Hardcoded Worker Topology**
Worker addresses embedded in scripts. Should be config-driven with worker registry.

---

## 4. Comparison with Existing Tools

**vs GitHub Actions:**
Missing: artifact passing between phases, secrets injection, cached dependencies.
Learn: add artifact handoff (phase 3 produces JSON -> phase 5 consumes it).

**vs Temporal/Airflow:**
Missing: DAG visualization, retry policies, backpressure, dead-letter queues.
Learn: add PERMANENTLY_FAILED status for phases that exhaust all revisions.

**vs Kubernetes Jobs:**
Missing: resource limits, pod eviction, horizontal scaling.
Learn: add worker resource tracking (disk space, memory) to avoid mid-phase crashes.

**Key Differentiator:**
None of these tools understand code semantically. Orchestrator can say 'verify the API returns expected JSON schema' because Claude DEV workers understand code. Lean into this — add schema validation, type checking, semantic diff verification.

---

## 5. Claude-Specific Optimizations

**A. Structured Output Guarantees**
Claude can return JSON reliably. Use for machine-readable result.json instead of markdown parsing.

**B. Tool Use for Verification**
Instead of SSH + grep, have DEV worker use Claude's tool_use to run tests and return structured results.

**C. Context Priming**
Before each phase, inject system primer: 'You are working on phase 4 of project X. Prior phases completed: [summary]. Your scope is ONLY [spec excerpt].' Prevents scope creep.

**D. Explicit Stop Conditions**
Add to every spec: 'STOP IMMEDIATELY when: tests pass, or you've attempted 3 approaches, or you hit a blocking external dependency.'

**E. Token Budget Per Phase**
Track tokens used per phase. Set soft limits (warn at 50K, hard stop at 100K).

---

## 6. Verification Strategy

**Level 1: Exit Code Verification**
DEV worker ends with explicit exit code. 0 = success, 1 = tests failed, 2 = couldn't complete.

**Level 2: Structured Verification JSON**
DEV runs: npm test --json > .planning/phase-N-test-results.json. Orchestrator parses JSON.

**Level 3: Contract Testing**
For API phases, include expected request/response in spec. Orchestrator runs curl with expected input, validates output matches contract.

**Level 4: Snapshot Testing**
For UI phases, capture screenshot after implementation. Human reviews at checkpoints.

**Avoid:** Complex test frameworks, mocking infrastructure, integration test suites. Keep it simple.

---

## 7. Scaling to 5-10 Workers

**What Breaks First:**

1. **Queue contention** — SQLite doesn't handle concurrent writes. Solution: PostgreSQL or per-worker queues.
2. **SSH connection limits** — Connection exhaustion at 10 workers. Solution: connection pooling or persistent tunnels.
3. **Git conflicts** — Multiple workers pushing to same repo. Solution: branch-per-phase.
4. **Credential sprawl** — Each worker needs keys/tokens. Solution: centralized secrets manager.
5. **Visibility chaos** — status.sh unreadable at 10 workers. Solution: web dashboard.

**Build Now:**
- Worker registry (config file)
- Per-worker queues
- Branch-per-phase git workflow

---

## 8. Risk Assessment

**HIGH RISK:**
- Runaway costs (no token tracking, stuck phase could burn $50+)
- Silent failures (SSH fails without alerting)
- Security exposure (sshpass credential files)
- No backup/recovery (events.jsonl corruption = lost state)

**MEDIUM RISK:**
- Context degradation (long projects, quality drops)
- Spec drift (inconsistent templates over time)
- Single point of failure (lipo-360 down = everything stops)

**LOW RISK:**
- Timezone confusion (standardize on UTC)
- Log sprawl (add rotation)

---

## Immediate Actions (Gemini's Recommendation)

1. Fix add-task.sh (30 min)
2. Add SSH timeout/retry (1 hr)
3. Add delivery confirmation / worker ACK (2 hr)
4. Move credentials from sshpass to SSH keys (1 hr)
5. Add per-phase token tracking (2 hr)

---

*Raw consultation output preserved for reference. Merged analysis in ENHANCEMENT-ROADMAP.md.*
