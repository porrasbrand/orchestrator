#!/usr/bin/env bash
# scripts/ai-diagnose.sh — orchestrator P2 Phase A.
# Thin wrapper around scripts/ai-diagnose.js. The Node helper does the heavy
# work (context bundling, ai-consult call, schema validation, file write,
# event append). This script handles arg parsing + sets AI_CONSULT_PATH default.
#
# Usage: scripts/ai-diagnose.sh <phase-dir>
# Exit codes: 0 ok | 1 missing required file / ai-consult failed | 2 schema-validation failed

set -e

PHASE_DIR="${1:?Usage: ai-diagnose.sh <phase-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${AI_CONSULT_PATH:=$HOME/awsc-new/awesome/ai-consult}"
export AI_CONSULT_PATH

node "$SCRIPT_DIR/ai-diagnose.js" "$PHASE_DIR"
