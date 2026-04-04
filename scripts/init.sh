#!/bin/bash
# Scaffold .planning/ directory in a project
# Usage: ./scripts/init.sh <project-path> [project-name]

set -e

PROJECT_PATH="${1:?Usage: init.sh <project-path> [project-name]}"
PROJECT_NAME="${2:-$(basename "$PROJECT_PATH")}"
TODAY=$(date +%Y-%m-%d)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Create directory structure
mkdir -p "$PROJECT_PATH/.planning/phases"

# Initialize events log
if [ ! -f "$PROJECT_PATH/.planning/events.jsonl" ]; then
  echo "{\"ts\":\"$NOW\",\"event\":\"project_init\",\"data\":{\"project\":\"$PROJECT_NAME\",\"path\":\"$PROJECT_PATH\"}}" > "$PROJECT_PATH/.planning/events.jsonl"
  echo "✅ Created events.jsonl"
fi

# Initialize status.json
if [ ! -f "$PROJECT_PATH/.planning/status.json" ]; then
  cat > "$PROJECT_PATH/.planning/status.json" << EOF
{
  "project": "$PROJECT_NAME",
  "created": "$TODAY",
  "updated": "$TODAY",
  "status": "initializing",
  "current_phase": null,
  "checkpoint_frequency": 3,
  "phases_since_checkpoint": 0,
  "target_worker": "hetzner",
  "phases": {},
  "execution_order": [],
  "blocked": false,
  "blocked_reason": null,
  "metrics": {
    "phases_complete": 0,
    "phases_total": 0,
    "total_revisions": 0,
    "total_smoke_tests": 0,
    "started_at": null
  }
}
EOF
  echo "✅ Created status.json"
fi

# Initialize learnings.md
if [ ! -f "$PROJECT_PATH/.planning/learnings.md" ]; then
  echo "# Learnings" > "$PROJECT_PATH/.planning/learnings.md"
  echo "" >> "$PROJECT_PATH/.planning/learnings.md"
  echo "Discoveries made during execution that inform future phases." >> "$PROJECT_PATH/.planning/learnings.md"
  echo "✅ Created learnings.md"
fi

# Initialize notifications.md
if [ ! -f "$PROJECT_PATH/.planning/notifications.md" ]; then
  echo "# Notifications" > "$PROJECT_PATH/.planning/notifications.md"
  echo "" >> "$PROJECT_PATH/.planning/notifications.md"
  echo "Level 1 notifications for user review." >> "$PROJECT_PATH/.planning/notifications.md"
  echo "✅ Created notifications.md"
fi

echo ""
echo "📁 .planning/ scaffolded at: $PROJECT_PATH/.planning/"
echo "   Next: copy brief.md, write project.md, create phase specs"
