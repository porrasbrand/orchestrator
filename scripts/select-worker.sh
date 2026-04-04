#!/bin/bash
# Select the least-busy active worker
# Usage: select-worker.sh [config-path]
# Output: worker name (e.g., "hetzner")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/../config/workers.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "hetzner"
  exit 0
fi

# Get active workers
ACTIVE_WORKERS=($(jq -r '.workers | to_entries[] | select(.value.status == "active") | .key' "$CONFIG_FILE" 2>/dev/null))

if [ ${#ACTIVE_WORKERS[@]} -eq 0 ]; then
  echo "hetzner"
  exit 0
fi

# If only one worker, return it
if [ ${#ACTIVE_WORKERS[@]} -eq 1 ]; then
  echo "${ACTIVE_WORKERS[0]}"
  exit 0
fi

# Check each worker for availability
for worker in "${ACTIVE_WORKERS[@]}"; do
  # Get SSH command for this worker
  ssh_cmd=$(bash "$SCRIPT_DIR/get-worker.sh" "$worker" ssh_cmd 2>/dev/null) || continue
  base_path=$(bash "$SCRIPT_DIR/get-worker.sh" "$worker" base_path 2>/dev/null) || continue

  # Check if worker is reachable and not busy (5 second timeout)
  # Check for .orchestrator-busy lock file
  is_busy=$($ssh_cmd "test -f $base_path/.orchestrator-busy && echo BUSY || echo FREE" 2>/dev/null)

  if [ "$is_busy" = "FREE" ]; then
    echo "$worker"
    exit 0
  fi
done

# All workers busy or unreachable, return first active worker
echo "${ACTIVE_WORKERS[0]}"
