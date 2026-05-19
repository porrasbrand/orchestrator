#!/usr/bin/env bash
# scripts/ai-diagnose.sh — orchestrator P2 Phase A.
# Thin wrapper around scripts/ai-diagnose.js. The Node helper does the heavy
# work (context bundling, ai-consult call, schema validation, file write,
# event append). This script handles arg parsing + sets AI_CONSULT_PATH default.
#
# Usage: scripts/ai-diagnose.sh [--variant=base|customtools] <phase-dir>
#
# Flags:
#   --variant=base         Use gemini-3.1-pro-preview (default)
#   --variant=customtools  Use gemini-3.1-pro-preview-customtools (A/B benchmark, P2-D)
#
# Exit codes: 0 ok | 1 missing required file / ai-consult failed | 2 schema-validation failed

set -e

VARIANT="base"
POS_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --variant=*) VARIANT="${arg#--variant=}" ;;
    --variant)   echo "ai-diagnose.sh: --variant requires =<value> form, e.g. --variant=customtools" >&2; exit 2 ;;
    *)           POS_ARGS+=("$arg") ;;
  esac
done

PHASE_DIR="${POS_ARGS[0]:?Usage: ai-diagnose.sh [--variant=base|customtools] <phase-dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${AI_CONSULT_PATH:=$HOME/awsc-new/awesome/ai-consult}"
export AI_CONSULT_PATH

case "$VARIANT" in
  base)        AI_DIAGNOSE_MODEL="gemini-3.1-pro-preview" ;;
  customtools) AI_DIAGNOSE_MODEL="gemini-3.1-pro-preview-customtools" ;;
  *)           echo "ai-diagnose.sh: unknown --variant=$VARIANT (expected base|customtools)" >&2; exit 2 ;;
esac
export AI_DIAGNOSE_MODEL

node "$SCRIPT_DIR/ai-diagnose.js" "$PHASE_DIR"
