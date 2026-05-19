#!/usr/bin/env node
// scripts/ai-diagnose.js — orchestrator P2 Phase A.
// Invoked by scripts/ai-diagnose.sh with a phase-dir argument; builds a
// structured failure context from verification-report.json + spec.md +
// optional revisions/learnings/events/git diff, calls ai-consult with the
// diagnosis reviewType, validates the model's JSON against
// templates/ai-diagnosis-schema.json, augments with provider/model/timestamp/
// cost, writes ai-diagnosis-NN.json into the phase-dir, and appends an
// ai_diagnostic_run event to the project's .planning/events.jsonl.
//
// Exit codes:
//   0 ok
//   1 missing required file OR ai-consult call failed
//   2 schema validation failed (raw response preserved at ai-diagnosis-NN.raw.txt)
//
// Env vars:
//   AI_CONSULT_PATH    default: ~/awsc-new/awesome/ai-consult
//   AI_DIAGNOSE_MODEL  override the Gemini model id (e.g.,
//                      'gemini-3.1-pro-preview-customtools' for the A/B variant
//                      from ai-diagnose.sh --variant=customtools).
//   AI_DIAGNOSE_MOCK   path to a JSON file. Two accepted shapes:
//                      (a) Single: {feedback, usage, cost} — used as the
//                          primary (and only) response.
//                      (b) Pair:   {primary: {...}, secondary: {...}} — primary
//                          is used first; secondary is consumed if the second-
//                          opinion path triggers (primary low-confidence).
//                      Lets integration tests cover both the single-pass and
//                      the second-opinion code paths deterministically.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const AI_CONSULT_PATH = process.env.AI_CONSULT_PATH || path.resolve(process.env.HOME || '/home/ubuntu', 'awsc-new/awesome/ai-consult');

// Load ai-consult's .env so GOOGLE_API_KEY / OPENAI_API_KEY are available
// regardless of CWD. ai-consult's own require('dotenv').config() reads from
// CWD only — we explicitly point dotenv at AI_CONSULT_PATH/.env.
try {
  const dotenvPath = path.join(AI_CONSULT_PATH, 'node_modules', 'dotenv');
  require(dotenvPath).config({ path: path.join(AI_CONSULT_PATH, '.env') });
} catch {
  // dotenv missing or .env absent — fall through; ai-consult may still
  // pick up env vars from the parent process.
}
const SCRIPT_DIR = __dirname;
const ORCHESTRATOR_ROOT = path.resolve(SCRIPT_DIR, '..');
const SCHEMA_PATH = path.join(ORCHESTRATOR_ROOT, 'templates', 'ai-diagnosis-schema.json');
const MAX_DIFF_LINES = 500;
const MAX_EVENTS = 50;

function fail(msg, code = 1) {
  console.error(`[ai-diagnose] ${msg}`);
  process.exit(code);
}

