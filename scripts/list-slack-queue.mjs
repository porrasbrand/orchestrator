// list-slack-queue.mjs — scoped lister for the resident PM's Slack queue.
//
// Prints ONLY pending rows for queue_name='orchestrator' (the rows awesome-bridge
// enqueues from #orchestrator, source='slack-awesome'). The shared
// slack-app/queue-helper.js `list` is hardcoded to slack+hetzner+ppc-control, so
// this gives the PM a focused view of its Slack inbox. claim / respond-superagent
// still go through slack-app/queue-helper.js (they resolve the queue by id).
//
// Read-only. Imports the sanctioned queue-db.js by absolute path — never raw SQL.
import os from 'node:os';
import path from 'node:path';

const SLACK_APP = process.env.ORCH_HETZNER_SLACK_APP || path.join(os.homedir(), 'awsc-new/awesome/slack-app');
const { getPendingMessages } = await import(path.join(SLACK_APP, 'queue-db.js'));

const rows = getPendingMessages('orchestrator');
console.log('================================================================');
console.log(`📬 orchestrator (Slack) pending: ${rows.length}`);
console.log('================================================================');
for (const m of rows) {
  console.log(`\n[${m.status}] ID: ${m.id}`);
  console.log(`  user: ${m.user}  channel: ${m.channel}  thread: ${m.threadTs}`);
  console.log('  ' + String(m.task || m.query || '').replace(/\n/g, '\n  ').slice(0, 1500));
}
if (rows.length === 0) console.log('\n✅ empty — no Slack tasks.');
console.log('\nProcess each: node ~/awsc-new/awesome/slack-app/queue-helper.js claim <id>  →  act as PM  →  node ~/awsc-new/awesome/slack-app/queue-helper.js respond-superagent <id> "<slack-mrkdwn reply>"');
