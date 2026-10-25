#!/bin/bash
# Branch management for phase-per-branch workflow
# Usage:
#   branch.sh create <project-path> <phase-name> [worker]
#   branch.sh merge <project-path> <phase-name> [worker]
#   branch.sh list <project-path> [worker]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COMMAND="${1:?Usage: branch.sh <create|merge|list> <project-path> <phase-name> [worker]}"
PROJECT_PATH="${2:?Missing project path}"

# Helper to run git commands (locally or via SSH)
run_git() {
  local worker="$1"
  shift
  local cmd="$@"

  if [ -z "$worker" ]; then
    # Run locally
    (cd "$PROJECT_PATH" && eval "$cmd")
  else
    # Run via SSH
    local ssh_cmd
    ssh_cmd=$(bash "$SCRIPT_DIR/get-worker.sh" "$worker" ssh_cmd 2>&1) || {
      echo "❌ $ssh_cmd" >&2
      exit 1
    }
    local base_path
    base_path=$(bash "$SCRIPT_DIR/get-worker.sh" "$worker" base_path 2>&1) || {
      echo "❌ $base_path" >&2
      exit 1
    }
    local project_name=$(basename "$PROJECT_PATH")
    $ssh_cmd "cd $base_path/$project_name && $cmd"
  fi
}

# Detect main branch name
get_main_branch() {
  local worker="$1"
  local main_branch
  main_branch=$(run_git "$worker" "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo 'master'")
  # Fallback to master if detection fails
  [ -z "$main_branch" ] && main_branch="master"
  echo "$main_branch"
}

case "$COMMAND" in
  create)
    PHASE_NAME="${3:?Missing phase name}"
    WORKER="${4:-}"
    BRANCH_NAME="phase/$PHASE_NAME"
    MAIN_BRANCH=$(get_main_branch "$WORKER")

    # Make sure we're on main branch first
    run_git "$WORKER" "git checkout $MAIN_BRANCH"

    # Pull latest (ignore errors if no remote)
    run_git "$WORKER" "git pull origin $MAIN_BRANCH 2>/dev/null || true"

    # Create and checkout new branch
    run_git "$WORKER" "git checkout -b $BRANCH_NAME"

    echo "✅ Created and checked out branch: $BRANCH_NAME"
    ;;

  merge)
    PHASE_NAME="${3:?Missing phase name}"
    WORKER="${4:-}"
    BRANCH_NAME="phase/$PHASE_NAME"
    MAIN_BRANCH=$(get_main_branch "$WORKER")

    # Check if branch exists
    branch_exists=$(run_git "$WORKER" "git branch --list '$BRANCH_NAME' | wc -l | tr -d ' '")
    if [ "$branch_exists" -eq 0 ]; then
      echo "❌ Error: Branch '$BRANCH_NAME' does not exist" >&2
      exit 1
    fi

    # Checkout main branch
    run_git "$WORKER" "git checkout $MAIN_BRANCH"

    # Pull latest (ignore errors if no remote)
    run_git "$WORKER" "git pull origin $MAIN_BRANCH 2>/dev/null || true"

    # Merge with --no-ff
    if ! run_git "$WORKER" "git merge --no-ff $BRANCH_NAME -m 'Merge $BRANCH_NAME into $MAIN_BRANCH'"; then
      echo "❌ Error: Merge conflict! Resolve manually and try again." >&2
      run_git "$WORKER" "git merge --abort 2>/dev/null || true"
      exit 1
    fi

    # Delete the phase branch
    run_git "$WORKER" "git branch -d $BRANCH_NAME"

    echo "✅ Merged $BRANCH_NAME into $MAIN_BRANCH"
    ;;

  list)
    WORKER="${3:-}"

    echo "Phase branches:"
    branches=$(run_git "$WORKER" "git branch --list 'phase/*'" 2>/dev/null || echo "")
    if [ -z "$branches" ]; then
      echo "  (none)"
    else
      echo "$branches" | while read -r branch; do
        echo "  $branch"
      done
    fi
    ;;

  *)
    echo "❌ Unknown command: $COMMAND" >&2
    echo "Usage: branch.sh <create|merge|list> <project-path> <phase-name> [worker]" >&2
    exit 1
    ;;
esac
