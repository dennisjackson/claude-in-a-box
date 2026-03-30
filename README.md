# NSS Dev Container

> **Warning** --- Claude Code is, at best, an enthusiastic intern. Treat
> everything it generates as a starting point that requires review by someone
> who understands the code.

A sandboxed dev container for working on
[Mozilla NSS/NSPR](https://firefox-source-docs.mozilla.org/security/nss/index.html)
with [Claude Code](https://docs.anthropic.com/en/docs/claude-code).
Claude gets a full C/C++ build environment it can explore and modify freely
without touching the host.

## Prerequisites

- Docker
- [Dev Containers CLI](https://github.com/devcontainers/cli)
  (`npm install -g @devcontainers/cli`)
- An [Anthropic API key](https://console.anthropic.com/)
- Optional: a [Bugzilla API key](https://bugzilla.mozilla.org/userprefs.cgi?tab=apikey)
  and [Phabricator Conduit token](https://phabricator.services.mozilla.com/settings/panel/apitokens/)
  for fetching bug context

## Workflow

### 1. Fetch a bug

```bash
host-tools/bz-fetch.py 2026089
```

On first run this prompts for API keys and writes them to `.envrc`.
Bug data lands in `bugs/bug-<id>/` as markdown files Claude can read
inside the container.

### 2. Connect to the container

```bash
host-tools/connect.sh
```

Builds the container on first run, starts it if stopped, then drops you
into a shell. Claude Code is pre-installed. NSS and NSPR source are cloned
on first boot and persist across rebuilds via Docker volumes.

### 3. Work inside the container

Run `claude` to start a session. Claude sees the full NSS/NSPR source,
bug data in `bugs/`, and a set of slash commands (`/nss-bugfix`,
`/nss-review`, `/nss-triage`, `/nss-systemize`) that encode common
workflows.

### 4. Extract code

The container's NSS repo has an `exchange` git remote pointing at the
shared bare repo `.nss-exchange.git/`. Claude commits work on a branch;
you fetch and review it on the host.

**Inside the container** (Claude pushes a branch):
```bash
git push exchange bug-1234567-fix-overread
```

**On the host** (you review):
```bash
host-tools/sync-host-nss.sh          # fetches exchange branches
cd host-nss
git diff HEAD..exchange/bug-1234567-fix-overread
```

## Host Tools

| Script | Purpose |
|--------|---------|
| `host-tools/bz-fetch.py <id> [...]` | Fetch Bugzilla bugs with comments, attachments, and Phabricator diffs. |
| `host-tools/connect.sh` | Connect to the container (build/start/exec). |
| `host-tools/sync-host-nss.sh` | Fetch exchange branches into `host-nss/`. Clones NSS on first run. |
| `host-tools/nuke.sh` | Destroy container, volumes, and exchange repo. Requires typing "nuke". |

## Container Contents

Includes everything you need to build NSS, Claude and various related tools (gdb, valgrind, clang-tidy, clang-format, cppcheck, weggli, lcov, diff=cover).

### Workspace layout

```
/workspaces/nss-dev/
  nss/              NSS source (Docker volume)
  nspr/             NSPR source (Docker volume)
  .ccache/          Compiler cache (Docker volume)
  bugs/             Bind-mounted from host
  .claude/          Bind-mounted from container-claude/
  CLAUDE.md         Symlink to .claude/CLAUDE.md
```

### Slash commands

| Command | Purpose |
|---------|---------|
| `/nss-bugfix` | Investigate a bug, develop and test a fix. |
| `/nss-review` | Review a patch (skeptically). |
| `/nss-triage` | Review how a bug might be triggered. |
| `/nss-systemize` | Review if similar bugs exist elsewhere in the codebase. |

## Security Model

The container is **untrusted**. Claude Code runs inside it with
`CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true` and full network access.
All container input, e.g. the `bugs/` folder, and output --- code, files, instructions --- must be reviewed carefully.

### Hardening

- All Linux capabilities dropped except `SYS_PTRACE` (required by ASan).
  Custom seccomp profile; `no-new-privileges` set.
- `.git` and `.devcontainer` mounted read-only.
- No Docker socket. Non-root user (`vscode`).
- Only `ANTHROPIC_API_KEY` enters the container. Bugzilla and Phabricator
  tokens stay on the host.

### Trust boundary

The container boundary is the trust boundary. Anything the container
writes could be the product of prompt injection from attacker-controlled
content in NSS source, bug comments, or Phabricator diffs.

Three host directories are writable from inside the container:

| Directory | Risk |
|-----------|------|
| `container-claude/` | Container can modify the CLAUDE.md and slash commands that Claude reads on next session. Review changes before trusting them on the host. |
| `bugs/` | Container can overwrite fetched bug data and persist analysis results. |
| `.nss-exchange.git/` | Container pushes branches here, used as a remote by `host-nss` |

The container also has full outbound network access and could exfiltrate
the API key or fetch malicious payloads.
