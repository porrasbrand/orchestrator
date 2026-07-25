#!/usr/bin/env node
// pm-daemon.js — Resident PM daemon (r1-03).
//
// Watches $SUPER_AGENT_DIR/tasks/responses/new/ and, after a grace period,
// claims each response that matches the r1-01 dispatch-ledger by atomic
// rename to `claimed/`, then spawns `pm-iterate.sh --trigger response
// --response-file <claimed>` for that project. Also runs a periodic tick that
// pokes actionable phases (`pending` / `specified` / `verifying`, plus
// `queued` beyond PM_STALL_TIMEOUT).
//
// Single-flight: pm-iterate runs one-at-a-time across all projects — the
// per-project flock in pm-iterate.sh is defence-in-depth, not the primary
// concurrency guard here.
//
// Env knobs (all optional):
//   ORCH_STATE_DIR       ($HOME/.orchestrator)
//   SUPER_AGENT_DIR      ($HOME/awesome/super-agent)
//   PM_GRACE_PERIOD      (600 s)
//   PM_POLL_INTERVAL     (60 s)   — responses scan cadence
//   PM_TICK_INTERVAL     (900 s)  — project tick cadence
//   PM_STALL_TIMEOUT     (14400 s) — queued-phase stall threshold
//   PM_MAX_ATTEMPTS      (2)      — attempts per claimed response before give-up
//   PM_ITERATE_BIN       (<repo>/scripts/pm-iterate.sh)
// CLI:
//   --once  run exactly one scan + tick cycle synchronously, then exit.
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

// ---- config ----
const HOME = os.homedir();
const REPO_DIR = path.resolve(__dirname, '..');
const STATE_DIR = process.env.ORCH_STATE_DIR || path.join(HOME, '.orchestrator');
const SUPER_AGENT_DIR = process.env.SUPER_AGENT_DIR || path.join(HOME, 'awesome', 'super-agent');
const GRACE_PERIOD = numEnv('PM_GRACE_PERIOD', 600, 0);   // 0 is legal — claim as soon as the response appears
const POLL_INTERVAL = numEnv('PM_POLL_INTERVAL', 60);
const TICK_INTERVAL = numEnv('PM_TICK_INTERVAL', 900);
const STALL_TIMEOUT = numEnv('PM_STALL_TIMEOUT', 14400);
const MAX_ATTEMPTS = numEnv('PM_MAX_ATTEMPTS', 2);
const PM_ITERATE_BIN = process.env.PM_ITERATE_BIN || path.join(REPO_DIR, 'scripts', 'pm-iterate.sh');
const RESOLUTIONS_INTERVAL = numEnv('PM_RESOLUTIONS_INTERVAL', 120);
const PM_RESOLUTIONS_BIN = process.env.PM_RESOLUTIONS_BIN || path.join(REPO_DIR, 'scripts', 'slack-poll-resolutions.sh');

const RESP_NEW = path.join(SUPER_AGENT_DIR, 'tasks', 'responses', 'new');
const RESP_CLAIMED = path.join(SUPER_AGENT_DIR, 'tasks', 'responses', 'claimed');
const RESP_ARCHIVE = path.join(SUPER_AGENT_DIR, 'tasks', 'responses', 'archive');
const RESP_FAILED = path.join(SUPER_AGENT_DIR, 'tasks', 'responses', 'failed');

const LEDGER_FILE = path.join(STATE_DIR, 'dispatch-ledger.jsonl');
const REGISTRY_FILE = path.join(STATE_DIR, 'active-projects.json');
const PAUSED_FILE = path.join(STATE_DIR, 'paused');
const DAEMON_STATE_FILE = path.join(STATE_DIR, 'daemon-state.json');

// ---- utils ----
function numEnv(name, def, min = 1) {
    const raw = process.env[name];
    if (raw === undefined || raw === '') return def;
    const v = Number(raw);
    if (!Number.isFinite(v) || v < min) {
        console.warn(new Date().toISOString(), '[pm-daemon]',
            `ignoring invalid ${name}=${JSON.stringify(raw)} (must be a number >= ${min}); using default ${def}`);
        return def;
    }
    return v;
}

