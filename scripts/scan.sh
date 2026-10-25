#!/bin/bash
# Scan an existing codebase and generate snapshot.md
# Usage: ./scripts/scan.sh <project-path>

set -e

PROJECT_PATH="${1:?Usage: scan.sh <project-path>}"
OUTPUT="$PROJECT_PATH/.planning/snapshot.md"
TODAY=$(date +%Y-%m-%d)

mkdir -p "$PROJECT_PATH/.planning"
echo "🔍 Scanning codebase at: $PROJECT_PATH"

cat > "$OUTPUT" << HEADER
# Codebase Snapshot

Generated: $TODAY
Project: $PROJECT_PATH

HEADER

# Tech stack detection
echo "## Tech Stack" >> "$OUTPUT"
if [ -f "$PROJECT_PATH/package.json" ]; then
  echo "- Language: Node.js" >> "$OUTPUT"
  echo "- Package manager: npm" >> "$OUTPUT"
  # Detect framework
  if grep -q '"express"' "$PROJECT_PATH/package.json" 2>/dev/null; then
    echo "- Framework: Express.js" >> "$OUTPUT"
  elif grep -q '"fastify"' "$PROJECT_PATH/package.json" 2>/dev/null; then
    echo "- Framework: Fastify" >> "$OUTPUT"
  elif grep -q '"next"' "$PROJECT_PATH/package.json" 2>/dev/null; then
    echo "- Framework: Next.js" >> "$OUTPUT"
  fi
elif [ -f "$PROJECT_PATH/requirements.txt" ] || [ -f "$PROJECT_PATH/pyproject.toml" ]; then
  echo "- Language: Python" >> "$OUTPUT"
elif [ -f "$PROJECT_PATH/go.mod" ]; then
  echo "- Language: Go" >> "$OUTPUT"
fi

# Database detection
if grep -rq "pg\|postgres\|PostgreSQL" "$PROJECT_PATH" --include="*.js" --include="*.ts" --include="*.py" --include="*.json" 2>/dev/null | head -1 >/dev/null 2>&1; then
  echo "- Database: PostgreSQL" >> "$OUTPUT"
elif grep -rq "sqlite\|better-sqlite" "$PROJECT_PATH" --include="*.js" --include="*.ts" --include="*.py" --include="*.json" 2>/dev/null | head -1 >/dev/null 2>&1; then
  echo "- Database: SQLite" >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# File structure
echo "## File Structure" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
cd "$PROJECT_PATH" && find . \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  -not -path '*/.planning/*' \
  -not -path '*/__pycache__/*' \
  -not -name '*.Zone.Identifier' \
  -not -name '*.lock' \
  -not -name 'package-lock.json' \
  | sort | head -150 >> "$OUTPUT"
echo '```' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Dependencies
echo "## Dependencies" >> "$OUTPUT"
if [ -f "$PROJECT_PATH/package.json" ]; then
  echo '```json' >> "$OUTPUT"
  node -e "
    const pkg = require('$PROJECT_PATH/package.json');
    const deps = {...(pkg.dependencies||{}), ...(pkg.devDependencies||{})};
    console.log(JSON.stringify(deps, null, 2));
  " >> "$OUTPUT" 2>/dev/null || echo "{}" >> "$OUTPUT"
  echo '```' >> "$OUTPUT"
elif [ -f "$PROJECT_PATH/requirements.txt" ]; then
  echo '```' >> "$OUTPUT"
  cat "$PROJECT_PATH/requirements.txt" >> "$OUTPUT"
  echo '```' >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# Entry points
echo "## Entry Points" >> "$OUTPUT"
for f in server.js index.js main.js app.js main.py app.py; do
  if [ -f "$PROJECT_PATH/$f" ]; then
    echo "- \`$f\`" >> "$OUTPUT"
  fi
  # Check common subdirs
  for dir in backend src; do
    if [ -f "$PROJECT_PATH/$dir/$f" ]; then
      echo "- \`$dir/$f\`" >> "$OUTPUT"
    fi
  done
done
echo "" >> "$OUTPUT"

# Key exports
echo "## Key Exports & Components" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
cd "$PROJECT_PATH" && grep -rn \
  'export function\|export class\|export default\|export async function\|module\.exports' \
  --include='*.js' --include='*.ts' --include='*.mjs' \
  --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.git \
  2>/dev/null | head -40 >> "$OUTPUT" || echo "(none found)" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# API routes
echo "## API Routes" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
cd "$PROJECT_PATH" && grep -rn \
  'router\.\(get\|post\|put\|delete\|patch\)\|app\.\(get\|post\|put\|delete\|patch\)' \
  --include='*.js' --include='*.ts' \
  --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.git \
  2>/dev/null | head -30 >> "$OUTPUT" || echo "(none found)" >> "$OUTPUT"
echo '```' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# Database schemas
echo "## Database Schema" >> "$OUTPUT"
SQL_FILES=$(cd "$PROJECT_PATH" && find . -name '*.sql' -not -path '*/node_modules/*' 2>/dev/null | head -10)
if [ -n "$SQL_FILES" ]; then
  for sql in $SQL_FILES; do
    echo "### $sql" >> "$OUTPUT"
    echo '```sql' >> "$OUTPUT"
    head -50 "$PROJECT_PATH/$sql" >> "$OUTPUT"
    echo '```' >> "$OUTPUT"
  done
else
  echo "(no SQL files found)" >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# Existing docs
echo "## Existing Documentation" >> "$OUTPUT"
for doc in README.md CLAUDE.md docs/README.md; do
  if [ -f "$PROJECT_PATH/$doc" ]; then
    echo "### $doc" >> "$OUTPUT"
    head -30 "$PROJECT_PATH/$doc" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "..." >> "$OUTPUT"
    echo "" >> "$OUTPUT"
  fi
done

# Config
echo "## Configuration" >> "$OUTPUT"
if [ -f "$PROJECT_PATH/.env.example" ]; then
  echo "### .env.example" >> "$OUTPUT"
  echo '```' >> "$OUTPUT"
  cat "$PROJECT_PATH/.env.example" >> "$OUTPUT"
  echo '```' >> "$OUTPUT"
fi
echo "" >> "$OUTPUT"

# Line count
LINES=$(wc -l < "$OUTPUT")
echo ""
echo "✅ Snapshot written to: $OUTPUT ($LINES lines)"
