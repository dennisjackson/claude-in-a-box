# NSS Dev Container

> **Warning — AI-assisted development requires developer judgement.**
> Claude Code is, at best, an enthusiastic intern. Its output should not be
> trusted without review. Even when the tool produces correct results, expert
> judgement nearly always leads to better outcomes than the tool alone. Treat
> everything it generates — code, analysis, suggestions — as a starting point
> that requires verification by an expert.

A sandboxed dev container for working on [Mozilla NSS/NSPR](https://firefox-source-docs.mozilla.org/security/nss/index.html) with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Claude gets a full C/C++ build environment (Clang 18, gyp, ninja, sanitizers) that it can explore and modify freely without touching the host.

## Prerequisites

- Docker
- [Dev Containers CLI](https://github.com/devcontainers/cli) (`npm install -g @devcontainers/cli`) or VS Code with the Dev Containers extension
- An [Anthropic API key](https://console.anthropic.com/)
- (Optional) A [Bugzilla API key](https://bugzilla.mozilla.org/userprefs.cgi?tab=apikey) and [Phabricator Conduit token](https://phabricator.services.mozilla.com/settings/panel/apitokens/) for fetching bug context

## Quick Start

```bash
# 1. Configure API keys (interactive, one-time)
host-tools/setup-envrc.sh
source .envrc

# 2. Fetch a bug to work on
host-tools/bz-fetch.py 2026089

# 3. Start the container (builds on first run)
host-tools/fresh-container.sh

# Or, if the container is already running:
host-tools/connect.sh
```

Inside the container, Claude Code is pre-installed and pre-configured. NSS and NSPR source are cloned on first boot and persist across container rebuilds via Docker volumes.

## What's in the Container

| Tool | Version | Purpose |
|------|---------|---------|
| Clang/LLVM | 18 | Default C/C++ compiler (via ccache) |
| ccache | distro | Compiler cache; persistent volume survives rebuilds |
| GCC | distro | Available as fallback |
| ninja | distro | Build system used by NSS |
| gyp | distro | NSS build file generator |
| git-cinnabar | 0.7.3 | Git frontend for Mozilla's Mercurial repos |
| weggli | latest | Semantic C/C++ code search |
| diff-cover | latest | Coverage analysis focused on changed lines |
| Claude Code | latest | AI coding assistant |

Sanitizer builds (`./build.sh --asan --ubsan`) work out of the box. `CC` and `CXX` are set to `ccache clang` / `ccache clang++` — ccache is transparent to the build system and its cache persists across container rebuilds.

## Directory Layout

```
.devcontainer/          # Dockerfile, devcontainer.json, post-create script
container-claude/       # CLAUDE.md and .claude/ commands for use inside the container
bugs/                   # Bug context fetched from Bugzilla (not in git)
host-tools/             # Scripts that run on the host only
```

Inside the container, the workspace is `/workspaces/nss-dev/`:

```
/workspaces/nss-dev/
├── nss/                # NSS source (Docker volume)
├── nspr/               # NSPR source (Docker volume)
├── .ccache/            # Compiler cache (Docker volume)
├── bugs/               # Bind-mounted from host
├── .claude/            # Bind-mounted from container-claude/
└── CLAUDE.md           # Symlink → .claude/CLAUDE.md
```

## Host Tools

| Script | Description |
|--------|-------------|
| `host-tools/setup-envrc.sh` | Set up `.envrc` with API keys. Use `-f` to overwrite existing values. |
| `host-tools/bz-fetch.py` | Fetch bugs from Bugzilla with comments, attachments, and Phabricator diffs. Accepts multiple bug numbers. |
| `host-tools/connect.sh` | Exec into a running dev container. |
| `host-tools/fresh-container.sh` | Tear down and rebuild the container, then connect. |
| `host-tools/status.sh` | Report container state, persistent volumes, build artifacts, and environment config. |

### Fetching Bugs

```bash
# Single bug
host-tools/bz-fetch.py 2026089

# Multiple bugs
host-tools/bz-fetch.py 2026089 2026090 2026091

# Custom output directory
host-tools/bz-fetch.py 2026089 -o /tmp/bugs
```

Bug data is written as markdown files (`bug.md`, `comments.md`, `attachments/`) so Claude can read them directly. Phabricator revision diffs are fetched automatically if a Conduit token is configured.

## Security Model

The container is an **untrusted environment**. Claude Code runs inside it with full tool permissions and unrestricted network access. Key points:

- **All Linux capabilities are dropped** except `SYS_PTRACE` (needed by ASan). A custom seccomp profile adds only `ptrace` and `personality` to Docker's default allowlist — all other dangerous syscalls stay blocked. Privilege escalation is blocked via `--security-opt=no-new-privileges`.
- `.git` and `.devcontainer` are mounted **read-only** — the container cannot tamper with host repo state.
- The container has **no Docker socket** access and runs as a non-root user.
- `ANTHROPIC_API_KEY` is the only secret passed into the container. Bugzilla and Phabricator tokens stay on the host.
- `container-claude/` and `bugs/` are bind-mounted **read-write** — this is the primary remaining escape vector. Review changes to these directories before trusting them on the host.

See [CLAUDE.md](CLAUDE.md) for the full security model and threat analysis.
