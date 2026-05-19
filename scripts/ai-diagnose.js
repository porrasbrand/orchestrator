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
//   AI_CONSULT_PATH   default: ~/awsc-new/awesome/ai-consult
//   AI_DIAGNOSE_MOCK  path to a JSON file with shape {feedback, usage, cost}.
//                     When set, bypasses the ai-consult call and returns the
//                     canned response. Used by integration-test.sh for
//                     deterministic + cost-free CI runs.

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
  // Project root is the .planning sibling — walk up looking for one. Cap at 4 levels.
  let projectRoot = phaseDir;
  for (let i = 0; i < 4; i++) {
    const candidate = path.dirname(projectRoot);
    if (fs.existsSync(path.join(candidate, '.planning'))) { projectRoot = candidate; break; }
    projectRoot = candidate;
    if (projectRoot === '/' || projectRoot === '') break;
  }

  const context = buildContext({ phaseDir, projectRoot, phaseName });
  process.stderr.write(`[ai-diagnose] context bundled: ${context.length} chars\n`);

  // Invoke ai-consult — OR use the AI_DIAGNOSE_MOCK env var to short-circuit
  // with a canned response. The mock path lets integration tests run
  // deterministically + cost-free. Mock file must be a JSON document with
  // shape: { feedback: "<JSON string>", usage: {...}, cost: {...} }.
  let r;
  if (process.env.AI_DIAGNOSE_MOCK) {
    try {
      r = JSON.parse(fs.readFileSync(process.env.AI_DIAGNOSE_MOCK, 'utf8'));
      process.stderr.write(`[ai-diagnose] using AI_DIAGNOSE_MOCK=${process.env.AI_DIAGNOSE_MOCK}\n`);
    } catch (e) {
      fail(`AI_DIAGNOSE_MOCK read failed: ${e.message}`, 1);
    }
  } else {
    try {
      const ai = require(path.join(AI_CONSULT_PATH, 'index.js'));
      r = await ai.reviewDocument({
        provider: 'gemini',
        content: context,
        reviewType: 'diagnosis',
      });
    } catch (e) {
      fail(`ai-consult call failed: ${e.message}`, 1);
    }
  }
  if (!r || typeof r.feedback !== 'string') fail('ai-consult returned no feedback', 1);

  // Parse model JSON.
  const num = nextDiagnosisNum(phaseDir);
  const rawPath = path.join(phaseDir, `ai-diagnosis-${num}.raw.txt`);
  let parsed;
  try {
    parsed = JSON.parse(r.feedback);
  } catch (e) {
    fs.writeFileSync(rawPath, r.feedback, 'utf8');
    fail(`Model returned non-JSON; raw saved to ${rawPath}: ${e.message}`, 2);
  }

  // Augment with metadata.
  const augmented = {
    ...parsed,
    provider: 'gemini',
    model: process.env.GEMINI_MODEL_OVERRIDE || 'gemini-3.1-pro-preview',
    timestamp: new Date().toISOString(),
    cost: {
      inputTokens: r.cost?.inputTokens ?? r.usage?.inputTokens ?? 0,
      outputTokens: r.cost?.outputTokens ?? r.usage?.outputTokens ?? 0,
      totalCost: r.cost?.totalCost ?? 0,
      currency: r.cost?.currency || 'USD',
    },
  };

  // Validate.
  const v = validateSchema(augmented);
  if (!v.ok) {
    fs.writeFileSync(rawPath, r.feedback, 'utf8');
    console.error(`[ai-diagnose] schema validation FAILED (${v.validator}):`);
    for (const e of v.errors) console.error('  -', JSON.stringify(e));
    console.error(`[ai-diagnose] raw model output preserved at ${rawPath}`);
    process.exit(2);
  }

  // Write the diagnosis JSON.
  const outPath = path.join(phaseDir, `ai-diagnosis-${num}.json`);
  fs.writeFileSync(outPath, JSON.stringify(augmented, null, 2) + '\n', 'utf8');

  // Append event to .planning/events.jsonl (if .planning exists).
  const eventsPath = path.join(projectRoot, '.planning', 'events.jsonl');
  if (fs.existsSync(path.dirname(eventsPath))) {
    const event = {
      ts: new Date().toISOString(),
      event: 'ai_diagnostic_run',
      data: {
        phase: phaseName,
        diagnosis_num: Number(num),
        confidence: augmented.confidence,
        escalate_now: augmented.escalate_now,
        cost: augmented.cost.totalCost,
      },
    };
    fs.appendFileSync(eventsPath, JSON.stringify(event) + '\n', 'utf8');
  }

  // Stdout summary.
  const rc = augmented.root_cause.split('\n')[0].slice(0, 140);
  console.log(`Phase: ${phaseName}`);
  console.log(`Diagnosis #${num} saved to: ${outPath}`);
  console.log(`Confidence: ${augmented.confidence}`);
  console.log(`Escalate: ${augmented.escalate_now ? 'yes' : 'no'}`);
  console.log(`Root cause: ${rc}`);
  console.log(`Cost: $${augmented.cost.totalCost.toFixed(6)}`);
}

main().catch(e => fail(e.stack || e.message, 1));
