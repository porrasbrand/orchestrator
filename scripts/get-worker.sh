#!/bin/bash
# Get worker configuration from config/workers.json
# Usage: get-worker.sh <worker-name> <field>
# Example: get-worker.sh hetzner host → remote.manuelporras.com
# Example: get-worker.sh hetzner ssh_cmd → full SSH command string
# Example: get-worker.sh hetzner scp_cmd → full SCP command prefix

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/workers.json"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib-host.sh"

WORKER="${1:?Usage: get-worker.sh <worker-name> <field>}"
FIELD="${2:?Missing field (host, port, user, ssh_key, base_path, capabilities, status, ssh_cmd, scp_cmd)}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Error: workers.json not found at $CONFIG_FILE" >&2
  exit 1
fi

# Check if worker exists
WORKER_EXISTS=$(jq -r --arg w "$WORKER" '.workers | has($w)' "$CONFIG_FILE")
if [ "$WORKER_EXISTS" != "true" ]; then
  echo "❌ Error: Worker '$WORKER' not found in registry" >&2
  exit 1
fi

# Resident-host short-circuit: if this worker is local:true AND we are running ON
# that host, there is no SSH hop. ssh_cmd/scp_cmd become LOCAL runners so callers
# (verify.sh etc.) that do `$SSH_CMD "<cmd string>"` execute directly.
#   ssh_cmd → `bash -c`   (so `bash -c "<cmd>"` runs locally; ~ and base_path expand)
#   scp_cmd → `cp`        (local file copy; same-host so no host: prefix needed)
WORKER_LOCAL=$(jq -r --arg w "$WORKER" '.workers[$w].local // false' "$CONFIG_FILE")
if [ "$WORKER_LOCAL" = "true" ] && orch_is_hetzner; then
  case "$FIELD" in
    ssh_cmd) echo "bash -c"; exit 0 ;;
    scp_cmd) echo "cp"; exit 0 ;;
  esac
fi

# Special computed fields
if [ "$FIELD" = "ssh_cmd" ]; then
  HOST=$(jq -r --arg w "$WORKER" '.workers[$w].host' "$CONFIG_FILE")
  PORT=$(jq -r --arg w "$WORKER" '.workers[$w].port' "$CONFIG_FILE")
  USER=$(jq -r --arg w "$WORKER" '.workers[$w].user' "$CONFIG_FILE")
  SSH_KEY=$(jq -r --arg w "$WORKER" '.workers[$w].ssh_key' "$CONFIG_FILE")
  # Expand ~ in ssh_key path
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  echo "ssh $HOST -p $PORT -l $USER -i $SSH_KEY -o ConnectTimeout=10 -o ServerAliveInterval=5 -o StrictHostKeyChecking=no -o BatchMode=yes"
  exit 0
fi

if [ "$FIELD" = "scp_cmd" ]; then
  HOST=$(jq -r --arg w "$WORKER" '.workers[$w].host' "$CONFIG_FILE")
  PORT=$(jq -r --arg w "$WORKER" '.workers[$w].port' "$CONFIG_FILE")
  USER=$(jq -r --arg w "$WORKER" '.workers[$w].user' "$CONFIG_FILE")
  SSH_KEY=$(jq -r --arg w "$WORKER" '.workers[$w].ssh_key' "$CONFIG_FILE")
  SSH_KEY="${SSH_KEY/#\~/$HOME}"
  echo "scp -P $PORT -i $SSH_KEY -o StrictHostKeyChecking=no -o BatchMode=yes"
  exit 0
fi

# Regular field lookup
VALUE=$(jq -r --arg w "$WORKER" --arg f "$FIELD" '.workers[$w][$f] // empty' "$CONFIG_FILE")
if [ -z "$VALUE" ]; then
  echo "❌ Error: Field '$FIELD' not found for worker '$WORKER'" >&2
  exit 1
fi

echo "$VALUE"