function log(...args) {
    console.log(new Date().toISOString(), '[pm-daemon]', ...args);
}

function ensureDir(p) {
    fs.mkdirSync(p, { recursive: true });
}

function safeReadJSON(p, fallback) {
    try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return fallback; }
}

function safeReadJSONL(p) {
    if (!fs.existsSync(p)) return [];
    const lines = fs.readFileSync(p, 'utf8').split('\n');
    const out = [];
    for (const line of lines) {
        const s = line.trim();
        if (!s) continue;
        try { out.push(JSON.parse(s)); } catch { /* skip bad line */ }
    }
    return out;
}

function atomicWriteJSON(target, obj) {
    const tmp = target + '.tmp.' + process.pid + '.' + Date.now();
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2));
    fs.renameSync(tmp, target);
}

function loadLedger() {
    const map = new Map();
    for (const row of safeReadJSONL(LEDGER_FILE)) {
        if (row && row.task_id) map.set(String(row.task_id), row);
    }
    return map;
}

function loadRegistry() {
    const arr = safeReadJSON(REGISTRY_FILE, []);
    const byName = new Map();
    for (const e of Array.isArray(arr) ? arr : []) {
        if (e && e.name) byName.set(e.name, e);
    }
    return byName;
}

function loadDaemonState() {
    return safeReadJSON(DAEMON_STATE_FILE, { claims: {} });
}
function saveDaemonState(s) {
    ensureDir(path.dirname(DAEMON_STATE_FILE));
    atomicWriteJSON(DAEMON_STATE_FILE, s);
}

function appendEventTo(planningDir, event) {
    if (!fs.existsSync(planningDir)) return;
    const line = JSON.stringify(event) + '\n';
    fs.appendFileSync(path.join(planningDir, 'events.jsonl'), line);
}

function runPmIterate(projectPath, extraArgs) {
    log('spawn:', PM_ITERATE_BIN, projectPath, ...extraArgs);
    const r = spawnSync(PM_ITERATE_BIN, [projectPath, ...extraArgs], {
        stdio: ['ignore', 'pipe', 'pipe'],
        env: process.env,
        cwd: REPO_DIR,
    });
    const stdout = (r.stdout || '').toString();
    const stderr = (r.stderr || '').toString();
    if (stdout.trim()) log('pm-iterate stdout:', stdout.trim());
    if (stderr.trim()) log('pm-iterate stderr:', stderr.trim());
    return { code: r.status ?? 1, stdout, stderr };
}

function moveFile(src, destDir) {
    ensureDir(destDir);
    const dest = path.join(destDir, path.basename(src));
    fs.renameSync(src, dest);
    return dest;
}

// ---- claim step (atomic rename) ----
function tryClaim(taskId) {
    const src = path.join(RESP_NEW, taskId + '.json');
    ensureDir(RESP_CLAIMED);
    const dest = path.join(RESP_CLAIMED, taskId + '.json');
    try {
        fs.renameSync(src, dest);
        return dest;
    } catch (e) {
        if (e.code === 'ENOENT') return null; // raced
        throw e;
    }
}

