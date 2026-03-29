#!/bin/bash
set -euo pipefail
devcontainer exec --workspace-folder "$(dirname "$0")/.." bash
