#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Helper: run a command in the container as the vscode user
cexec() { docker exec -u vscode "$CONTAINER_ID" "$@"; }

# --- Colours & helpers -------------------------------------------------------
bold=$'\033[1m'
dim=$'\033[2m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
cyan=$'\033[36m'
reset=$'\033[0m'

section() { printf '\n%s=== %s ===%s\n' "$bold$cyan" "$1" "$reset"; }
kv()      { printf '  %-24s %s\n' "$1" "$2"; }
warn()    { printf '  %s⚠  %s%s\n' "$yellow" "$1" "$reset"; }
ok()      { printf '  %s✓  %s%s\n' "$green" "$1" "$reset"; }
err()     { printf '  %s✗  %s%s\n' "$red" "$1" "$reset"; }

# --- Container status --------------------------------------------------------
section "Container"

CONTAINER_ID=$(docker ps -q --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)

if [ -z "$CONTAINER_ID" ]; then
    STOPPED_ID=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
    if [ -n "$STOPPED_ID" ]; then
        err "Container exists but is stopped (${STOPPED_ID:0:12})"
        CREATED=$(docker inspect -f '{{.Created}}' "$STOPPED_ID" 2>/dev/null || echo "unknown")
        kv "Created:" "$CREATED"
    else
        err "No container found"
    fi
    CONTAINER_ID=""
else
    ok "Running (${CONTAINER_ID:0:12})"
    CREATED=$(docker inspect -f '{{.Created}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    kv "Created:" "$CREATED"
    kv "Started:" "$UPTIME"
    kv "Image:" "$IMAGE"

    # Show what project is mounted
    PROJECT_MOUNT=$(docker inspect -f '{{ range .Mounts }}{{ if eq .Destination "/workspaces/project" }}{{ .Source }}{{ end }}{{ end }}' "$CONTAINER_ID" 2>/dev/null || true)
    if [ -n "$PROJECT_MOUNT" ]; then
        kv "Project:" "$PROJECT_MOUNT"
    fi
fi

# --- Persistent volumes ------------------------------------------------------
section "Persistent Volumes"

vol="claude-dev-ccache"
info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
if [ -n "$info" ]; then
    ok "$vol  ${dim}(created: $info)${reset}"
else
    warn "$vol  — not found (will be created on first container start)"
fi

# If container is running, show ccache stats
if [ -n "$CONTAINER_ID" ]; then
    ccache_stats=$(cexec env CCACHE_DIR=/.ccache ccache --show-stats 2>/dev/null || echo "unavailable")
    if [ "$ccache_stats" != "unavailable" ]; then
        cache_size=$(echo "$ccache_stats" | grep -i "cache size" | head -1 | sed 's/.*: *//' || echo "?")
        hit_rate=$(echo "$ccache_stats" | grep -i "hit rate" | head -1 | sed 's/.*: *//' || true)
        kv "ccache size:" "$cache_size"
        [ -n "$hit_rate" ] && kv "ccache hit rate:" "$hit_rate"
    fi
fi

# --- Environment --------------------------------------------------------------
section "Environment"

if [ -f "$PROJ_DIR/.envrc" ]; then
    for key in ANTHROPIC_API_KEY; do
        if grep -q "^export $key=" "$PROJ_DIR/.envrc" 2>/dev/null; then
            val=$(grep "^export $key=" "$PROJ_DIR/.envrc" | head -1 | sed 's/^export [^=]*=//' | tr -d '"' | tr -d "'")
            if [ -n "$val" ]; then
                ok "$key is set (${val:0:4}...)"
            else
                warn "$key is empty"
            fi
        else
            warn "$key not found in .envrc"
        fi
    done
else
    warn ".envrc not found — run host-tools/internal/setup-envrc.sh"
fi

echo ""
