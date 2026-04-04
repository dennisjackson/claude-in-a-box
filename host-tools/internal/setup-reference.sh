#!/bin/bash
# Populate the reference/ directory with git repos listed in
# reference/sources.txt. This directory is mounted read-only into the dev
# container at /workspaces/nss-dev/reference/.
#
# Usage: host-tools/internal/setup-reference.sh [--force]
#   --force   re-clone repos even if they already exist
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REF_DIR="$PROJ_DIR/reference"
SOURCES="$REF_DIR/sources.txt"

if [[ ! -f "$SOURCES" ]]; then
    echo "ERROR: $SOURCES not found." >&2
    exit 1
fi

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# ── Skip if last sync was recent (< 8 hours) ────────────────────────
STAMP="$REF_DIR/.last-sync"
COOLDOWN=$((8 * 3600))

if ! $FORCE && [[ -f "$STAMP" ]]; then
    last=$(cat "$STAMP")
    now=$(date +%s)
    if (( now - last < COOLDOWN )); then
        echo "==> Reference repos synced $(( (now - last) / 3600 ))h ago; skipping (use --force to override)."
        exit 0
    fi
fi

# ── Clone / update repos ────────────────────────────────────────────
mkdir -p "$REF_DIR/repos"

clone_or_update_repo() {
    local url="$1"
    local name
    name="$(basename "$url" .git)"
    local target="$REF_DIR/repos/$name"

    if [[ -d "$target/.git" ]] && ! $FORCE; then
        echo "  [pull]  $name"
        git -C "$target" fetch --depth 1 origin 2>&1 | sed 's/^/         /'
        git -C "$target" reset --hard FETCH_HEAD 2>&1 | sed 's/^/         /'
        return 0
    fi

    if [[ -d "$target" ]]; then
        echo "  [rm]   $name"
        rm -rf "$target"
    fi

    echo "  [clone] $name  ← $url"
    git clone --depth 1 "$url" "$target" 2>&1 | sed 's/^/         /'
}

echo "==> Syncing reference repos in $REF_DIR/repos/ ..."
while IFS= read -r line; do
    line="${line%%#*}"       # strip comments
    line="${line// /}"       # strip whitespace
    [[ -z "$line" ]] && continue
    clone_or_update_repo "$line" &
done < "$SOURCES"
wait
date +%s > "$STAMP"
echo "    Done."
echo "==> Reference directory ready."
