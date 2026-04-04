#!/bin/bash
# Validate a spec.md file before queuing to DEV worker
# Usage: ./scripts/check-spec.sh <spec-path>
# Exit codes: 0 = PASS (warnings ok), 1 = FAIL (has errors)

set -e

SPEC_PATH="${1:?Usage: check-spec.sh <spec-path>}"

if [ ! -f "$SPEC_PATH" ]; then
  echo "❌ File not found: $SPEC_PATH"
  exit 1
fi

echo "Checking: $SPEC_PATH"
echo ""

ERRORS=0
WARNINGS=0

# Helper: check if section exists and has content
check_section() {
  local section="$1"
  local required="$2"  # "required" or "recommended"
  local content

  # Extract section content (from ## Section to next ## or EOF)
  content=$(sed -n "/^## ${section}$/,/^## /p" "$SPEC_PATH" | sed '1d;$d' | grep -v '^$' | head -20)

  if [ -z "$content" ]; then
    if [ "$required" = "required" ]; then
      echo "❌ ${section}: MISSING (required)"
      return 1
    else
      echo "⚠️  ${section}: MISSING (recommended)"
      return 2
    fi
  else
    return 0
  fi
}

# Check Objective
objective_content=$(sed -n '/^## Objective$/,/^## /p' "$SPEC_PATH" | sed '1d;$d' | grep -v '^$' | tr '\n' ' ')
if [ -z "$objective_content" ] || echo "$objective_content" | grep -qE '^\[.*\]$'; then
  echo "❌ Objective: MISSING or placeholder only (required)"
  ERRORS=$((ERRORS+1))
else
  word_count=$(echo "$objective_content" | wc -w)
  if [ "$word_count" -lt 20 ]; then
    echo "⚠️  Objective: present (${word_count} words) — may be too vague"
    WARNINGS=$((WARNINGS+1))
  else
    echo "✅ Objective: present (${word_count} words)"
  fi
fi

# Check Acceptance Criteria
criteria_count=$(grep -c '^\- \[ \]' "$SPEC_PATH" 2>/dev/null) || criteria_count=0
if [ "$criteria_count" -eq 0 ]; then
  echo "❌ Acceptance Criteria: no checkbox items found (required)"
  ERRORS=$((ERRORS+1))
else
  echo "✅ Acceptance Criteria: ${criteria_count} items"
fi

# Check Smoke Tests - extract from ## Smoke Tests to next ## heading or EOF
# Use sed to get section, then grep for test patterns
smoke_section=$(sed -n '/^## Smoke Tests/,/^## [^S]/p' "$SPEC_PATH" 2>/dev/null | sed '1d;$d') || smoke_section=""
# If that didn't work (section at EOF), try getting everything after ## Smoke Tests
if [ -z "$smoke_section" ]; then
  smoke_section=$(sed -n '/^## Smoke Tests/,$p' "$SPEC_PATH" 2>/dev/null | sed '1d') || smoke_section=""
fi
# Count lines with test indicators: numbered items, backticks, arrows, or "expect"
smoke_count=$(echo "$smoke_section" | grep -cE '(→|`.+`|^[0-9]+\.|expect )' 2>/dev/null) || smoke_count=0
if [ "$smoke_count" -eq 0 ]; then
  echo "❌ Smoke Tests: no test commands found (required)"
  ERRORS=$((ERRORS+1))
else
  echo "✅ Smoke Tests: ${smoke_count} tests found"
fi

# Check recommended sections
if grep -q "^## Prior Work Summary$" "$SPEC_PATH"; then
  echo "✅ Prior Work Summary: present"
else
  echo "⚠️  Prior Work Summary: MISSING (recommended)"
  WARNINGS=$((WARNINGS+1))
fi

if grep -q "^## Expected Files Changed$" "$SPEC_PATH"; then
  echo "✅ Expected Files Changed: present"
else
  echo "⚠️  Expected Files Changed: MISSING (recommended)"
  WARNINGS=$((WARNINGS+1))
fi

if grep -q "^## Do NOT Touch$" "$SPEC_PATH"; then
  echo "✅ Do NOT Touch: present"
else
  echo "⚠️  Do NOT Touch: MISSING (recommended)"
  WARNINGS=$((WARNINGS+1))
fi

if grep -qE "^## Files to (Create|Modify)$" "$SPEC_PATH"; then
  echo "✅ Files to Create/Modify: present"
else
  echo "⚠️  Files to Create/Modify: MISSING (recommended)"
  WARNINGS=$((WARNINGS+1))
fi

# Summary
echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "Result: FAIL (${ERRORS} error(s), ${WARNINGS} warning(s))"
  exit 1
else
  if [ "$WARNINGS" -gt 0 ]; then
    echo "Result: PASS (${WARNINGS} warning(s))"
  else
    echo "Result: PASS"
  fi
  exit 0
fi
