#!/bin/bash
set -euo pipefail
PROJ_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
devcontainer up --workspace-folder "$PROJ_DIR" --remove-existing-container && \
devcontainer exec --workspace-folder "$PROJ_DIR" bash