// ---- scan cycle ----
function scanCycle() {
    if (fs.existsSync(PAUSED_FILE)) {
        log('paused — skipping scan cycle');
        return;
    }
    ensureDir(RESP_NEW);
    ensureDir(RESP_CLAIMED);

    const ledger = loadLedger();
    const registry = loadRegistry();
    const now = Date.now();

    // 1. Claim ledger-matched, grace-elapsed files from new/.
    let entries = [];
    try { entries = fs.readdirSync(RESP_NEW); } catch { entries = []; }
    for (const name of entries) {
        if (!name.endsWith('.json')) continue;
        const taskId = name.slice(0, -5);
        const row = ledger.get(taskId);
        if (!row) continue;                       // not a ledger match
        const proj = registry.get(row.project);
        if (!proj || proj.active === false) continue;  // deactivated / unknown
        let mtime;
        try { mtime = fs.statSync(path.join(RESP_NEW, name)).mtimeMs; }
        catch { continue; }
        const ageS = (now - mtime) / 1000;
        if (ageS < GRACE_PERIOD) continue;
        const claimedPath = tryClaim(taskId);
        if (claimedPath) log('claimed:', taskId, '→', claimedPath);
    }

    // 2. Process every file sitting in claimed/ (incl. leftovers from prior cycles).
    let claimed = [];
    try { claimed = fs.readdirSync(RESP_CLAIMED); } catch { claimed = []; }
    claimed = claimed.filter(n => n.endsWith('.json')).sort();

    for (const name of claimed) {
        const taskId = name.slice(0, -5);
        const row = ledger.get(taskId);
        if (!row) { log('skipping claimed file without ledger row:', name); continue; }
        const proj = registry.get(row.project);
        if (!proj) { log('skipping claimed file for unknown project:', name); continue; }
        const claimedPath = path.join(RESP_CLAIMED, name);
        const { code, stdout } = runPmIterate(proj.local_path, [
            '--trigger', 'response', '--response-file', claimedPath
        ]);

        // Disposition
        const skipped = /^SKIP:/m.test(stdout);
        if (code === 0 && !skipped) {
            moveFile(claimedPath, RESP_ARCHIVE);
            const s = loadDaemonState();
            delete s.claims[taskId];
            saveDaemonState(s);
            log('archived:', taskId, '(exit 0)');
        } else if (code === 0 && skipped) {
            log('claim left in place (pm-iterate SKIP):', taskId);
        } else {
            // failure: bump attempts, retry OR give up
            const s = loadDaemonState();
            const prev = (s.claims[taskId] && s.claims[taskId].attempts) || 0;
            const attempts = prev + 1;
            s.claims[taskId] = {
                attempts,
                last_exit: code,
                last_ts: new Date().toISOString(),
            };
            saveDaemonState(s);
            log('failure:', taskId, 'attempts=' + attempts + '/' + MAX_ATTEMPTS + ', exit=' + code);
            if (attempts >= MAX_ATTEMPTS) {
                moveFile(claimedPath, RESP_FAILED);
                appendEventTo(path.join(proj.local_path, '.planning'), {
                    ts: new Date().toISOString(),
                    event: 'pm_daemon_gave_up',
                    data: {
                        task_id: taskId,
                        phase: row.phase,
                        attempts,
                        last_exit: code,
                    },
                });
                delete s.claims[taskId];
                saveDaemonState(s);
                log('GAVE UP on', taskId, '→ failed/');
            }
        }
    }
}

// ---- tick cycle ----
function newestPhaseQueuedTs(planningDir, phase) {
    const events = safeReadJSONL(path.join(planningDir, 'events.jsonl'));
    let latest = null;
    for (const e of events) {
        if (e && e.event === 'phase_queued' && e.data && e.data.phase === phase && e.ts) {
            if (!latest || e.ts > latest) latest = e.ts;
        }
    }
    return latest;
}

