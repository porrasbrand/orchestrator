#!/bin/bash
# Run smoke tests for a phase and report results
# Usage: ./scripts/verify.sh <worker> <project-path> <phase-dir>
# Example: ./scripts/verify.sh hetzner /home/mp/awesome/blog-publisher .planning/phases/01-publish-history
#
# v2: SSH key auth, timeouts, retry with backoff
# v3: Contextual error messages, failure summary, verification-report.json

set -e

WORKER="${1:?Usage: verify.sh <hetzner|wsl2> <project-path> <phase-dir>}"
PROJECT_PATH="${2:?Missing project path}"
PHASE_DIR="${3:?Missing phase directory}"
SPEC_FILE="$PROJECT_PATH/$PHASE_DIR/spec.md"
EVENTS_FILE="$PROJECT_PATH/.planning/events.jsonl"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PHASE_NAME=$(basename "$PHASE_DIR")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get worker config from registry
SSH_CMD=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" ssh_cmd 2>&1) || {
  echo "❌ $SSH_CMD"
  exit 1
}
REMOTE_BASE=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" base_path 2>&1) || {
  echo "❌ $REMOTE_BASE"
  exit 1
}

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

# Failure tracking arrays (stored as newline-delimited strings for bash compat)
FAILURE_ENTRIES=""    # newline-delimited "TYPE|DETAIL|SUGGESTION" entries
FAILURE_JSON_ITEMS="" # comma-separated JSON objects for verification-report.json

add_failure() {
  local ftype="$1"
  local detail="$2"
  local suggestion="$3"
  local extra_expected="${4:-}"
  local extra_actual="${5:-}"

  # Add to display list
  if [ -n "$FAILURE_ENTRIES" ]; then
    FAILURE_ENTRIES="$FAILURE_ENTRIES
$ftype|$detail|$suggestion"
  else
    FAILURE_ENTRIES="$ftype|$detail|$suggestion"
  fi

  # Build JSON object for report
  local json_obj
  if [ "$ftype" = "smoke_test" ] && [ -n "$extra_expected" ]; then
    json_obj=$(jq -n \
      --arg type "$ftype" \
      --arg test "$detail" \
      --arg expected "$extra_expected" \
      --arg actual "$extra_actual" \
      --arg suggestion "$suggestion" \
      '{type: $type, test: $test, expected: $expected, actual: $actual, suggestion: $suggestion}')
  elif [ "$ftype" = "scope" ]; then
    json_obj=$(jq -n \
      --arg type "$ftype" \
      --arg file "$detail" \
      --arg suggestion "$suggestion" \
      '{type: $type, file: $file, suggestion: $suggestion}')
  else
    json_obj=$(jq -n \
      --arg type "$ftype" \
      --arg detail "$detail" \
      --arg suggestion "$suggestion" \
      '{type: $type, detail: $detail, suggestion: $suggestion}')
  fi

  if [ -n "$FAILURE_JSON_ITEMS" ]; then
    FAILURE_JSON_ITEMS="$FAILURE_JSON_ITEMS,$json_obj"
  else
    FAILURE_JSON_ITEMS="$json_obj"
  fi
}

# Step 1: Check result.md exists
echo "--- Basic Checks ---"
RESULT_MD_FULL_PATH="$REMOTE_BASE/$(basename $PROJECT_PATH)/$PHASE_DIR/result.md"
RESULT_EXISTS=$(ssh_retry "test -f $RESULT_MD_FULL_PATH && echo YES || echo NO")
if [ "$RESULT_EXISTS" = "YES" ]; then
  echo "✅ result.md exists"
  PASS=$((PASS+1))
else
  echo "❌ result.md NOT FOUND at $RESULT_MD_FULL_PATH. Worker must create this file. See templates/result.md for format."
  FAIL=$((FAIL+1))
  add_failure "result_missing" "result.md not found at $RESULT_MD_FULL_PATH" "Worker must create $PHASE_DIR/result.md. See templates/result.md for expected format."
fi
TOTAL=$((TOTAL+1))

