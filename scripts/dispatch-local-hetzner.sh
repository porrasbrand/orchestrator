#!/usr/bin/env bash
# dispatch-local-hetzner.sh — LOCAL sibling of super-agent/scripts/add-task.sh.
#
# When the PM runs ON the hetzner box, there is no SSH hop: we insert straight
# into the local worker queue (~/awsc-new/awesome/slack-app/queue.db,
# queue_name='hetzner') via the SAME addMessage() path add-task.sh reaches
# remotely. Output format is byte-compatible with add-task.sh so queue-phase.sh
# parses it identically:
#     ID: <task_id>
#     Task queued: <task_id>
#
# Usage:
#   dispatch-local-hetzner.sh [--repo <id>] [--priority <n>] "<task text>"
#
# Does NOT edit any slack-app file — it only require()s queue-db.js.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib-host.sh"

SLACK_APP="$ORCH_HETZNER_SLACK_APP"
QUEUE_DB="$ORCH_HETZNER_QUEUE_DB"

REPO=""
PRIORITY=""
TASK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)     REPO="$2"; shift 2 ;;
    --priority) PRIORITY="$2"; shift 2 ;;
    --)         shift; TASK="$*"; break ;;
    *)          TASK="$1"; shift; break ;;
  esac
done

if [[ -z "$TASK" ]]; then
  echo "Usage: $0 [--repo <id>] [--priority <n>] \"<task text>\"" >&2
  exit 1
fi
if [[ ! -f "$SLACK_APP/queue-db.js" ]]; then
  echo "❌ local queue-db.js not found at $SLACK_APP (are we really on hetzner?)" >&2
  exit 1
fi

TASK_ID="$(date +%s%3N)"
CREATED="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
TMP="/tmp/orch-local-task-${TASK_ID}.json"

# Build task JSON with jq (handles all escaping) — mirrors add-task.sh's shape,
# plus repo_id/priority for lock-lane routing. query AND task both set so the
# worker's `list` shows the text and the worker reads `task`.
jq -n \
  --arg id "$TASK_ID" \
  --arg task "$TASK" \
  --arg created "$CREATED" \
  --arg repo "$REPO" \
  --arg priority "$PRIORITY" \
  '{
     id: ($id | tonumber),
     task: $task,
     query: $task,
     user: "super-agent",
     channel: "super-agent",
     created: $created,
     timestamp: $created
   }
   + (if $repo == "" then {} else {repo_id: $repo} end)
   + (if $priority == "" then {} else {priority: ($priority | tonumber)} end)' > "$TMP"

echo "➕ Queuing task for >>hetzner (local dispatch, no SSH)..."
echo "Task: ${TASK:0:80}..."
echo "ID: $TASK_ID"
echo ""

# Insert via the exact addMessage path add-task.sh uses remotely, then ACK.
QUEUE_RESULT="$(cd "$SLACK_APP" && node -e "
  const fs = require('fs');
  const task = JSON.parse(fs.readFileSync('$TMP', 'utf8'));
  import('./queue-db.js').then(qdb => {
    qdb.addMessage('hetzner', task);   // addMessage logs '[QueueDB] Added message ...'
    const back = qdb.getMessage(task.id, 'hetzner');
    console.log(back ? 'ACK' : 'MISSING');
    fs.unlinkSync('$TMP');
  }).catch(e => { console.error('Error:', e.message); process.exit(1); });
" 2>&1)"
QUEUE_EXIT=$?
rm -f "$TMP"

if [[ $QUEUE_EXIT -ne 0 ]]; then
  echo "❌ Failed to queue task locally" >&2
  echo "Error: $QUEUE_RESULT" >&2
  exit 1
fi

echo "$QUEUE_RESULT" | grep -v '^ACK$' | grep -v '^MISSING$' || true
echo "Task queued: $TASK_ID"
echo ""
if echo "$QUEUE_RESULT" | grep -q '^ACK$'; then
  echo "✅ Task queued directly to local Hetzner SQLite (delivery confirmed)"
else
  echo "⚠️  Task inserted but delivery ACK unclear — check manually if needed"
fi
