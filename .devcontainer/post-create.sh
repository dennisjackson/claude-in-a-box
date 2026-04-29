#!/bin/bash
set -euo pipefail

WORKSPACE="/workspaces/project"

echo "==> Configuring Claude Code..."
mkdir -p ~/.claude

# Symlink settings.json and CLAUDE.md from the read-only config mount.
ln -sf /workspaces/config/container-claude/settings.json ~/.claude/settings.json
ln -sf /workspaces/config/container-claude/CLAUDE.md /workspaces/CLAUDE.md

CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "0.0.0")

# Extract the last 20 chars of the API key as the approval suffix
KEY_SUFFIX=""
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    KEY_SUFFIX="${ANTHROPIC_API_KEY: -20}"
fi

cat > ~/.claude.json << PREFS
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "${CLAUDE_VERSION}",
  "hasSeenTasksHint": true,
  "autoUpdates": false,
  "customApiKeyResponses": {
    "approved": ["${KEY_SUFFIX}"],
    "rejected": []
  },
  "projects": {
    "${WORKSPACE}": {
      "allowedTools": [],
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    },
    "/workspaces": {
      "allowedTools": [],
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true
    }
  }
}
PREFS

echo "==> Pre-trusting project .envrc (if present)..."
if [ -f "${WORKSPACE}/.envrc" ]; then
    direnv allow "${WORKSPACE}"
    echo "    direnv: allowed ${WORKSPACE}/.envrc"
else
    echo "    no .envrc found, skipping"
fi

echo "==> Configuring git..."
git config --global worktree.useRelativePaths true

IDENTITY_FILE="${WORKSPACE}/.host-git-identity"
if [ -f "${IDENTITY_FILE}" ]; then
    GIT_NAME="$(sed -n '1p' "${IDENTITY_FILE}")"
    GIT_EMAIL="$(sed -n '2p' "${IDENTITY_FILE}")"
    if [ -n "${GIT_NAME}" ]; then
        git config --global user.name "${GIT_NAME}"
        echo "    user.name = ${GIT_NAME}"
    fi
    if [ -n "${GIT_EMAIL}" ]; then
        git config --global user.email "${GIT_EMAIL}"
        echo "    user.email = ${GIT_EMAIL}"
    fi
else
    echo "    WARNING: ${IDENTITY_FILE} not found — git identity not configured"
fi

echo "==> Done!"
