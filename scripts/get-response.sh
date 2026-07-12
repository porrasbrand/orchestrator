#!/usr/bin/env bash
# get-response.sh <task-id> — print the response text for a queued task.
#
# Resident (hetzner) PM helper: reads the LOCAL worker queue.db and prints the
# `response` column for <task-id>, regardless of which queue the row is in.
# Read-only — require()s queue-db.js, never writes.
#
# Exit codes: 0 = printed a response; 2 = row not found; 3 = row found but no
# response yet (still pending/processing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib-host.sh"

TASK_ID="${1:?Usage: get-response.sh <task-id>}"
SLACK_APP="$ORCH_HETZNER_SLACK_APP"

if [[ ! -f "$SLACK_APP/queue-db.js" ]]; then
  echo "❌ local queue-db.js not found at $SLACK_APP" >&2
  exit 1
fi

cd "$SLACK_APP"
exec node -e "
  const id = Number('$TASK_ID');
  import('./queue-db.js').then(qdb => {
    const queues = (qdb.getDistinctQueueNames?.() || ['hetzner','slack','ppc-control']);
    let row = null;
    for (const q of queues) { const m = qdb.getMessage(id, q); if (m) { row = m; break; } }
    if (!row) { console.error('not found: ' + id); process.exit(2); }
    if (row.response == null || row.response === '') {
      console.error('no response yet (status=' + row.status + ')');
      process.exit(3);
    }
    process.stdout.write(row.response + '\n');
  }).catch(e => { console.error('Error:', e.message); process.exit(1); });
"
