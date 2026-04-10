#!/bin/bash
# Connect to the dev container with a project folder mounted.
# Usage: connect.sh <project-dir>
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS_FLAG="--workspace-folder $PROJ_DIR"

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "$0") <project-dir>"
    echo "  Mount the given directory into the dev container and connect."
    exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
export PROJECT_DIR

# Ensure .envrc exists (needed for API keys passed into the container)
if [ ! -f "$PROJ_DIR/.envrc" ]; then
    echo "==> No .envrc found — running setup..."
    "$PROJ_DIR/host-tools/internal/setup-envrc.sh"
fi

# Check for a running container
RUNNING=$(docker ps -q --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$RUNNING" ]; then
    # Verify it's mounted to the right project
    CURRENT_MOUNT=$(docker inspect -f '{{ range .Mounts }}{{ if eq .Destination "/workspaces/project" }}{{ .Source }}{{ end }}{{ end }}' "$RUNNING" 2>/dev/null || true)
    if [ "$CURRENT_MOUNT" = "$PROJECT_DIR" ]; then
        exec devcontainer exec $WS_FLAG bash
    else
        echo "==> Running container is mounted to a different project ($CURRENT_MOUNT)"
        echo "    Stopping it to switch to $PROJECT_DIR..."
        docker rm -f "$RUNNING" >/dev/null
    fi
fi

# Check for a stopped container
STOPPED=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$STOPPED" ]; then
    # Stopped containers can't switch mounts — remove and recreate
    echo "==> Removing stopped container to (re)create with project mount..."
    docker rm -f "$STOPPED" >/dev/null
fi

# No usable container — create one
echo "==> Building container with project: $PROJECT_DIR"
devcontainer up $WS_FLAG
exec devcontainer exec $WS_FLAG bash
