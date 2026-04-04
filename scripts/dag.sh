#!/bin/bash
# Analyze phase dependencies and identify parallelizable phases
# Usage: dag.sh <project-path>
# Reads .planning/status.json and outputs dependency analysis

set -e

PROJECT_PATH="${1:?Usage: dag.sh <project-path>}"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE" >&2
  exit 1
fi

# Get all phase names
PHASES=$(jq -r '.phases | keys[]' "$STATUS_FILE" | sort)
PHASE_COUNT=$(echo "$PHASES" | wc -l)

echo "========================================"
echo "Phase Dependencies:"
echo "========================================"

# For each phase, show its dependencies
while IFS= read -r phase; do
  deps=$(jq -r --arg p "$phase" '.phases[$p].depends_on // [] | if length == 0 then "(none)" else join(", ") end' "$STATUS_FILE")
  printf "  %-25s → %s\n" "$phase" "$deps"
done <<< "$PHASES"

echo ""
echo "========================================"
echo "Ready to run (can execute in parallel):"
echo "========================================"

# Find phases that are pending AND have all dependencies complete
READY_COUNT=0
while IFS= read -r phase; do
  status=$(jq -r --arg p "$phase" '.phases[$p].status' "$STATUS_FILE")

  # Skip non-pending phases
  if [ "$status" != "pending" ]; then
    continue
  fi

  # Check if all dependencies are complete
  deps=$(jq -r --arg p "$phase" '.phases[$p].depends_on // []' "$STATUS_FILE")
  all_deps_complete=true

  if [ "$deps" != "[]" ]; then
    dep_list=$(jq -r --arg p "$phase" '.phases[$p].depends_on[]' "$STATUS_FILE" 2>/dev/null) || dep_list=""
    while IFS= read -r dep; do
      [ -z "$dep" ] && continue
      dep_status=$(jq -r --arg d "$dep" '.phases[$d].status // "unknown"' "$STATUS_FILE")
      if [ "$dep_status" != "complete" ]; then
        all_deps_complete=false
        break
      fi
    done <<< "$dep_list"
  fi

  if [ "$all_deps_complete" = true ]; then
    echo "  $phase"
    READY_COUNT=$((READY_COUNT+1))
  fi
done <<< "$PHASES"

if [ "$READY_COUNT" -eq 0 ]; then
  echo "  (none)"
fi

echo ""
echo "========================================"
echo "Parallel groups:"
echo "========================================"

# Calculate dependency level for each phase
# Level 0 = no dependencies, Level N = depends on something at level N-1
declare -A PHASE_LEVELS

# Initialize all phases at level -1 (unassigned)
while IFS= read -r phase; do
  PHASE_LEVELS["$phase"]=-1
done <<< "$PHASES"

# Iteratively assign levels
MAX_ITERATIONS=20
changed=true
iteration=0

while [ "$changed" = true ] && [ $iteration -lt $MAX_ITERATIONS ]; do
  changed=false
  iteration=$((iteration+1))

  while IFS= read -r phase; do
    [ "${PHASE_LEVELS[$phase]}" -ge 0 ] && continue

    deps=$(jq -r --arg p "$phase" '.phases[$p].depends_on // []' "$STATUS_FILE")

    if [ "$deps" = "[]" ]; then
      # No dependencies → level 0
      PHASE_LEVELS["$phase"]=0
      changed=true
    else
      # Check if all deps have assigned levels
      max_dep_level=-1
      all_assigned=true

      dep_list=$(jq -r --arg p "$phase" '.phases[$p].depends_on[]' "$STATUS_FILE" 2>/dev/null) || dep_list=""
      while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        dep_level=${PHASE_LEVELS["$dep"]:-"-1"}
        if [ "$dep_level" -lt 0 ]; then
          all_assigned=false
          break
        fi
        if [ "$dep_level" -gt "$max_dep_level" ]; then
          max_dep_level=$dep_level
        fi
      done <<< "$dep_list"

      if [ "$all_assigned" = true ]; then
        PHASE_LEVELS["$phase"]=$((max_dep_level+1))
        changed=true
      fi
    fi
  done <<< "$PHASES"
done

# Check for circular dependencies
CIRCULAR=false
while IFS= read -r phase; do
  if [ "${PHASE_LEVELS[$phase]}" -lt 0 ]; then
    echo "  ⚠️  WARNING: Circular dependency detected involving: $phase"
    CIRCULAR=true
  fi
done <<< "$PHASES"

if [ "$CIRCULAR" = false ]; then
  # Find max level
  max_level=0
  while IFS= read -r phase; do
    level=${PHASE_LEVELS["$phase"]}
    [ "$level" -gt "$max_level" ] && max_level=$level
  done <<< "$PHASES"

  # Print phases by level
  for level in $(seq 0 $max_level); do
    phases_at_level=""
    while IFS= read -r phase; do
      if [ "${PHASE_LEVELS[$phase]}" -eq "$level" ]; then
        [ -n "$phases_at_level" ] && phases_at_level="$phases_at_level, "
        phases_at_level="$phases_at_level$phase"
      fi
    done <<< "$PHASES"

    if [ "$level" -eq 0 ]; then
      echo "  Level $level: $phases_at_level"
    else
      # Show what they depend on
      echo "  Level $level: $phases_at_level"
    fi
  done

  MIN_STEPS=$((max_level+1))
else
  MIN_STEPS="unknown (circular deps)"
fi

echo ""
echo "========================================"
echo "Summary:"
echo "========================================"

# Count by status
COMPLETE_COUNT=$(jq '[.phases[] | select(.status == "complete")] | length' "$STATUS_FILE")
PENDING_COUNT=$(jq '[.phases[] | select(.status == "pending")] | length' "$STATUS_FILE")
BLOCKED_COUNT=$((PENDING_COUNT - READY_COUNT))

echo "  Total phases: $PHASE_COUNT"
echo "  Complete: $COMPLETE_COUNT"
echo "  Ready: $READY_COUNT"
echo "  Blocked: $BLOCKED_COUNT"
echo "  Min sequential steps: $MIN_STEPS (with parallel execution)"
