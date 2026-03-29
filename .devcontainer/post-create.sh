#!/bin/bash
set -euo pipefail

WORKSPACE="/workspaces/nss-dev"
mkdir -p "${WORKSPACE}"

echo "==> Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

echo "==> Verifying tools..."
gcc --version 2>&1 | head -1 || true
clang --version 2>&1 | head -1 || true
ninja --version
git cinnabar --version
weggli --version || true
claude --version

echo "==> Configuring Claude Code..."
mkdir -p ~/.claude

cat > ~/.claude/settings.json << 'SETTINGS'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash",
      "Read",
      "Edit",
      "Write",
      "Glob",
      "Grep",
      "WebFetch",
      "WebSearch",
      "Agent"
    ]
  }
}
SETTINGS

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
    }
  }
}
PREFS

echo "==> Linking CLAUDE.md into workspace..."
ln -sf /workspaces/config/CLAUDE.md "${WORKSPACE}/CLAUDE.md"

echo "==> Fixing volume ownership..."
sudo chown vscode:vscode "${WORKSPACE}/nspr" "${WORKSPACE}/nss"

echo "==> Syncing NSS and NSPR via git-cinnabar into ${WORKSPACE}..."
clone_or_pull() {
    local repo_url="$1" target="$2"
    if [ -d "${target}/.git" ]; then
        echo "    ${target} exists, pulling updates..."
        git -C "${target}" pull --ff-only
    else
        echo "    Cloning ${repo_url}..."
        git clone --depth 1 hg::"${repo_url}" "${target}"
    fi
}

clone_or_pull "https://hg.mozilla.org/projects/nspr" "${WORKSPACE}/nspr" &
clone_or_pull "https://hg.mozilla.org/projects/nss" "${WORKSPACE}/nss" &
wait

echo "==> Done!"
