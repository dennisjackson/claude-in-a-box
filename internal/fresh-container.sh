#!/bin/bash
set -euo pipefail
# Tear down and rebuild the container for a specific project.
# Usage: fresh-container.sh <project-dir>

# Resolve symlinks to find real script location (portable — no readlink -f)
SOURCE="$0"
while [ -L "$SOURCE" ]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
PROJ_DIR="$(cd "$(dirname "$SOURCE")/.." && pwd)"

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "$0") <project-dir>"
    exit 1
fi

PROJECT_DIR="$(cd "$1" && pwd)"
export PROJECT_DIR
ID_LABEL="cbx.project=$PROJECT_DIR"
DC_ARGS="--workspace-folder $PROJ_DIR --id-label $ID_LABEL"

devcontainer up $DC_ARGS --remove-existing-container && \
devcontainer exec $DC_ARGS bash
