#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST_NSS="${REPO_ROOT}/host-nss"

if [ ! -d "${HOST_NSS}/.git" ]; then
    echo "==> host-nss not found — cloning..."
    "${REPO_ROOT}/host-tools/internal/setup-host-nss.sh"
fi

echo "==> Fetching from exchange..."
git -C "${HOST_NSS}" fetch --no-local exchange

# Show what's available
BRANCHES=$(git -C "${HOST_NSS}" branch -r --list 'exchange/*' 2>/dev/null)
if [ -z "${BRANCHES}" ]; then
    echo "No branches in exchange yet."
else
    echo "==> Exchange branches:"
    echo "${BRANCHES}"
    echo ""
    echo "To review a branch:"
    echo "  cd ${HOST_NSS}"
    echo "  git diff HEAD..exchange/<branch>"
    echo ""
    echo "To check out a branch:"
    echo "  cd ${HOST_NSS}"
    echo "  git checkout -b <branch> exchange/<branch>"
fi
