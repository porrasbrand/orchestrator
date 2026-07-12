#!/usr/bin/env bash
# keepalive-orchestrator.sh — Slack-queue pickup for the resident orchestrator PM.
#
# Mirrors keepalive-awesome-kurt.sh, scoped to:
#   queue_name = 'orchestrator'   (rows the awesome-bridge enqueues from #orchestrator)
#   session    = 'orchestrator'   (the resident PM tmux)
#
# Scheduled: * * * * * (every minute) from the user's crontab.
#
# Coexists with orch-response-watcher, which injects 'check response <id>' into
# the SAME tmux. Different message shapes, same session — fine. Both honor the
# same boot-grace marker (run-orchestrator.sh writes .boot-grace-until) so
# neither injects while Claude Code's TUI is still booting.

set -u

DB="${HOME}/awsc-new/awesome/slack-app/queue.db"
LOG_DIR="${HOME}/awsc-new/awesome/orchestrator/logs"
LOG="${LOG_DIR}/keepalive-orchestrator.log"
SESSION="orchestrator"
QUEUE="orchestrator"
GRACE_FILE="${HOME}/awsc-new/awesome/orchestrator/.boot-grace-until"

mkdir -p "$LOG_DIR"

# Boot grace — same discipline as the awesome-kurt / ppc keepalives and the
# orch-response-watcher.
if [ -f "$GRACE_FILE" ]; then
    GRACE_UNTIL=$(cat "$GRACE_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$NOW" -lt "$GRACE_UNTIL" ]; then
        exit 0
    fi
    rm -f "$GRACE_FILE"
fi

# Abort silently if the PM session isn't up yet.
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    exit 0
fi

HAS_WORK=$(sqlite3 "$DB" "SELECT 1 FROM messages
  WHERE queue_name='${QUEUE}' AND status IN ('pending','processing') LIMIT 1;")
if [ -z "$HAS_WORK" ]; then
    exit 0
fi

tmux send-keys -t "$SESSION" "check queue" Enter
echo "$(date -Is) [keepalive-orchestrator] sent 'check queue' to ${SESSION} (queue=${QUEUE}, work pending)" >> "$LOG"
