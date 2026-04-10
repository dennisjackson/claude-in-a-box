#!/bin/bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Colours & helpers -------------------------------------------------------
bold=$'\033[1m'
dim=$'\033[2m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
cyan=$'\033[36m'
reset=$'\033[0m'

section() { printf '\n%s=== %s ===%s\n' "$bold$cyan" "$1" "$reset"; }
warn()    { printf '  %s⚠  %s%s\n' "$yellow" "$1" "$reset"; }
ok()      { printf '  %s✓  %s%s\n' "$green" "$1" "$reset"; }
err()     { printf '  %s✗  %s%s\n' "$red" "$1" "$reset"; }

ask_yes_no() {
    local prompt="$1"
    local answer
    printf '  %s [y/N] ' "$prompt"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# --- Inventory what will be destroyed ----------------------------------------
section "The following will be destroyed"

# Container
CONTAINER_ID=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$CONTAINER_ID" ]; then
    state=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_ID" 2>/dev/null || echo "unknown")
    printf '  Container:  %s (%s)\n' "${CONTAINER_ID:0:12}" "$state"
else
    printf '  Container:  %snone found%s\n' "$dim" "$reset"
fi

# ccache volume
vol="claude-dev-ccache"
info=$(docker volume inspect "$vol" --format '{{.CreatedAt}}' 2>/dev/null || true)
if [ -n "$info" ]; then
    printf '  Volume:     %s  %s(created: %s)%s\n' "$vol" "$dim" "$info" "$reset"
else
    printf '  Volume:     %s  %snot found%s\n' "$vol" "$dim" "$reset"
fi

# --- Confirm -----------------------------------------------------------------
echo ""
printf '%s%sThis will permanently delete the container and ccache volume.%s\n' "$bold" "$red" "$reset"
printf 'Type "nuke" to confirm: '
read -r confirm

if [ "$confirm" != "nuke" ]; then
    echo "Aborted."
    exit 1
fi

echo ""

# --- Destroy container -------------------------------------------------------
section "Removing container"

if [ -n "$CONTAINER_ID" ]; then
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1
    ok "Container removed"
else
    ok "No container to remove"
fi

# --- Destroy ccache volume ---------------------------------------------------
section "Removing ccache volume"

if docker volume rm claude-dev-ccache >/dev/null 2>&1; then
    ok "Removed claude-dev-ccache"
else
    ok "claude-dev-ccache already absent"
fi

echo ""
ok "Nuke complete."
echo ""
