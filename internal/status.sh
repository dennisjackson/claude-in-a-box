#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Helper: run a command in a container as the vscode user
cexec() { docker exec -u vscode "$1" "$@"; }

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
section "Containers"

# Find all cbx containers
CONTAINER_IDS=$(docker ps -aq --filter "label=cbx.project" 2>/dev/null || true)

if [ -z "$CONTAINER_IDS" ]; then
    err "No containers found"
else
    while IFS= read -r CONTAINER_ID; do
        state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
        project=$(docker inspect -f '{{index .Config.Labels "cbx.project"}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
        project_name=$(basename "$project")

        if [ "$state" = "running" ]; then
            ok "${green}${project_name}${reset}  (${CONTAINER_ID:0:12}, running)"
        else
            err "${project_name}  (${CONTAINER_ID:0:12}, $state)"
        fi

        CREATED=$(docker inspect -f '{{.Created}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
        kv "  Project:" "$project"
        kv "  Created:" "$CREATED"

        if [ "$state" = "running" ]; then
            UPTIME=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
            IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
            kv "  Started:" "$UPTIME"
            kv "  Image:" "$IMAGE"
        fi
        echo ""
    done <<< "$CONTAINER_IDS"
fi

# --- Persistent volumes ------------------------------------------------------
section "Persistent Volumes"

vol="claude-dev-sccache"
info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
if [ -n "$info" ]; then
    ok "$vol  ${dim}(created: $info)${reset}"
else
    warn "$vol  — not found (will be created on first container start)"
fi

# Show sccache stats from a running container (pick the first one)
RUNNING_ID=$(docker ps -q --filter "label=cbx.project" 2>/dev/null | head -1 || true)
if [ -n "$RUNNING_ID" ]; then
    sccache_stats=$(docker exec -u vscode "$RUNNING_ID" sccache --show-stats 2>/dev/null || echo "unavailable")
    if [ "$sccache_stats" != "unavailable" ]; then
        cache_size=$(echo "$sccache_stats" | grep -i "cache size" | head -1 | sed 's/.*: *//' || echo "?")
        hit_rate=$(echo "$sccache_stats" | grep -i "hit rate" | head -1 | sed 's/.*: *//' || true)
        kv "sccache size:" "$cache_size"
        [ -n "$hit_rate" ] && kv "sccache hit rate:" "$hit_rate"
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
    warn ".envrc not found — run internal/setup-envrc.sh"
fi

echo ""
