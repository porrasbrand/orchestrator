#!/bin/bash
# Run smoke tests for a phase and report results
# Usage: ./scripts/verify.sh <worker> <project-path> <phase-dir>
# Example: ./scripts/verify.sh hetzner /home/mp/awesome/blog-publisher .planning/phases/01-publish-history
#
# v2: SSH key auth, timeouts, retry with backoff

set -e

WORKER="${1:?Usage: verify.sh <hetzner|wsl2> <project-path> <phase-dir>}"
PROJECT_PATH="${2:?Missing project path}"
PHASE_DIR="${3:?Missing phase directory}"
SPEC_FILE="$PROJECT_PATH/$PHASE_DIR/spec.md"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PHASE_NAME=$(basename "$PHASE_DIR")

SSH_KEY="$HOME/.ssh/id_remote_claude"
SSH_OPTS="-i $SSH_KEY -o ConnectTimeout=10 -o ServerAliveInterval=5 -o StrictHostKeyChecking=no -o BatchMode=yes"

# SSH config per worker
if [ "$WORKER" = "hetzner" ]; then
  SSH_CMD="ssh remote.manuelporras.com -p 22 -l ubuntu $SSH_OPTS"
  REMOTE_BASE="~/awsc-new/awesome"
elif [ "$WORKER" = "wsl2" ]; then
  SSH_CMD="ssh ssh.manuelporras.com -p 2222 -l ubuntu $SSH_OPTS"
  REMOTE_BASE="~/awsc-new/awesome"
else
  echo "❌ Unknown worker: $WORKER (use hetzner or wsl2)"
  exit 1
fi

# Retry wrapper: run SSH command with 2 retries and backoff
ssh_retry() {
  local max_retries=2
  local attempt=0
  local backoff=3
  local result=""
  local exit_code=0

  while [ $attempt -le $max_retries ]; do
    if [ $attempt -gt 0 ]; then
      echo "  ↻ Retry $attempt/$max_retries (waiting ${backoff}s)..."
      sleep $backoff
      backoff=$((backoff * 2))
    fi

    result=$($SSH_CMD "$@" 2>&1) && exit_code=0 || exit_code=$?

    if [ $exit_code -eq 0 ]; then
      echo "$result"
      return 0
    fi

    # Check if it's a connection error (worth retrying) vs command error (don't retry)
    if echo "$result" | grep -qi "connection\|timeout\|refused\|reset\|network"; then
      attempt=$((attempt + 1))
    else
      # Command itself failed, not SSH — don't retry
      echo "$result"
      return $exit_code
    fi
  done

  echo "SSH_RETRY_EXHAUSTED: $result"
  return 1
}

echo "🔍 Verifying phase: $PHASE_NAME on >>$WORKER"
echo ""

PASS=0
FAIL=0
TOTAL=0

# Step 1: Check result.md exists
echo "--- Basic Checks ---"
RESULT_EXISTS=$(ssh_retry "test -f $REMOTE_BASE/$(basename $PROJECT_PATH)/$PHASE_DIR/result.md && echo YES || echo NO")
if [ "$RESULT_EXISTS" = "YES" ]; then
  echo "✅ result.md exists"
  PASS=$((PASS+1))
else
  echo "❌ result.md NOT FOUND"
  FAIL=$((FAIL+1))
fi
TOTAL=$((TOTAL+1))

# Step 1.5: Diff-Based Scope Check
echo ""
echo "--- Scope Check ---"

