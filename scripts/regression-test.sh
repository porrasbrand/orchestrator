#!/bin/bash
# Run regression tests for all completed phases
# Usage: regression-test.sh <project-path> [worker]
#
# Collects smoke tests from all completed phase specs and runs them as one batch

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${1:?Usage: regression-test.sh <project-path> [worker]}"
WORKER="${2:-}"
STATUS_FILE="$PROJECT_PATH/.planning/status.json"

if [ ! -f "$STATUS_FILE" ]; then
  echo "❌ Error: status.json not found at $STATUS_FILE"
  exit 1
fi

# SSH command helper
run_cmd() {
  local cmd="$1"
  if [ -n "$WORKER" ]; then
    local ssh_cmd
    ssh_cmd=$(bash "$SCRIPT_DIR/get-worker.sh" "$WORKER" ssh_cmd 2>&1) || {
      echo "❌ $ssh_cmd" >&2
      return 1
    }
    $ssh_cmd "$cmd" 2>/dev/null
  else
    eval "$cmd" 2>/dev/null
  fi
}

echo "========================================"
echo "Regression Test Suite"
echo "========================================"
echo ""

# Get completed phases
COMPLETED_PHASES=($(jq -r '.phases | to_entries[] | select(.value.status == "complete") | .key' "$STATUS_FILE" | sort))

if [ ${#COMPLETED_PHASES[@]} -eq 0 ]; then
  echo "No completed phases to test."
  exit 0
fi

echo "Found ${#COMPLETED_PHASES[@]} completed phase(s)"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TESTS=0

for phase in "${COMPLETED_PHASES[@]}"; do
  PHASE_DIR="$PROJECT_PATH/.planning/phases/$phase"
  SPEC_FILE="$PHASE_DIR/spec.md"
  SMOKE_SCRIPT="$PHASE_DIR/smoke-tests.sh"

  echo "Phase $phase:"

  PHASE_PASS=0
  PHASE_FAIL=0

  # Check for executable smoke-tests.sh first (priority)
  if [ -x "$SMOKE_SCRIPT" ]; then
    echo "  (running smoke-tests.sh)"
    output=$(bash "$SMOKE_SCRIPT" 2>&1) || true

    # Count pass/fail from output
    pass_count=$(echo "$output" | grep -c "✅" || echo 0)
    fail_count=$(echo "$output" | grep -c "❌" || echo 0)

    PHASE_PASS=$pass_count
    PHASE_FAIL=$fail_count

    # Show summary
    if [ "$fail_count" -gt 0 ]; then
      echo "  ❌ Tests: $pass_count passed, $fail_count failed"
    else
      echo "  ✅ Tests: $pass_count/$pass_count passed"
    fi
  elif [ -f "$SPEC_FILE" ]; then
    # Parse smoke tests from spec.md (same logic as verify.sh)
    IN_SMOKE=0
    test_num=0
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
            test_num=$((test_num+1))
            ACTUAL=$(run_cmd "$CMD" 2>/dev/null || echo "COMMAND_FAILED")

            if echo "$ACTUAL" | grep -q "$EXPECTED"; then
              echo "  ✅ Test $test_num passed"
              PHASE_PASS=$((PHASE_PASS+1))
            else
              echo "  ❌ Test $test_num failed"
              PHASE_FAIL=$((PHASE_FAIL+1))
            fi
          fi
        fi
      fi
    done < "$SPEC_FILE"

    if [ $test_num -eq 0 ]; then
      echo "  (no parseable tests in spec)"
    else
      echo "  Tests: $PHASE_PASS/$test_num passed"
    fi
  else
    echo "  (no spec.md found)"
  fi

  TOTAL_PASS=$((TOTAL_PASS + PHASE_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + PHASE_FAIL))
  TOTAL_TESTS=$((TOTAL_TESTS + PHASE_PASS + PHASE_FAIL))
  echo ""
done

echo "========================================"
echo "Total: $TOTAL_PASS/$TOTAL_TESTS passed"

if [ $TOTAL_FAIL -eq 0 ]; then
  echo "Result: ALL PASS"
  exit 0
else
  echo "Result: $TOTAL_FAIL FAILED"
  exit 1
fi
