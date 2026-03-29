#!/bin/bash
set -euo pipefail
devcontainer up --workspace-folder "$(dirname "$0")/.." --remove-existing-container && \
devcontainer exec --workspace-folder "$(dirname "$0")/.." bash
