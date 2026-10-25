#!/bin/bash
# Merge completed phase branches back to main in dependency order
# Usage: merge-phases.sh <project-path> [worker]
#
# Merges all phase/* branches for completed phases in topological order

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:?Usage: merge-phases.sh <project-path> [worker]}"
WORKER="${2:-}"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE"
  exit 1
fi

# Helper to run git commands locally or via SSH
run_git() {
  local cmd="$1"
  if [ -n "$WORKER" ]; then
    local ssh_cmd
    ssh_cmd=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" ssh_cmd 2>&1) || {
      echo "❌ $ssh_cmd" >&2
      exit 1
    }
    local base_path
    base_path=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" base_path 2>&1) || {
      echo "❌ $base_path" >&2
      exit 1
    }
    local project_name=$(basename "$PROJECT_PATH")
    $ssh_cmd "cd $base_path/$project_name && $cmd"
  else
    (cd "$PROJECT_PATH" && eval "$cmd")
  fi
}

# Get list of phase/* branches that exist
get_phase_branches() {
  run_git "git branch --list 'phase/*'" 2>/dev/null | sed 's/^[* ]*//' | sed 's/phase\///'
}

# Get completed phases from status.json
get_completed_phases() {
  jq -r '.phases | to_entries[] | select(.value.status == "complete") | .key' "$STATUS_FILE"
}

# Get dependency level for a phase (for sorting)
get_phase_level() {
  local phase="$1"
  local deps
  deps=$(jq -r --arg p "$phase" '.phases[$p].depends_on // [] | length' "$STATUS_FILE")
  if [ "$deps" = "0" ]; then
    echo "0"
  else
    # Simple: count deps as level (good enough for topological sort)
    echo "$deps"
  fi
}

echo "========================================"
echo "Merge Orchestration"
echo "========================================"

# Get existing phase branches
BRANCHES=($(get_phase_branches))
if [ ${#BRANCHES[@]} -eq 0 ]; then
  echo "No phase branches to merge."
  exit 0
fi

echo "Found ${#BRANCHES[@]} phase branch(es): ${BRANCHES[*]}"

# Get completed phases
COMPLETED_PHASES=($(get_completed_phases))
echo "Completed phases: ${COMPLETED_PHASES[*]}"

# Find branches that correspond to completed phases
BRANCHES_TO_MERGE=()
for branch in "${BRANCHES[@]}"; do
  for completed in "${COMPLETED_PHASES[@]}"; do
    if [ "$branch" = "$completed" ]; then
      BRANCHES_TO_MERGE+=("$branch")
      break
    fi
  done
done

if [ ${#BRANCHES_TO_MERGE[@]} -eq 0 ]; then
  echo "No phase branches to merge (no completed phases have unmerged branches)."
  exit 0
fi

echo "Branches to merge: ${BRANCHES_TO_MERGE[*]}"

# Sort branches by dependency level (phases with fewer deps merge first)
SORTED_BRANCHES=()
declare -A BRANCH_LEVELS
for branch in "${BRANCHES_TO_MERGE[@]}"; do
  level=$(get_phase_level "$branch")
  BRANCH_LEVELS["$branch"]=$level
done

# Simple sort by level
for level in 0 1 2 3 4 5; do
  for branch in "${BRANCHES_TO_MERGE[@]}"; do
    if [ "${BRANCH_LEVELS[$branch]}" = "$level" ]; then
      SORTED_BRANCHES+=("$branch")
    fi
  done
done

echo ""
echo "Merge order (by dependency level):"
for branch in "${SORTED_BRANCHES[@]}"; do
  echo "  $branch (level ${BRANCH_LEVELS[$branch]})"
done

echo ""
echo "========================================"
echo "Merge Report:"
echo "========================================"

MERGED_COUNT=0
FAILED=false
FAILED_PHASE=""

for phase in "${SORTED_BRANCHES[@]}"; do
  echo -n "  Merging $phase... "

  # Run merge via branch.sh
  if bash "$SCRIPT_DIR/branch.sh" merge "$PROJECT_PATH" "$phase" $WORKER 2>&1; then
    echo "✅ $phase — merged to master"
    MERGED_COUNT=$((MERGED_COUNT + 1))
  else
    echo "❌ $phase — MERGE CONFLICT"
    FAILED=true
    FAILED_PHASE="$phase"
    break
  fi
done

echo ""

if [ "$FAILED" = true ]; then
  echo "❌ Merge stopped at $FAILED_PHASE due to conflict."
  echo "   Resolve the conflict manually, then re-run merge-phases.sh"
  exit 1
else
  if [ $MERGED_COUNT -gt 0 ]; then
    echo "All $MERGED_COUNT branch(es) merged successfully."
  else
    echo "No branches were merged."
  fi
  exit 0
fi
