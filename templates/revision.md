# Phase XX: <Phase Name> — Revision N

## What Failed
[Exact smoke test output or acceptance criteria that did not pass]

```
# Failed smoke test:
[command]
Expected: [expected]
Got: [actual]
```

## Previous Revisions
<!-- Include ALL prior revision context so DEV doesn't repeat mistakes -->

### Revision N-1
[What failed and what was attempted in the previous revision]

### Original Attempt
[What failed in the first attempt]

## Learnings Since Original Spec
[Any new discoveries from learnings.md that might help]

## AI Diagnostic (auto-generated)
{{ai_diagnostic_block}}

<!--
SUBSTITUTION RULES for {{ai_diagnostic_block}} (filled by the PM / orchestrator):

1. Look in the phase-dir for the highest-numbered ai-diagnosis-NN.json (the
   one ai-diagnose.sh wrote during the most recent verify failure).
2. If found, render the following block, substituting JSON fields:

       **Model:** <model>  ·  **Confidence:** <confidence>  ·  **Cost:** $<cost.totalCost>

       **Root cause:** <root_cause>

       **Diagnosis:** <diagnosis>

       **Suggested revisions:**
       - **<suggested_revisions[i].section>:** <suggested_revisions[i].change>
       - (repeat for each suggested_revisions entry)

       <if escalate_now=true>
       > ⚠️  **Escalation recommended:** <escalation_reason>
       </if>

3. If no ai-diagnosis-*.json file exists, replace with the literal line:
   _(no AI diagnostic available — primitive not run or failed)_

4. The PM (Claude) is expected to incorporate the suggested_revisions as
   concrete edits to the spec text in the "Additional Guidance" section
   below — apply them LITERALLY where they match the original wording, do
   not paraphrase. The full Diagnostic block above is included so the DEV
   worker sees the same context the orchestrator did.
-->

## Additional Guidance
[Specific hints based on failure analysis — e.g., "The route was defined but not mounted in server.js"]
[When an AI Diagnostic above has high confidence + concrete suggested_revisions, apply them here verbatim before adding any additional guidance.]

---

## Full Original Spec
<!-- Paste the complete original spec.md below — DEV needs full context -->
