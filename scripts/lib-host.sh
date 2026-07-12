#!/usr/bin/env bash
# lib-host.sh — shared host detection for the orchestrator.
#
# Sourced by queue-phase.sh / get-worker.sh / verify.sh etc. Lets the same repo
# work on BOTH hosts:
#   • lipo-360 (the laptop PM)  → remote: dispatch/verify via SSH into hetzner
#   • hetzner  (resident PM)    → local:  dispatch/verify against local queue.db
#
# Detection (per orch-migration-01 spec): we are on hetzner when the hostname is
# the hetzner box OR $HOME=/home/ubuntu AND the local slack-app queue.db exists
# (the strong local signal — lipo has to SSH to reach that DB, it isn't local).

# Absolute path to the local worker queue DB when resident on hetzner.
ORCH_HETZNER_QUEUE_DB="${ORCH_HETZNER_QUEUE_DB:-$HOME/awsc-new/awesome/slack-app/queue.db}"
ORCH_HETZNER_SLACK_APP="${ORCH_HETZNER_SLACK_APP:-$HOME/awsc-new/awesome/slack-app}"

# Return 0 when running ON the hetzner resident host, 1 otherwise.
orch_is_hetzner() {
  # Explicit override for tests / edge hosts.
  case "${ORCH_FORCE_HOST:-}" in
    hetzner) return 0 ;;
    lipo|remote) return 1 ;;
  esac
  local h
  h="$(hostname 2>/dev/null || echo)"
  [[ "$h" == ubuntu-32gb-* ]] && return 0
  [[ "$HOME" == "/home/ubuntu" && -f "$ORCH_HETZNER_QUEUE_DB" ]] && return 0
  return 1
}
