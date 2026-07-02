#!/usr/bin/env bash
# register-project.sh — track orchestrated projects in $ORCH_STATE_DIR/active-projects.json
#
# Usage:
#   register-project.sh add <project-path> [--name <name>] [--worker hetzner|wsl2] [--remote-path <path>]
#   register-project.sh deactivate <name>
#   register-project.sh list [--json]
#   register-project.sh get <name>

set -euo pipefail

STATE_DIR="${ORCH_STATE_DIR:-$HOME/.orchestrator}"
REGISTRY="$STATE_DIR/active-projects.json"

ensure_state() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR"
        chmod 700 "$STATE_DIR"
    fi
    if [[ ! -f "$REGISTRY" ]]; then
        echo '[]' > "$REGISTRY"
    fi
}

usage() {
    cat >&2 <<'EOF'
Usage:
  register-project.sh add <project-path> [--name <name>] [--worker hetzner|wsl2] [--remote-path <path>]
  register-project.sh deactivate <name>
  register-project.sh list [--json]
  register-project.sh get <name>
EOF
    exit 1
}

# Atomic write: write to tmp, then mv.
atomic_write() {
    local target="$1" content="$2"
    local tmp
    tmp="$(mktemp "${target}.XXXXXX")"
    printf '%s\n' "$content" > "$tmp"
    mv "$tmp" "$target"
}

cmd_add() {
    local project_path="" name="" worker="hetzner" remote_path=""
    project_path="${1:-}"; [[ -z "$project_path" ]] && usage
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)         name="$2"; shift 2 ;;
            --worker)       worker="$2"; shift 2 ;;
            --remote-path)  remote_path="$2"; shift 2 ;;
            *) echo "unknown flag: $1" >&2; usage ;;
        esac
    done
    if [[ "$worker" != "hetzner" && "$worker" != "wsl2" ]]; then
        echo "worker must be hetzner or wsl2 (got: $worker)" >&2
        exit 1
    fi

    local abs_path
    abs_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        echo "project path not found: $project_path" >&2
        exit 1
    }

    if [[ -z "$name" ]]; then
        local status_json="$abs_path/.planning/status.json"
        if [[ -f "$status_json" ]]; then
            name="$(jq -r '.project // empty' "$status_json" 2>/dev/null || true)"
        fi
        if [[ -z "$name" ]]; then
            name="$(basename "$abs_path")"
        fi
    fi
    if [[ -z "$remote_path" ]]; then
        remote_path="\$HOME/awsc-new/awesome/$name"
    fi

    ensure_state
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Preserve registered_at if the entry exists (idempotent update).
    local updated
    updated="$(jq --arg name "$name" \
                   --arg local_path "$abs_path" \
                   --arg worker "$worker" \
                   --arg remote_path "$remote_path" \
                   --arg now "$now" '
        (map(select(.name == $name)) | first // {registered_at: $now}) as $existing
        |
        (map(select(.name != $name))) as $others
        |
        $others + [{
            name: $name,
            local_path: $local_path,
            worker: $worker,
            remote_path: $remote_path,
            active: true,
            registered_at: ($existing.registered_at // $now)
        }]
    ' "$REGISTRY")"
    atomic_write "$REGISTRY" "$updated"

    echo "registered: $name (worker=$worker, path=$abs_path)"
}

cmd_deactivate() {
    local name="${1:-}"; [[ -z "$name" ]] && usage
    ensure_state
    if [[ "$(jq --arg n "$name" 'any(.name == $n)' "$REGISTRY")" != "true" ]]; then
        echo "not found: $name" >&2
        exit 1
    fi
    local updated
    updated="$(jq --arg n "$name" 'map(if .name == $n then .active = false else . end)' "$REGISTRY")"
    atomic_write "$REGISTRY" "$updated"
    echo "deactivated: $name"
}

cmd_list() {
    ensure_state
    if [[ "${1:-}" == "--json" ]]; then
        cat "$REGISTRY"
        return
    fi
    if [[ "$(jq 'length' "$REGISTRY")" == "0" ]]; then
        echo "(no registered projects)"
        return
    fi
    printf '%-30s %-8s %-6s %s\n' "NAME" "WORKER" "ACTIVE" "LOCAL_PATH"
    jq -r '.[] | [.name, .worker, (.active|tostring), .local_path] | @tsv' "$REGISTRY" \
        | while IFS=$'\t' read -r n w a p; do
            printf '%-30s %-8s %-6s %s\n' "$n" "$w" "$a" "$p"
        done
}

cmd_get() {
    local name="${1:-}"; [[ -z "$name" ]] && usage
    ensure_state
    local entry
    entry="$(jq --arg n "$name" 'map(select(.name == $n)) | first // empty' "$REGISTRY")"
    if [[ -z "$entry" ]]; then
        echo "not found: $name" >&2
        exit 1
    fi
    printf '%s\n' "$entry"
}

[[ $# -lt 1 ]] && usage
sub="$1"; shift
case "$sub" in
    add)        cmd_add "$@" ;;
    deactivate) cmd_deactivate "$@" ;;
    list)       cmd_list "$@" ;;
    get)        cmd_get "$@" ;;
    -h|--help)  usage ;;
    *) echo "unknown subcommand: $sub" >&2; usage ;;
esac