SCOPE_WARNINGS=0
if grep -q "^## Expected Files Changed$" "$SPEC_FILE" 2>/dev/null; then
  # Extract expected files from spec (lines like "- `path/to/file`")
  EXPECTED_FILES=$(sed -n '/^## Expected Files Changed$/,/^## /p' "$SPEC_FILE" | grep -oE '\`[^\`]+\`' | tr -d '`' | sort -u)
  EXPECTED_COUNT=$(echo "$EXPECTED_FILES" | grep -c '.' || echo 0)

  # Get actual changed files from last commit on remote
  REMOTE_PROJECT="$REMOTE_BASE/$(basename $PROJECT_PATH)"
  ACTUAL_FILES=$(ssh_retry "cd $REMOTE_PROJECT && git diff --name-only HEAD~1 2>/dev/null" || echo "")
  ACTUAL_COUNT=$(echo "$ACTUAL_FILES" | grep -c '.' 2>/dev/null || echo 0)

  echo "Expected: $EXPECTED_COUNT files"
  echo "Actual: $ACTUAL_COUNT files changed"

  # Check each actual file
  while IFS= read -r file; do
    [ -z "$file" ] && continue

    # Skip .planning/ files (always expected)
    if echo "$file" | grep -q "^\.planning/"; then
      echo "✅ $file (ignored - .planning/)"
      continue
    fi

    # Check if file is in expected list
    if echo "$EXPECTED_FILES" | grep -qF "$file"; then
      echo "✅ $file (expected)"
    else
      echo "⚠️  $file (UNEXPECTED - not in expected files list)"
      SCOPE_WARNINGS=$((SCOPE_WARNINGS+1))
    fi
  done <<< "$ACTUAL_FILES"

  echo ""
  echo "Scope warnings: $SCOPE_WARNINGS"
else
  echo "Scope Check: skipped (no Expected Files Changed in spec)"
fi

# Step 2: Extract and run smoke tests from spec.md
echo ""
echo "--- Smoke Tests ---"

if [ -f "$SPEC_FILE" ]; then
  IN_SMOKE=0
  while IFS= read -r line; do
    if echo "$line" | grep -q "^## Smoke Tests"; then
      IN_SMOKE=1
      continue
    fi
    if [ $IN_SMOKE -eq 1 ] && echo "$line" | grep -q "^## "; then
      break
    fi
    if [ $IN_SMOKE -eq 1 ]; then
      if echo "$line" | grep -q '→ expect\|-> expect'; then
        CMD=$(echo "$line" | sed 's/→ expect.*//;s/-> expect.*//;s/^#.*//;s/`//g' | xargs)
        EXPECTED=$(echo "$line" | sed 's/.*→ expect //;s/.*-> expect //' | sed 's/`//g' | xargs)

        if [ -n "$CMD" ] && [ -n "$EXPECTED" ]; then
          TOTAL=$((TOTAL+1))
          echo -n "Test: $CMD ... "
          ACTUAL=$(ssh_retry "$CMD" 2>/dev/null || echo "COMMAND_FAILED")

          if echo "$ACTUAL" | grep -q "$EXPECTED"; then
            echo "✅"
            PASS=$((PASS+1))
            echo "{\"ts\":\"$NOW\",\"event\":\"smoke_test_pass\",\"data\":{\"phase\":\"$PHASE_NAME\",\"test\":\"$CMD\"}}" >> "$EVENTS_FILE"
          else
            echo "❌ (expected: $EXPECTED, got: $ACTUAL)"
            FAIL=$((FAIL+1))
            echo "{\"ts\":\"$NOW\",\"event\":\"smoke_test_fail\",\"data\":{\"phase\":\"$PHASE_NAME\",\"test\":\"$CMD\",\"expected\":\"$EXPECTED\",\"actual\":\"$ACTUAL\"}}" >> "$EVENTS_FILE"
          fi
        fi
      fi
    fi
  done < "$SPEC_FILE"
fi

echo ""
echo "--- Results ---"
echo "Passed: $PASS / $TOTAL"
echo "Failed: $FAIL / $TOTAL"

if [ $FAIL -eq 0 ]; then
  echo ""
  echo "✅ Phase $PHASE_NAME VERIFIED"
  echo "{\"ts\":\"$NOW\",\"event\":\"phase_verified\",\"data\":{\"phase\":\"$PHASE_NAME\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$TOTAL}}" >> "$EVENTS_FILE"
  exit 0
else
  echo ""
  echo "❌ Phase $PHASE_NAME FAILED verification"
  echo "{\"ts\":\"$NOW\",\"event\":\"phase_verification_failed\",\"data\":{\"phase\":\"$PHASE_NAME\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$TOTAL}}" >> "$EVENTS_FILE"
  exit 1
fi