# Step 1b: Check result.json (optional, for structured verification)
RESULT_JSON_PATH="$REMOTE_BASE/$(basename $PROJECT_PATH)/$PHASE_DIR/result.json"
RESULT_JSON_EXISTS=$(ssh_retry "test -f $RESULT_JSON_PATH && echo YES || echo NO")
if [ "$RESULT_JSON_EXISTS" = "YES" ]; then
  echo "✅ result.json exists"
  # Parse result.json with jq
  RESULT_JSON=$(ssh_retry "cat $RESULT_JSON_PATH" 2>/dev/null || echo "{}")
  JSON_STATUS=$(echo "$RESULT_JSON" | jq -r '.status // "unknown"' 2>/dev/null || echo "parse_error")
  if [ "$JSON_STATUS" = "parse_error" ]; then
    echo "   ⚠️ result.json exists but is not valid JSON. Re-generate with: jq . < result.json"
    add_failure "json_parse" "result.json is not valid JSON" "Re-generate with: cd $(basename $PROJECT_PATH) && jq . < $PHASE_DIR/result.json"
  else
    JSON_FILES_COUNT=$(echo "$RESULT_JSON" | jq -r '(.files_modified // []) + (.files_created // []) | length' 2>/dev/null || echo "0")
    JSON_TESTS_TOTAL=$(echo "$RESULT_JSON" | jq -r '.tests_run | length' 2>/dev/null || echo "0")
    JSON_TESTS_PASSED=$(echo "$RESULT_JSON" | jq -r '[.tests_run[] | select(.passed == true)] | length' 2>/dev/null || echo "0")
    echo "   Result JSON: status=$JSON_STATUS, $JSON_FILES_COUNT files changed, $JSON_TESTS_PASSED/$JSON_TESTS_TOTAL tests passed"

    # Check for blockers
    BLOCKERS=$(echo "$RESULT_JSON" | jq -r '.blockers[]?' 2>/dev/null)
    if [ -n "$BLOCKERS" ]; then
      echo "   ⚠️  Blockers reported:"
      echo "$BLOCKERS" | while read -r blocker; do
        [ -n "$blocker" ] && echo "      - $blocker"
      done
    fi
  fi
else
  echo "ℹ️  result.json not found (optional, falling back to result.md only)"
fi

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
      echo "⚠️  $file modified but NOT in Expected Files Changed."
      echo "   Fix: Either add to spec's Expected Files Changed, or revert with: git checkout HEAD~1 -- $file"
      SCOPE_WARNINGS=$((SCOPE_WARNINGS+1))
      add_failure "scope" "$file" "Add to Expected Files Changed or revert with: git checkout HEAD~1 -- $file"
    fi
  done <<< "$ACTUAL_FILES"

  echo ""
  echo "Scope warnings: $SCOPE_WARNINGS"
else
  echo "Scope Check: skipped (no Expected Files Changed in spec)"
fi

# Step 1.7: Check for executable smoke-tests.sh
SMOKE_SCRIPT_PATH="$REMOTE_BASE/$(basename $PROJECT_PATH)/$PHASE_DIR/smoke-tests.sh"
SMOKE_SCRIPT_EXISTS=$(ssh_retry "test -x $SMOKE_SCRIPT_PATH && echo YES || echo NO")
USE_SCRIPT_TESTS=0

if [ "$SMOKE_SCRIPT_EXISTS" = "YES" ]; then
  echo ""
  echo "--- Smoke Tests (executable script) ---"
  USE_SCRIPT_TESTS=1

  # Run smoke-tests.sh via SSH
  SMOKE_OUTPUT=$(ssh_retry "cd $REMOTE_BASE/$(basename $PROJECT_PATH) && bash $PHASE_DIR/smoke-tests.sh 2>&1") || SMOKE_EXIT=$?
  SMOKE_EXIT=${SMOKE_EXIT:-0}

  echo "$SMOKE_OUTPUT"

  # Count pass/fail from output
  SCRIPT_PASS=$(echo "$SMOKE_OUTPUT" | grep -c "✅" || echo 0)
  SCRIPT_FAIL=$(echo "$SMOKE_OUTPUT" | grep -c "❌" || echo 0)

  PASS=$((PASS + SCRIPT_PASS))
  FAIL=$((FAIL + SCRIPT_FAIL))
  TOTAL=$((TOTAL + SCRIPT_PASS + SCRIPT_FAIL))

  # Track script-level failures
  if [ "$SCRIPT_FAIL" -gt 0 ]; then
    # Extract individual failure lines from smoke output
    while IFS= read -r fail_line; do
      [ -z "$fail_line" ] && continue
      add_failure "smoke_test" "$fail_line" "Review smoke-tests.sh output above and fix the failing test. Re-run: bash $PHASE_DIR/smoke-tests.sh"
    done <<< "$(echo "$SMOKE_OUTPUT" | grep "❌")"
  fi

  # Log to events
  echo "{\"ts\":\"$NOW\",\"event\":\"smoke_tests_run\",\"data\":{\"phase\":\"$PHASE_NAME\",\"method\":\"script\",\"pass\":$SCRIPT_PASS,\"fail\":$SCRIPT_FAIL,\"exit_code\":$SMOKE_EXIT}}" >> "$EVENTS_FILE"
