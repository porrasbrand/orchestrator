// orch-response-watcher.mjs — resident-PM response notifier (orch-migration-01).
//
// Polls the LOCAL worker queue.db every ~30s. For each task_id recorded in the
// dispatch-ledger, once its row reaches a terminal status (processed/failed) and
// has NOT been notified before, it injects the literal line:
//     check response <id>\n
// into the 'orchestrator' tmux session, so the resident PM wakes up and reads
// the result via scripts/get-response.sh.
//
// Guarantees:
//   • Never double-notifies — notified ids persist in ~/.orchestrator/notified-ids.txt
//     and are reloaded on restart (idempotent across restarts).
//   • Ignores non-ledger rows entirely — only ledger task_ids are ever inspected.
//   • If the 'orchestrator' tmux session is not up yet, it skips WITHOUT marking
//     the id notified, so the nudge is delivered once the PM session exists.
//
// Read-only against queue.db (imports queue-db.js, calls getMessage only).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFile, execFileSync } from 'node:child_process';

const HOME = os.homedir();
const STATE_DIR = process.env.ORCH_STATE_DIR || path.join(HOME, '.orchestrator');
const LEDGER = path.join(STATE_DIR, 'dispatch-ledger.jsonl');
const NOTIFIED_FILE = path.join(STATE_DIR, 'notified-ids.txt');
const SLACK_APP = process.env.ORCH_HETZNER_SLACK_APP || path.join(HOME, 'awsc-new/awesome/slack-app');
const SESSION = process.env.ORCH_PM_SESSION || 'orchestrator';
const POLL_MS = Number(process.env.ORCH_WATCH_INTERVAL_MS || 30000);
const TERMINAL = new Set(['processed', 'failed']);
// Boot-grace marker written by run-orchestrator.sh. While the PM's Claude Code
// TUI is still booting it is NOT accepting input — keystrokes sent now are
// swallowed. Honor the grace window (same discipline as the keepalive crons):
// during it we skip WITHOUT marking notified, so delivery is retried once the
// TUI is interactive.
const GRACE_FILE = process.env.ORCH_PM_GRACE_FILE ||
  path.join(HOME, 'awsc-new/awesome/orchestrator/.boot-grace-until');
function withinBootGrace() {
  try {
    const until = Number(fs.readFileSync(GRACE_FILE, 'utf8').trim());
    return Number.isFinite(until) && (Date.now() / 1000) < until;
  } catch { return false; }
}

fs.mkdirSync(STATE_DIR, { recursive: true });

// --- Response materializer (orch-migration-02) ---
// For every ledger-matched terminal task we ALSO drop a response file into a
// local shim that mirrors lipo's super-agent layout, so the resident pm-daemon
// (which scans $SUPER_AGENT_DIR/tasks/responses/new/) has a file to claim if the
// interactive PM doesn't archive it within PM_GRACE_PERIOD. File shape matches
// lipo's response-fetcher exactly: {id, task, response, fetchedAt}.
const SHIM_ROOT = process.env.ORCH_SA_SHIM || path.join(STATE_DIR, 'superagent-shim');
const SHIM_RESP = path.join(SHIM_ROOT, 'tasks', 'responses');
const SHIM_DIRS = {
  new: path.join(SHIM_RESP, 'new'),
  claimed: path.join(SHIM_RESP, 'claimed'),
  archive: path.join(SHIM_RESP, 'archive'),
  failed: path.join(SHIM_RESP, 'failed'),
};
for (const d of Object.values(SHIM_DIRS)) fs.mkdirSync(d, { recursive: true });

