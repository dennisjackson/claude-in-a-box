#!/bin/bash
# Connect to the dev container — starting or creating it if needed.
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WS_FLAG="--workspace-folder $PROJ_DIR"

# Check for a running container
RUNNING=$(docker ps -q --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$RUNNING" ]; then
    exec devcontainer exec $WS_FLAG bash
fi

# Check for a stopped container
STOPPED=$(docker ps -aq --filter "label=devcontainer.local_folder=$PROJ_DIR" 2>/dev/null || true)
if [ -n "$STOPPED" ]; then
    echo "==> Container is stopped — starting..."
    docker start "$STOPPED" >/dev/null
    exec devcontainer exec $WS_FLAG bash
fi

# No container at all — create one
echo "==> No container found — building..."
devcontainer up $WS_FLAG
exec devcontainer exec $WS_FLAG bash
