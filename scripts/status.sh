#!/bin/bash
# Show orchestration status for a project
# Usage: ./scripts/status.sh <project-path>

PROJECT_PATH="${1:?Usage: status.sh <project-path>}"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ No .planning/status.json found at $PROJECT_PATH"
  exit 1
fi

echo "📊 Orchestration Status"
echo "======================"
echo ""

# Parse status.json with node
node -e "
  const status = JSON.parse(require('fs').readFileSync('$STATUS_FILE', 'utf8'));
  console.log('Project:', status.project);
  console.log('Status:', status.status);
  console.log('Current Phase:', status.current_phase || '(none)');
  console.log('Progress:', status.metrics.phases_complete + '/' + status.metrics.phases_total, 'phases');
  console.log('Total Revisions:', status.metrics.total_revisions);
  console.log('');
  console.log('Phases:');
  for (const [name, phase] of Object.entries(status.phases)) {
    const icon = phase.status === 'complete' ? '✅' :
                 phase.status === 'queued' ? '⏳' :
                 phase.status === 'pending' ? '⬜' :
                 phase.status === 'revision_failed' ? '❌' :
                 phase.status === 'blocked' ? '🚫' :
                 phase.status === 'skipped' ? '⏭️' : '🔄';
    const rev = phase.revisions > 0 ? ' (rev ' + phase.revisions + ')' : '';
    const commit = phase.commit ? ' [' + phase.commit + ']' : '';
    console.log('  ' + icon + ' ' + name + ': ' + phase.status + rev + commit);
  }
" 2>/dev/null

# Recent events
if [ -f "$EVENTS_FILE" ]; then
  echo ""
  echo "Recent Events (last 10):"
  tail -10 "$EVENTS_FILE" | node -e "
    const lines = require('fs').readFileSync('/dev/stdin', 'utf8').trim().split('\n');
    for (const line of lines) {
      try {
        const e = JSON.parse(line);
        const time = e.ts.replace('T',' ').replace('Z','');
        console.log('  ' + time + ' | ' + e.event + (e.data?.phase ? ' (' + e.data.phase + ')' : ''));
      } catch(e) {}
    }
  " 2>/dev/null
fi