// Idempotent: skip if <id>.json already exists in ANY of the four dirs (i.e. it
// was already materialized, claimed by the daemon, archived by the PM, or failed).
function shimExists(id) {
  const name = `${id}.json`;
  return Object.values(SHIM_DIRS).some(d => fs.existsSync(path.join(d, name)));
}
function materializeShim(id, row) {
  if (shimExists(id)) return false;
  const payload = {
    id: Number(id),
    task: String(row.task ?? row.query ?? ''),
    response: String(row.response ?? ''),
    fetchedAt: new Date().toISOString(),
  };
  const target = path.join(SHIM_DIRS.new, `${id}.json`);
  const tmp = `${target}.tmp.${process.pid}.${Date.now()}`;
  fs.writeFileSync(tmp, JSON.stringify(payload, null, 2));
  fs.renameSync(tmp, target);       // atomic publish into new/
  console.log(`[watcher] materialized shim response new/${id}.json`);
  return true;
}

// Persisted set of already-notified task ids (survives restarts).
const notified = new Set();
function loadNotified() {
  try {
    for (const line of fs.readFileSync(NOTIFIED_FILE, 'utf8').split('\n')) {
      const id = line.trim();
      if (id) notified.add(id);
    }
  } catch { /* first run: no file yet */ }
}
function markNotified(id) {
  notified.add(String(id));
  fs.appendFileSync(NOTIFIED_FILE, String(id) + '\n');
}

// Ledger task_ids (strings). Missing/partial ledger → empty list, never throws.
function ledgerIds() {
  let raw;
  try { raw = fs.readFileSync(LEDGER, 'utf8'); } catch { return []; }
  const ids = [];
  for (const line of raw.split('\n')) {
    const s = line.trim();
    if (!s) continue;
    try { const o = JSON.parse(s); if (o && o.task_id != null) ids.push(String(o.task_id)); }
    catch { /* skip malformed ledger line */ }
  }
  return ids;
}

function sessionUp() {
  try { execFileSync('tmux', ['has-session', '-t', `=${SESSION}`], { stdio: 'ignore' }); return true; }
  catch { return false; }
}
function inject(id) {
  return new Promise((resolve) => {
    execFile('tmux', ['send-keys', '-t', SESSION, `check response ${id}`, 'Enter'], (err) => resolve(!err));
  });
}

let getMessage, getDistinctQueueNames;
async function loadDb() {
  const mod = await import(path.join(SLACK_APP, 'queue-db.js'));
  getMessage = mod.getMessage;
  getDistinctQueueNames = mod.getDistinctQueueNames;
}
function findRow(idStr) {
  const id = Number(idStr);
  const queues = (getDistinctQueueNames?.() || ['hetzner', 'slack', 'ppc-control']);
  for (const q of queues) { const m = getMessage(id, q); if (m) return m; }
  return null;
}

async function tick() {
  const ids = ledgerIds();
  if (ids.length === 0) return;
  let pending = [];
  for (const id of ids) {
    const row = findRow(id);
    if (!row || !TERMINAL.has(row.status)) continue; // not complete yet
    // Materialize the daemon shim for EVERY terminal ledger task, independent of
    // tmux injection / boot-grace — the daemon is the fallback when the PM is
    // down, so the file must exist even if we can't nudge the session.
    materializeShim(id, row);
    if (notified.has(id)) continue;               // already nudged the tmux PM
    pending.push(id);
  }
  if (pending.length === 0) return;
  if (!sessionUp()) {
    console.log(`[watcher] ${pending.length} ready but tmux '${SESSION}' is down — will retry`);
    return;                                        // do NOT mark notified
  }
  if (withinBootGrace()) {
    console.log(`[watcher] ${pending.length} ready but PM still in boot-grace — will retry`);
    return;                                        // do NOT mark notified
  }
  for (const id of pending) {
    const ok = await inject(id);
    if (ok) { markNotified(id); console.log(`[watcher] notified PM: check response ${id}`); }
    else console.error(`[watcher] tmux send-keys failed for ${id} — will retry`);
  }
}

(async () => {
  loadNotified();
  await loadDb();
  console.log(`[watcher] up. session=${SESSION} poll=${POLL_MS}ms ledger=${LEDGER} notified_loaded=${notified.size}`);
  const run = () => tick().catch(e => console.error('[watcher] tick error:', e.message));
  await run();
  setInterval(run, POLL_MS);
})();
