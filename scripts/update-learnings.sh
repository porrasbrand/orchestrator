#!/bin/bash
# Update learnings.jsonl and regenerate learnings.md
# Usage:
#   Add:   ./scripts/update-learnings.sh <project-path> <phase> <category> "<discovery>" [impact]
#   Query: ./scripts/update-learnings.sh --query <project-path> <filter>
#
# Categories: codebase, api, testing, infrastructure, security, performance, other
# Impact: high, medium, low (default: medium)

set -e

# Check for query mode
if [ "$1" = "--query" ]; then
  PROJECT_PATH="${2:?Usage: update-learnings.sh --query <project-path> <filter>}"
  FILTER="${3:?Usage: update-learnings.sh --query <project-path> <filter>}"
  LEARNINGS_FILE="$PROJECT_PATH/.planning/learnings.jsonl"

  if [ ! -f "$LEARNINGS_FILE" ]; then
    echo "[]"
    exit 0
  fi

  # Parse filter (key=value)
  KEY="${FILTER%%=*}"
  VALUE="${FILTER#*=}"

  # Query using jq
  jq -c "select(.${KEY} == \"${VALUE}\")" "$LEARNINGS_FILE"
  exit 0
fi

# Add mode
PROJECT_PATH="${1:?Usage: update-learnings.sh <project-path> <phase> <category> \"<discovery>\" [impact]}"
PHASE="${2:?Missing phase argument}"
CATEGORY="${3:?Missing category argument}"
DISCOVERY="${4:?Missing discovery argument}"
IMPACT="${5:-medium}"

# Validate category
VALID_CATEGORIES="codebase api testing infrastructure security performance other"
if ! echo "$VALID_CATEGORIES" | grep -qw "$CATEGORY"; then
  echo "❌ Invalid category: $CATEGORY"
  echo "   Valid: $VALID_CATEGORIES"
  exit 1
fi

# Validate impact
VALID_IMPACTS="high medium low"
if ! echo "$VALID_IMPACTS" | grep -qw "$IMPACT"; then
  echo "❌ Invalid impact: $IMPACT"
  echo "   Valid: $VALID_IMPACTS"
  exit 1
fi

LEARNINGS_FILE="$PROJECT_PATH/.planning/learnings.jsonl"
LEARNINGS_MD="$PROJECT_PATH/.planning/learnings.md"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Create .planning directory if needed
mkdir -p "$PROJECT_PATH/.planning"

# Create learnings.jsonl if it doesn't exist
if [ ! -f "$LEARNINGS_FILE" ]; then
  touch "$LEARNINGS_FILE"
fi

# Append learning using jq for safe JSON construction
jq -n -c \
  --arg ts "$NOW" \
  --arg phase "$PHASE" \
  --arg category "$CATEGORY" \
  --arg discovery "$DISCOVERY" \
  --arg impact "$IMPACT" \
  '{ts: $ts, phase: $phase, category: $category, discovery: $discovery, impact: $impact}' \
  >> "$LEARNINGS_FILE"

echo "✅ Added learning to $LEARNINGS_FILE"

# Regenerate learnings.md from learnings.jsonl
regenerate_md() {
  local jsonl_file="$1"
  local md_file="$2"

  cat > "$md_file" << 'HEADER'
# Learnings

Discoveries made during execution that inform future phases.

HEADER

  # Get unique phases in order of appearance
  local phases=$(jq -r '.phase' "$jsonl_file" 2>/dev/null | awk '!seen[$0]++')

  if [ -z "$phases" ]; then
    echo "*No learnings recorded yet.*" >> "$md_file"
    return
  fi

  # For each phase, output its learnings
  while IFS= read -r phase; do
    [ -z "$phase" ] && continue
    echo "## Phase: $phase" >> "$md_file"
    echo "" >> "$md_file"

    # Get learnings for this phase
    jq -r "select(.phase == \"$phase\") | \"- **[\(.category)]** \(.discovery) *(\(.impact))*\"" "$jsonl_file" >> "$md_file"

    echo "" >> "$md_file"
  done <<< "$phases"
}

regenerate_md "$LEARNINGS_FILE" "$LEARNINGS_MD"
echo "✅ Regenerated $LEARNINGS_MD"
