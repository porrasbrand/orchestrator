#!/usr/bin/env bash
# run-orchestrator.sh — idempotent launcher for the RESIDENT PM (orch-migration-01).
#
# Brings up Claude Code in a detached tmux session named 'orchestrator', started
# in the orchestrator repo so it loads this repo's (host-aware) CLAUDE.md. If the
# session already exists, prints "already running" and exits 0.
#
# The orch-response-watcher (pm2) injects `check response <id>` into this session
# when a dispatched task completes, closing the loop without a human attaching.
#
# Usage:  ./scripts/run-orchestrator.sh
# Attach: tmux attach -t orchestrator

set -u

SESSION="orchestrator"
WORK_DIR="$HOME/awsc-new/awesome/orchestrator"

if tmux has-session -t "=$SESSION" 2>/dev/null; then
    echo "✅ tmux session '${SESSION}' already running — no-op."
    echo "   Attach with:  tmux attach -t ${SESSION}"
    exit 0
fi

if [ ! -d "$WORK_DIR" ]; then
    echo "❌ working dir not found: $WORK_DIR" >&2
    exit 1
fi

# Boot-grace marker (90s) matching the other resident sessions, so any keystroke
# nudger waits until Claude Code's TUI is interactive.
GRACE_UNTIL=$(( $(date +%s) + 90 ))
echo "$GRACE_UNTIL" > "$WORK_DIR/.boot-grace-until"

tmux new-session -d -s "$SESSION" -c "$WORK_DIR"
sleep 0.3
tmux send-keys -t "$SESSION" "claude --dangerously-skip-permissions" Enter

echo "✅ Launched '${SESSION}' in detached tmux at ${WORK_DIR}."
echo "   Boot grace: 90s (until $(date -d "@$GRACE_UNTIL" -Is 2>/dev/null || date))."
echo "   Attach with:  tmux attach -t ${SESSION}"
echo "   Kill with:    tmux kill-session -t ${SESSION}"