function tickCycle() {
    if (fs.existsSync(PAUSED_FILE)) {
        log('paused — skipping tick cycle');
        return;
    }
    const registry = loadRegistry();
    const now = Date.now();
    const poked = [];
    const skipped = [];

    for (const [name, proj] of registry.entries()) {
        if (proj.active === false) { skipped.push(name + ':inactive'); continue; }
        const planningDir = path.join(proj.local_path, '.planning');
        const status = safeReadJSON(path.join(planningDir, 'status.json'), null);
        if (!status) { skipped.push(name + ':no-status'); continue; }

        const currentPhase = status.current_phase;
        // Phase status may live at status.phases[currentPhase].status OR status.status.
        let phaseStatus = null;
        if (currentPhase && status.phases && status.phases[currentPhase]) {
            phaseStatus = status.phases[currentPhase].status;
        }
        if (!phaseStatus) phaseStatus = status.status || null;

        let poke = false, reason = '';
        if (phaseStatus === 'pending' || phaseStatus === 'specified' || phaseStatus === 'verifying') {
            poke = true; reason = phaseStatus;
        } else if (phaseStatus === 'queued' && currentPhase) {
            const ts = newestPhaseQueuedTs(planningDir, currentPhase);
            if (ts) {
                const ageS = (now - Date.parse(ts)) / 1000;
                if (ageS > STALL_TIMEOUT) { poke = true; reason = 'queued-stall(' + Math.floor(ageS) + 's)'; }
            }
        }

        if (!poke) { skipped.push(name + ':' + (phaseStatus || 'unknown')); continue; }
        const { code } = runPmIterate(proj.local_path, ['--trigger', 'tick']);
        poked.push(name + ':' + reason + '(exit=' + code + ')');
    }

    log('tick summary — poked:', poked.length ? poked.join(', ') : '(none)',
        '| skipped:', skipped.length ? skipped.join(', ') : '(none)');
}

// ---- resolutions cycle (r2-05 Slack inbound polling) ----
function resolutionsCycle() {
    if (fs.existsSync(PAUSED_FILE)) {
        log('paused — skipping resolutions cycle');
        return;
    }
    if (!fs.existsSync(PM_RESOLUTIONS_BIN)) return; // bare install, silent
    try {
        const st = fs.statSync(PM_RESOLUTIONS_BIN);
        if (!(st.mode & 0o111)) return; // not executable
    } catch { return; }
    log('spawn (resolutions):', PM_RESOLUTIONS_BIN);
    const r = spawnSync(PM_RESOLUTIONS_BIN, [], {
        stdio: ['ignore', 'pipe', 'pipe'],
        env: process.env,
        cwd: REPO_DIR,
    });
    const stdout = (r.stdout || '').toString().trim();
    const stderr = (r.stderr || '').toString().trim();
    if (stdout) log('resolutions stdout:', stdout.slice(0, 400));
    if (stderr) log('resolutions stderr:', stderr.slice(0, 400));
    log('resolutions exit=' + (r.status ?? 1));
}

// ---- main ----
function main() {
    ensureDir(STATE_DIR);
    log('pm-daemon starting; state=' + STATE_DIR, 'super_agent=' + SUPER_AGENT_DIR,
        'grace=' + GRACE_PERIOD + 's', 'poll=' + POLL_INTERVAL + 's', 'tick=' + TICK_INTERVAL + 's',
        'resolutions=' + RESOLUTIONS_INTERVAL + 's', 'max_attempts=' + MAX_ATTEMPTS);

    const once = process.argv.includes('--once');
    if (once) {
        log('--once mode: single scan + tick + resolutions cycle');
        try { scanCycle(); } catch (e) { log('scan error:', e && e.stack || e); }
        try { tickCycle(); } catch (e) { log('tick error:', e && e.stack || e); }
        try { resolutionsCycle(); } catch (e) { log('resolutions error:', e && e.stack || e); }
        return;
    }

    // Daemon mode: setInterval loops. Errors caught per-cycle.
    setInterval(() => {
        try { scanCycle(); } catch (e) { log('scan error:', e && e.stack || e); }
    }, POLL_INTERVAL * 1000);
    setInterval(() => {
        try { tickCycle(); } catch (e) { log('tick error:', e && e.stack || e); }
    }, TICK_INTERVAL * 1000);
    setInterval(() => {
        try { resolutionsCycle(); } catch (e) { log('resolutions error:', e && e.stack || e); }
    }, RESOLUTIONS_INTERVAL * 1000);
    // Immediate first cycles so pm2 restarts pick up work fast.
    try { scanCycle(); } catch (e) { log('scan error:', e && e.stack || e); }
    try { tickCycle(); } catch (e) { log('tick error:', e && e.stack || e); }
    try { resolutionsCycle(); } catch (e) { log('resolutions error:', e && e.stack || e); }
}

main();