fi

# Step 2: Extract and run smoke tests from spec.md (skip if script was used)
if [ $USE_SCRIPT_TESTS -eq 0 ]; then
  echo ""
  echo "--- Smoke Tests (markdown) ---"

  # Log method used
  echo "{\"ts\":\"$NOW\",\"event\":\"smoke_tests_run\",\"data\":{\"phase\":\"$PHASE_NAME\",\"method\":\"markdown\"}}" >> "$EVENTS_FILE"
fi

if [ $USE_SCRIPT_TESTS -eq 0 ] && [ -f "$SPEC_FILE" ]; then
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
            echo "❌ Test failed: $CMD"
            echo "   Expected: $EXPECTED"
            echo "   Got:      $ACTUAL"
            echo "   Suggestion: Check if the relevant file was modified correctly. Re-run: $CMD"
            FAIL=$((FAIL+1))
            add_failure "smoke_test" "$CMD" "Check if the relevant file was modified correctly. Re-run: $CMD" "$EXPECTED" "$ACTUAL"
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

# Generate verification-report.json
REPORT_PATH="$PROJECT_PATH/$PHASE_DIR/verification-report.json"
VERIFIED="true"
if [ $FAIL -gt 0 ]; then
  VERIFIED="false"
fi

# Build revision notes string
REVISION_NOTES=""
if [ $FAIL -gt 0 ] && [ -n "$FAILURE_ENTRIES" ]; then
  REVISION_NOTES="Include these in revision spec: "
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    ftype=$(echo "$entry" | cut -d'|' -f1)
    detail=$(echo "$entry" | cut -d'|' -f2)
    if [ "$ftype" = "smoke_test" ]; then
      REVISION_NOTES="${REVISION_NOTES}Smoke test '$detail' failed. "
    elif [ "$ftype" = "scope" ]; then
      REVISION_NOTES="${REVISION_NOTES}File $detail was modified outside spec scope. "
    elif [ "$ftype" = "result_missing" ]; then
      REVISION_NOTES="${REVISION_NOTES}result.md was not created. "
    elif [ "$ftype" = "json_parse" ]; then
      REVISION_NOTES="${REVISION_NOTES}result.json is not valid JSON. "
    fi
  done <<< "$FAILURE_ENTRIES"
fi

# Write verification-report.json using jq
FAILURES_ARRAY="[$FAILURE_JSON_ITEMS]"
jq -n \
  --arg phase "$PHASE_NAME" \
  --argjson verified "$VERIFIED" \
  --arg timestamp "$NOW" \
  --argjson pass "$PASS" \
  --argjson fail "$FAIL" \
  --argjson total "$TOTAL" \
  --argjson failures "$FAILURES_ARRAY" \
  --arg revision_notes "$REVISION_NOTES" \
  '{
    phase: $phase,
    verified: $verified,
    timestamp: $timestamp,
    pass: $pass,
    fail: $fail,
    total: $total,
    failures: $failures,
    revision_notes: $revision_notes
  }' > "$REPORT_PATH"

echo ""
echo "📄 Verification report written to: $REPORT_PATH"

