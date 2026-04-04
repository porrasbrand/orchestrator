#!/bin/bash
# Identify ready-to-run phases and prepare for parallel dispatch
# Usage: parallel-dispatch.sh <project-path> [worker]
#
# Outputs JSON dispatch plan to stdout:
# {
#   "ready_phases": [...],
#   "branches_created": [...],
#   "suggested_assignments": {...}
# }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:?Usage: parallel-dispatch.sh <project-path> [worker]}"
WORKER="${2:-}"
CONFIG_FILE="$SCRIPT_DIR/../config/workers.json"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"

# Redirect all non-JSON output to stderr
exec 3>&1
exec 1>&2

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE"
  echo '{"ready_phases":[],"branches_created":[],"suggested_assignments":{}}' >&3
  exit 0
fi

# Get ready phases from dag.sh output
echo "Analyzing dependencies..."
DAG_OUTPUT=$(bash "$SCRIPT_DIR/dag.sh" "$PROJECT_PATH" 2>&1)

# Extract ready phases from dag output (lines after "Ready to run" until next section)
READY_PHASES=()
in_ready_section=false
while IFS= read -r line; do
  if echo "$line" | grep -q "Ready to run"; then
    in_ready_section=true
    continue
  fi
  if [ "$in_ready_section" = true ]; then
    if echo "$line" | grep -q "^==="; then
      break
    fi
    # Extract phase name (strip leading whitespace)
    phase=$(echo "$line" | sed 's/^[[:space:]]*//' | grep -v "^(none)$" | grep -v "^$")
    if [ -n "$phase" ]; then
      READY_PHASES+=("$phase")
    fi
  fi
done <<< "$DAG_OUTPUT"

echo "Found ${#READY_PHASES[@]} ready phase(s)"

# If no ready phases, output empty plan
if [ ${#READY_PHASES[@]} -eq 0 ]; then
  echo "No phases ready to dispatch"
  echo '{"ready_phases":[],"branches_created":[],"suggested_assignments":{}}' >&3
  exit 0
fi

# Get active workers for load-balanced assignment
ACTIVE_WORKERS=()
if [ -f "$CONFIG_FILE" ]; then
  while IFS= read -r worker; do
    ACTIVE_WORKERS+=("$worker")
  done < <(jq -r '.workers | to_entries[] | select(.value.status == "active") | .key' "$CONFIG_FILE")
fi

# Fallback if no active workers found
if [ ${#ACTIVE_WORKERS[@]} -eq 0 ]; then
  ACTIVE_WORKERS=("hetzner")
fi

echo "Active workers: ${ACTIVE_WORKERS[*]}"

# Select primary worker using load balancing
PRIMARY_WORKER=$(bash "$SCRIPT_DIR/select-worker.sh" 2>/dev/null) || PRIMARY_WORKER="${ACTIVE_WORKERS[0]}"
echo "Primary worker (least busy): $PRIMARY_WORKER"

# Create branches for each ready phase
BRANCHES_CREATED=()
ASSIGNMENTS=()
use_primary=true

for phase in "${READY_PHASES[@]}"; do
  echo "Creating branch for: $phase"

  # Create phase branch
  if [ -n "$WORKER" ]; then
    bash "$SCRIPT_DIR/branch.sh" create "$PROJECT_PATH" "$phase" "$WORKER" 2>&1 || true
  else
    bash "$SCRIPT_DIR/branch.sh" create "$PROJECT_PATH" "$phase" 2>&1 || true
  fi

  BRANCHES_CREATED+=("phase/$phase")

  # Load-balanced worker assignment (alternate between workers for parallelism)
  if [ "$use_primary" = true ]; then
    assigned_worker="$PRIMARY_WORKER"
    use_primary=false
  else
    # Use the other worker if multiple exist
    for w in "${ACTIVE_WORKERS[@]}"; do
      if [ "$w" != "$PRIMARY_WORKER" ]; then
        assigned_worker="$w"
        break
      fi
    done
    # Fallback to primary if only one worker
    [ -z "$assigned_worker" ] && assigned_worker="$PRIMARY_WORKER"
    use_primary=true
  fi
  ASSIGNMENTS+=("\"$phase\":\"$assigned_worker\"")
done

# Switch back to master
echo "Switching back to master..."
cd "$PROJECT_PATH" && git checkout master 2>&1 || true

# Build JSON output
ready_json=$(printf '%s\n' "${READY_PHASES[@]}" | jq -R . | jq -s .)
branches_json=$(printf '%s\n' "${BRANCHES_CREATED[@]}" | jq -R . | jq -s .)
assignments_json=$(echo "{${ASSIGNMENTS[*]}}" | sed 's/" "/","/g')

# Output final JSON to stdout (fd 3)
echo "Dispatch plan ready"
cat >&3 << EOF
{
  "ready_phases": $ready_json,
  "branches_created": $branches_json,
  "suggested_assignments": $assignments_json
}
EOF
