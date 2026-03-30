#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_NSS="${REPO_ROOT}/host-nss"
EXCHANGE="${REPO_ROOT}/.nss-exchange.git"

if [ -d "${HOST_NSS}/.git" ]; then
    echo "host-nss already exists at ${HOST_NSS}"
    exit 0
fi

echo "==> Cloning NSS via git-cinnabar..."
git clone --depth 1 hg::"https://hg.mozilla.org/projects/nss" "${HOST_NSS}"

echo "==> Adding exchange remote..."
git -C "${HOST_NSS}" remote add exchange "${EXCHANGE}"

echo "==> Done! Run host-tools/sync-host-nss.sh to pull exchange branches."