if [ $FAIL -eq 0 ]; then
  echo ""
  echo "✅ Phase $PHASE_NAME VERIFIED"
  echo "{\"ts\":\"$NOW\",\"event\":\"phase_verified\",\"data\":{\"phase\":\"$PHASE_NAME\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$TOTAL}}" >> "$EVENTS_FILE"
  exit 0
else
  # Print Failure Summary
  echo ""
  echo "--- Failure Summary ---"
  echo "FAILED: $FAIL of $TOTAL tests"
  echo ""

  FAILURE_NUM=0
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    FAILURE_NUM=$((FAILURE_NUM+1))
    ftype=$(echo "$entry" | cut -d'|' -f1)
    detail=$(echo "$entry" | cut -d'|' -f2)
    suggestion=$(echo "$entry" | cut -d'|' -f3)

    if [ "$ftype" = "smoke_test" ]; then
      echo "$FAILURE_NUM. [SMOKE_TEST] $detail"
    elif [ "$ftype" = "scope" ]; then
      echo "$FAILURE_NUM. [SCOPE] $detail"
    elif [ "$ftype" = "result_missing" ]; then
      echo "$FAILURE_NUM. [RESULT] $detail"
    elif [ "$ftype" = "json_parse" ]; then
      echo "$FAILURE_NUM. [JSON] $detail"
    else
      echo "$FAILURE_NUM. [$ftype] $detail"
    fi
    echo "   Fix: $suggestion"
    echo ""
  done <<< "$FAILURE_ENTRIES"

  echo "--- Suggested Revision Notes ---"
  echo "Include these in the revision spec's Context section:"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    ftype=$(echo "$entry" | cut -d'|' -f1)
    detail=$(echo "$entry" | cut -d'|' -f2)

    if [ "$ftype" = "smoke_test" ]; then
      echo "- Smoke test \"$detail\" failed"
    elif [ "$ftype" = "scope" ]; then
      echo "- File $detail was modified outside spec scope"
    elif [ "$ftype" = "result_missing" ]; then
      echo "- result.md was not created at expected path"
    elif [ "$ftype" = "json_parse" ]; then
      echo "- result.json is not valid JSON"
    fi
  done <<< "$FAILURE_ENTRIES"

  echo ""
  echo "❌ Phase $PHASE_NAME FAILED verification"
  echo "{\"ts\":\"$NOW\",\"event\":\"phase_verification_failed\",\"data\":{\"phase\":\"$PHASE_NAME\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$TOTAL}}" >> "$EVENTS_FILE"

  # ---- P2 Phase B: AI Diagnostic step ----
  # Supplementary (NEVER blocking). When ai-diagnose.sh is present + executable,
  # invoke it on this failed phase-dir so the orchestrator (or PM) can read the
  # diagnostic before composing the revision spec. Three outcome bands:
  #   exit 0 → diagnostic written; surface path
  #   exit 1 → transient (likely API failure); print warning, proceed
  #   exit 2 → schema fail; warning, raw output preserved, proceed
  # If ai-diagnose.sh is absent/non-executable, skip silently (bare orchestrator
  # installs without ai-consult should still verify normally).
  AI_DIAGNOSE_BIN="$SCRIPT_DIR/ai-diagnose.sh"
  if [ -x "$AI_DIAGNOSE_BIN" ]; then
    echo ""
    echo "--- AI Diagnostic ---"
    AI_DIAG_RC=0
    bash "$AI_DIAGNOSE_BIN" "$PROJECT_PATH/$PHASE_DIR" || AI_DIAG_RC=$?
    case "$AI_DIAG_RC" in
      0)
        LATEST_DIAG=$(ls -1 "$PROJECT_PATH/$PHASE_DIR"/ai-diagnosis-*.json 2>/dev/null | tail -1)
        echo "🤖 AI Diagnostic complete: ${LATEST_DIAG:-(no file written)}"
        ;;
      1)
        echo "⚠️  AI Diagnostic transient failure (exit 1) — proceeding without diagnostic"
        ;;
      2)
        echo "⚠️  AI Diagnostic schema-validation failed (exit 2) — raw output preserved in phase-dir; proceeding"
        ;;
      *)
        echo "⚠️  AI Diagnostic unknown exit code ($AI_DIAG_RC) — proceeding"
        ;;
    esac
  fi

  exit 1
fi
