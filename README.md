# Claude Dev Container

> **Warning** — Claude Code is, at best, an enthusiastic intern. Treat
> everything it generates as a starting point that requires extensive review
> by someone who understands the code.

A sandboxed dev container for running
[Claude Code](https://docs.anthropic.com/en/docs/claude-code) against
arbitrary project folders. The container provides a full C/C++ build
environment that Claude can explore and modify freely. Source code lives on
the host and is bind-mounted into the container.

## Prerequisites

- Docker
- [Dev Containers CLI](https://github.com/devcontainers/cli)
  (`npm install -g @devcontainers/cli`)
- An [Anthropic API key](https://console.anthropic.com/)

## Workflow

### 1. Set up a project folder

Create a directory with your source code, a `CLAUDE.md` with instructions for
Claude, and optionally a `.claude/commands/` directory with slash commands.

### 2. Connect to the container

```bash
cbx-connect /path/to/my-project
```

Builds a container on first run, then mounts your project folder and drops you
into a shell. Claude Code is pre-installed. The sccache volume is shared across
all containers and persists across rebuilds.

Multiple containers can run simultaneously — just open another terminal and
connect to a different project:

```bash
cbx-connect /path/to/other-project
```

On first run this prompts for your Anthropic API key and writes it to `.envrc`.

### 3. Work inside the container

Run `claude` to start a session. Claude sees your project folder at
`/workspaces/project/`, including the project's CLAUDE.md and any slash
commands you defined.

All changes Claude makes are written directly to your project folder on the
host.

## Host Tools

| Script | Purpose |
|--------|---------|
| `cbx-connect <project-dir>` | Mount a project folder and connect (one container per project). |
| `cbx-nuke` | Destroy all containers and sccache volume. Requires typing "nuke". |
| `cbx-nuke <project-dir>` | Destroy just that project's container. |
| `internal/status.sh` | Report all container states and environment config. |
| `internal/fresh-container.sh <project-dir>` | Tear down and rebuild a project's container. |
| `internal/setup-envrc.sh` | Set up `.envrc` with API key. |

## Container Contents

The container includes Clang 18, GCC 14, sccache, gdb, valgrind, clang-tidy,
clang-format, cppcheck, weggli, semgrep, lcov, diff-cover, AFL++, angr, Z3,
searchfox-cli, git-cinnabar, Rust, uv, tlslite-ng, vim, micro, tmux, and
Claude Code.

### Workspace layout

```
/workspaces/project/     Your project folder (bind-mounted from host)
/.sccache/               Compiler cache (Docker volume, persists across projects)
```

## Security Model

The container is **untrusted**. Claude Code runs inside it with
`CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true` and full network access. All
container output — code, files, instructions — must be reviewed carefully.

### Hardening

- All Linux capabilities dropped except `SYS_PTRACE` (required by ASan).
  Custom seccomp profile; `no-new-privileges` set.
- `.devcontainer` and `container-claude` mounted read-only.
- No Docker socket. Non-root user (`vscode`).
- Only `ANTHROPIC_API_KEY` enters the container.

### Trust boundary

The container boundary is the trust boundary. Anything the container writes
could be the product of prompt injection from attacker-controlled content in
the project's source code or data files.

The **project folder is writable** from inside the container. The container
can modify the CLAUDE.md, slash commands, and any other file in the project.
Review changes before trusting them on the host.

The container also has full outbound network access and could exfiltrate the
API key or fetch malicious payloads.
