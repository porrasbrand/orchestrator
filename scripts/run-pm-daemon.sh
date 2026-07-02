#!/usr/bin/env bash
# run-pm-daemon.sh — pm2 wrapper for services/pm-daemon.js.
#
# Deployment:
#   pm2 start scripts/run-pm-daemon.sh --name pm-daemon
#
# Env knobs (override as needed):
#   ORCH_STATE_DIR   ($HOME/.orchestrator)
#   SUPER_AGENT_DIR  ($HOME/awesome/super-agent)
#   PM_GRACE_PERIOD  (600)   seconds a response must sit in new/ before claim
#   PM_POLL_INTERVAL (60)    seconds between response-scan cycles
#   PM_TICK_INTERVAL (900)   seconds between project-tick cycles
#   PM_STALL_TIMEOUT (14400) seconds a queued phase may sit before tick pokes
#   PM_MAX_ATTEMPTS  (2)     pm-iterate attempts per claim before give-up
#   PM_ITERATE_BIN   (<repo>/scripts/pm-iterate.sh)
#
# For tests, pass --once to run one scan + one tick synchronously and exit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

exec node "$REPO_DIR/services/pm-daemon.js" "$@"