function readIfExists(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function safeRun(cmd, opts = {}) {
  try {
    return execSync(cmd, { encoding: 'utf8', ...opts });
  } catch (e) {
    return null;
  }
}

function lastNLines(text, n) {
  if (!text) return '';
  const lines = text.split('\n');
  return lines.slice(-n).join('\n');
}

function truncateLines(text, max) {
  if (!text) return '';
  const lines = text.split('\n');
  if (lines.length <= max) return text;
  return lines.slice(0, max).join('\n') + `\n... [TRUNCATED — ${lines.length - max} more lines omitted]`;
}

function findExpectedFilesChanged(specMd) {
  // Look for an "expected files changed" / "files to modify" / "files to create"
  // bulleted list. Returns the file paths or null.
  if (!specMd) return null;
  const headingRe = /^#+\s*(Expected Files Changed|Files to (?:Create|Modify)|Files Changed)/im;
  const m = specMd.match(headingRe);
  if (!m) return null;
  const start = m.index + m[0].length;
  const rest = specMd.slice(start);
  // Capture lines until the next heading or end-of-string.
  const block = rest.split(/\n#+\s/)[0];
  const files = [];
  for (const line of block.split('\n')) {
    const bm = line.match(/^\s*[-*]\s+(?:`([^`]+)`|(\S+))/);
    if (bm) files.push(bm[1] || bm[2]);
  }
  return files.length ? files : null;
}

function buildContext({ phaseDir, projectRoot, phaseName }) {
  const verifyPath = path.join(phaseDir, 'verification-report.json');
  const specPath = path.join(phaseDir, 'spec.md');

  const verifyRaw = readIfExists(verifyPath);
  if (!verifyRaw) fail(`Missing required file: ${verifyPath}`, 1);
  const specMd = readIfExists(specPath);
  if (!specMd) fail(`Missing required file: ${specPath}`, 1);

  // Revisions (optional, lexical order).
  const revisions = fs.readdirSync(phaseDir)
    .filter(n => /^revision.*\.md$/i.test(n))
    .sort()
    .map(n => ({ name: n, body: readIfExists(path.join(phaseDir, n)) || '' }));

  // Project learnings + last N events (optional).
  const planningDir = path.join(projectRoot, '.planning');
  const learnings = readIfExists(path.join(planningDir, 'learnings.md'));
  const eventsLog = readIfExists(path.join(planningDir, 'events.jsonl'));
  const recentEvents = lastNLines(eventsLog, MAX_EVENTS);

  // Git context — diff vs main, optionally scoped to expected_files_changed.
  let gitDiff = '';
  const expected = findExpectedFilesChanged(specMd);
  const gitOpts = { cwd: projectRoot };
  // If main is missing as a ref, fall back to HEAD~1 to avoid hard-fail.
  let base = 'main';
  if (!safeRun('git rev-parse --verify main', gitOpts)) {
    if (safeRun('git rev-parse --verify master', gitOpts)) base = 'master';
    else if (safeRun('git rev-parse --verify HEAD~1', gitOpts)) base = 'HEAD~1';
    else base = null;
  }
  if (base) {
    const args = expected && expected.length
      ? `${base} -- ${expected.map(f => `'${f.replace(/'/g, "'\\''")}'`).join(' ')}`
      : base;
    const raw = safeRun(`git diff ${args}`, gitOpts) || '';
    gitDiff = truncateLines(raw, MAX_DIFF_LINES);
  }

  const sections = [];
  sections.push(`# Failed Phase Diagnostic Context — ${phaseName}\n`);
  sections.push(`## verification-report.json\n\n\`\`\`json\n${verifyRaw.trim()}\n\`\`\`\n`);
  sections.push(`## spec.md\n\n\`\`\`markdown\n${specMd.trim()}\n\`\`\`\n`);
  if (revisions.length) {
    sections.push(`## Revision attempts (${revisions.length})\n`);
    for (const r of revisions) sections.push(`### ${r.name}\n\n\`\`\`markdown\n${r.body.trim()}\n\`\`\`\n`);
  }
  if (learnings) sections.push(`## Project learnings (.planning/learnings.md)\n\n\`\`\`markdown\n${learnings.trim()}\n\`\`\`\n`);
  if (recentEvents) sections.push(`## Recent events (last ${MAX_EVENTS} of .planning/events.jsonl)\n\n\`\`\`\n${recentEvents.trim()}\n\`\`\`\n`);
  if (gitDiff) sections.push(`## Git diff vs ${base}\n\n\`\`\`diff\n${gitDiff}\n\`\`\`\n`);

  return sections.join('\n');
}

function nextDiagnosisNum(phaseDir) {
  const existing = fs.readdirSync(phaseDir).filter(n => /^ai-diagnosis-\d{2}\.json$/.test(n));
  return String(existing.length + 1).padStart(2, '0');
}

function validateSchema(obj) {
  // Use ajv if available; else degrade to manual key checks.
  let ajvAvailable = false;
  let Ajv;
  try {
    // Try locally — ai-consult installs ajv transitively via @google/generative-ai.
    Ajv = require(path.join(AI_CONSULT_PATH, 'node_modules', 'ajv'));
    ajvAvailable = true;
  } catch {
    try { Ajv = require('ajv'); ajvAvailable = true; } catch {}
  }
  const schema = JSON.parse(fs.readFileSync(SCHEMA_PATH, 'utf8'));
  if (ajvAvailable) {
    const ajv = new Ajv({ allErrors: true, strict: false });
    const validate = ajv.compile(schema);
    const ok = validate(obj);
    return { ok, errors: ok ? [] : validate.errors, validator: 'ajv' };
  }
  // Fallback — assert all required top-level keys present.
  const errors = [];
  for (const k of schema.required) {
    if (!(k in obj)) errors.push({ keyword: 'required', missingKey: k });
  }
  if (obj.escalate_now === true && (!obj.escalation_reason || !obj.escalation_reason.length)) {
    errors.push({ keyword: 'conditional', message: 'escalate_now=true requires non-empty escalation_reason' });
  }
  return { ok: errors.length === 0, errors, validator: 'manual-fallback' };
}

async function main() {
  const argPhaseDir = process.argv[2];
  if (!argPhaseDir) fail('Usage: ai-diagnose.js <phase-dir>', 1);
  const phaseDir = path.resolve(argPhaseDir);
  if (!fs.existsSync(phaseDir) || !fs.statSync(phaseDir).isDirectory()) {
    fail(`Phase dir not found or not a directory: ${phaseDir}`, 1);
  }
  const phaseName = path.basename(phaseDir);
  // Project root is the directory that has a .planning sibling. Check the
  // phase-dir itself first (some smoke layouts put .planning inside the
  // phase-dir), then walk up. Cap at 4 levels.
  let projectRoot = phaseDir;
  if (!fs.existsSync(path.join(projectRoot, '.planning'))) {
    let cursor = phaseDir;
    for (let i = 0; i < 4; i++) {
      const candidate = path.dirname(cursor);
      if (fs.existsSync(path.join(candidate, '.planning'))) { projectRoot = candidate; break; }
      cursor = candidate;
      if (cursor === '/' || cursor === '') break;
    }
    // If still not found, fall back to the phase-dir's parent (preserves
    // prior behavior — better than `/` for notify.sh + events appends).
    if (!fs.existsSync(path.join(projectRoot, '.planning'))) {
      projectRoot = path.dirname(phaseDir);
    }
  }

  const context = buildContext({ phaseDir, projectRoot, phaseName });
  process.stderr.write(`[ai-diagnose] context bundled: ${context.length} chars\n`);

  // ---- Mock loader (single OR {primary, secondary} shapes) ----
  let mockPayload = null;
  if (process.env.AI_DIAGNOSE_MOCK) {
    try {
      const raw = JSON.parse(fs.readFileSync(process.env.AI_DIAGNOSE_MOCK, 'utf8'));
      mockPayload = raw;
      process.stderr.write(`[ai-diagnose] using AI_DIAGNOSE_MOCK=${process.env.AI_DIAGNOSE_MOCK}\n`);
    } catch (e) {
      fail(`AI_DIAGNOSE_MOCK read failed: ${e.message}`, 1);
    }
  }
  function mockFor(slot /* 'primary' | 'secondary' */) {
    if (!mockPayload) return null;
    if (mockPayload.primary || mockPayload.secondary) return mockPayload[slot] || null;
    return slot === 'primary' ? mockPayload : null;
  }

  // ---- One-shot diagnose: invoke ai-consult (or use mock) ----
  async function diagnoseOnce({ provider, model, slot }) {
    const mock = mockFor(slot);
    if (mock) return mock;
    try {
      const ai = require(path.join(AI_CONSULT_PATH, 'index.js'));
      const opts = { provider, content: context, reviewType: 'diagnosis' };
      if (model) opts.model = model;
      return await ai.reviewDocument(opts);
    } catch (e) {
      fail(`ai-consult call failed (${provider}${model ? '/' + model : ''}): ${e.message}`, 1);
    }
  }

  function parseDiagnose(r, slot) {
    if (!r || typeof r.feedback !== 'string') fail(`ai-consult returned no feedback (${slot})`, 1);
    let parsed;
    try { parsed = JSON.parse(r.feedback); }
    catch (e) {
      const num = nextDiagnosisNum(phaseDir);
      const rawPath = path.join(phaseDir, `ai-diagnosis-${num}.raw.txt`);
      fs.writeFileSync(rawPath, r.feedback, 'utf8');
      fail(`${slot} returned non-JSON; raw saved to ${rawPath}: ${e.message}`, 2);
    }
    return parsed;
  }

  function augment(parsed, providerLabel, modelLabel, costObj) {
    return {
      ...parsed,
      provider: providerLabel,
      model: modelLabel,
      timestamp: new Date().toISOString(),
      cost: {
        inputTokens: costObj?.inputTokens ?? 0,
        outputTokens: costObj?.outputTokens ?? 0,
        totalCost: costObj?.totalCost ?? 0,
        currency: costObj?.currency || 'USD',
      },
    };
  }

  // ---- Primary run (Gemini, or AI_DIAGNOSE_MODEL override for --variant) ----
  const primaryModel = process.env.AI_DIAGNOSE_MODEL || 'gemini-3.1-pro-preview';
  const primaryR = await diagnoseOnce({ provider: 'gemini', model: primaryModel, slot: 'primary' });
  const primaryParsed = parseDiagnose(primaryR, 'primary');
  let augmented = augment(primaryParsed, 'gemini', primaryModel, primaryR.cost);

  // ---- Second-opinion path: primary confidence === 'low' ----
  let secondaryAugmented = null;
  let secondOpinionUsed = false;
  let bothLow = false;
  let secondaryR = null;
  if (augmented.confidence === 'low') {
    console.log('ℹ️  Primary diagnosis low-confidence — consulting OpenAI gpt-5.2-pro for second opinion…');
    secondaryR = await diagnoseOnce({ provider: 'openai', model: 'gpt-5.2-pro', slot: 'secondary' });
    const secondaryParsed = parseDiagnose(secondaryR, 'secondary');
    secondaryAugmented = augment(secondaryParsed, 'openai', 'gpt-5.2-pro', secondaryR.cost);
    secondOpinionUsed = true;

    const confidenceRank = (c) => ({ high: 2, medium: 1, low: 0 }[c] ?? -1);
    if (confidenceRank(secondaryAugmented.confidence) > confidenceRank(augmented.confidence)) {
      // Swap: secondary becomes primary; original primary becomes -secondary.
      const rejected = augmented;
      augmented = {
        ...secondaryAugmented,
        second_opinion_used: true,
        primary_provider: 'gemini',
        primary_confidence: rejected.confidence,
      };
      secondaryAugmented = rejected; // saved as -secondary.json
    } else {
      // Secondary did not improve. Tag primary with second_opinion_used metadata.
      augmented = {
        ...augmented,
        second_opinion_used: true,
        primary_provider: 'gemini',
        primary_confidence: augmented.confidence,
      };
      if (secondaryAugmented.confidence === 'low') {
        bothLow = true;
        console.log('⚠️  Both providers low-confidence — escalating.');
        if (!augmented.escalate_now) {
          augmented.escalate_now = true;
          augmented.escalation_reason = augmented.escalation_reason && augmented.escalation_reason.length
            ? augmented.escalation_reason + ' · both providers low-confidence'
            : 'both providers low-confidence';
        }
      }
    }
  }

  // ---- Validate primary ----
  const v = validateSchema(augmented);
  if (!v.ok) {
    const num = nextDiagnosisNum(phaseDir);
    const rawPath = path.join(phaseDir, `ai-diagnosis-${num}.raw.txt`);
    fs.writeFileSync(rawPath, primaryR.feedback, 'utf8');
    console.error(`[ai-diagnose] schema validation FAILED (${v.validator}):`);
    for (const e of v.errors) console.error('  -', JSON.stringify(e));
    console.error(`[ai-diagnose] raw model output preserved at ${rawPath}`);
    process.exit(2);
  }

  // ---- Write files ----
  const num = nextDiagnosisNum(phaseDir);
  const outPath = path.join(phaseDir, `ai-diagnosis-${num}.json`);
  fs.writeFileSync(outPath, JSON.stringify(augmented, null, 2) + '\n', 'utf8');
  let secondaryPath = null;
  if (secondaryAugmented) {
    secondaryPath = path.join(phaseDir, `ai-diagnosis-${num}-secondary.json`);
    fs.writeFileSync(secondaryPath, JSON.stringify(secondaryAugmented, null, 2) + '\n', 'utf8');
  }

  // ---- Events ----
  const eventsPath = path.join(projectRoot, '.planning', 'events.jsonl');
  const eventsDirOk = fs.existsSync(path.dirname(eventsPath));
  if (eventsDirOk) {
    fs.appendFileSync(eventsPath, JSON.stringify({
      ts: new Date().toISOString(),
      event: 'ai_diagnostic_run',
      data: {
        phase: phaseName,
        diagnosis_num: Number(num),
        confidence: augmented.confidence,
        escalate_now: augmented.escalate_now,
        cost: augmented.cost.totalCost,
        model: augmented.model,
      },
    }) + '\n', 'utf8');

    if (secondOpinionUsed) {
      // `cost` here is the SECONDARY-only cost — keeps ai-stats sum trivial
      // (total = sum(ai_diagnostic_run.cost) + sum(ai_second_opinion_consulted.cost)).
      // After a swap, secondaryAugmented holds the rejected primary; otherwise
      // it holds the second-opinion response. Either way the secondary cost is
      // `secondaryR.cost.totalCost` — pre-swap reference.
      const secondaryCost = (secondaryR.cost?.totalCost) || 0;
      fs.appendFileSync(eventsPath, JSON.stringify({
        ts: new Date().toISOString(),
        event: 'ai_second_opinion_consulted',
        data: {
          phase: phaseName,
          diagnosis_num: Number(num),
          primary_provider: 'gemini',
          primary_confidence: primaryParsed.confidence,
          secondary_provider: 'openai',
          secondary_confidence: secondaryAugmented
            ? (secondaryAugmented.provider === 'openai' ? secondaryAugmented.confidence : augmented.confidence)
            : augmented.confidence,
          cost: secondaryCost,
          both_low: bothLow,
        },
      }) + '\n', 'utf8');
    }
  }

  // ---- Stdout summary ----
  const rc = augmented.root_cause.split('\n')[0].slice(0, 140);
  console.log(`Phase: ${phaseName}`);
  console.log(`Diagnosis #${num} saved to: ${outPath}`);
  if (secondaryPath) console.log(`Secondary saved to: ${secondaryPath}`);
  console.log(`Provider: ${augmented.provider} (${augmented.model})`);
  console.log(`Confidence: ${augmented.confidence}`);
  console.log(`Escalate: ${augmented.escalate_now ? 'yes' : 'no'}`);
  console.log(`Root cause: ${rc}`);
  const totalCost = (augmented.cost.totalCost || 0) + (secondaryAugmented?.cost?.totalCost || 0);
  console.log(`Cost: $${totalCost.toFixed(6)}${secondaryAugmented ? ' (primary + secondary)' : ''}`);

  // ---- Escalation routing ----
  // Two trigger paths:
  //   (a) escalate_now=true AND confidence=high — the model is highly
  //       confident the spec is fundamentally wrong (or repeated revisions
  //       failed). PM should halt the auto-revision cycle for this phase.
  //   (b) bothLow path above already forced escalate_now=true with the
  //       "both providers low-confidence" reason. Same notify flow.
  const shouldEscalate = (augmented.escalate_now === true && augmented.confidence === 'high') || bothLow;
  if (shouldEscalate) {
    const reason = augmented.escalation_reason || '(no reason given)';
    console.log(`🚨 ESCALATION RECOMMENDED — see ${outPath}. Reason: ${reason}. notify.sh invoked.`);

    if (eventsDirOk) {
      fs.appendFileSync(eventsPath, JSON.stringify({
        ts: new Date().toISOString(),
        event: 'ai_escalation_recommended',
        data: {
          phase: phaseName,
          diagnosis_num: Number(num),
          reason,
          confidence: augmented.confidence,
        },
      }) + '\n', 'utf8');
    }

    // Invoke notify.sh — best-effort, never blocks the diagnostic exit.
    const notifyBin = path.join(SCRIPT_DIR, 'notify.sh');
    if (fs.existsSync(notifyBin)) {
      try {
        const detail = `Reason: ${reason} · Confidence: ${augmented.confidence} · Diagnosis: ${outPath} · Model: ${augmented.model} · Cost: $${totalCost.toFixed(6)}`;
        execSync(
          `bash "${notifyBin}" ai_escalation_recommended "${projectRoot}" --phase "${phaseName}" --detail "${detail.replace(/"/g, '\\"')}"`,
          { stdio: 'inherit' }
        );
      } catch (e) {
        console.warn('[ai-diagnose] notify.sh call failed (non-fatal):', e.message);
      }
    }
  }
}

main().catch(e => fail(e.stack || e.message, 1));
