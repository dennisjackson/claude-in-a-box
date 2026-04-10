# Claude Dev Container — Host Project

This repo defines a reproducible, sandboxed dev container for running Claude
Code against arbitrary project folders. The container provides a full C/C++
build environment that Claude can explore and modify freely. Source code lives
on the host and is bind-mounted into the container.

## Directory Layout

| Path | Purpose |
|---|---|
| `.devcontainer/` | Dockerfile, devcontainer.json, seccomp profile, post-create script |
| `connect.sh`, `nuke.sh` | Top-level host scripts (connect to container, destroy it) |
| `internal/` | Helper scripts (fresh-container, status, envrc setup) |
| `.envrc` | Anthropic API key (not tracked in git) |

## How It Works

The container is generic — it has the toolchain, Claude Code, and a ccache
volume but no project-specific content. You point `connect.sh` at a **project
folder** on the host and that folder gets bind-mounted read-write into the
container at `/workspaces/project/`.

The project folder should contain whatever the task needs: source code,
CLAUDE.md, `.claude/` commands directory, data files, etc. Claude Code inside
the container will pick up the project's CLAUDE.md and commands automatically.

## Host Tools

- `connect.sh <project-dir>` — mount the given project directory into the dev
  container and connect. Creates the container on first use, recreates it when
  switching projects. Auto-runs envrc setup if `.envrc` is missing.
- `nuke.sh` — destroy the container and ccache volume (requires typing "nuke").
- `internal/fresh-container.sh` — tear down and rebuild the dev container.
- `internal/setup-envrc.sh` — interactively populate `.envrc` with
  `ANTHROPIC_API_KEY`. Triggered automatically by `connect.sh` when `.envrc` is
  missing.
- `internal/status.sh` — report container state, ccache volume, and
  environment config.

## Workflow

1. Set up a project folder on the host with source code, a CLAUDE.md, and
   optionally a `.claude/` commands directory.
2. Connect: `./connect.sh /path/to/my-project`
3. Claude Code is pre-installed and pre-configured inside. It sees the project
   folder contents at `/workspaces/project/`.
4. All changes Claude makes are written directly to the host project folder.

## Security Model

The container is an **untrusted environment**. Claude Code runs inside it with
`CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS=true` and full tool access, so any output
from the container — files, diffs, instructions — must be treated as
potentially compromised.

### Trust boundary

The container boundary is the trust boundary. Anything written by the container
could be the product of prompt injection (e.g. from attacker-controlled content
in source code or data files within the project).

**The project folder is bind-mounted read-write.** The container can modify
anything in it, including the project's CLAUDE.md and `.claude/` commands. If
you run Claude Code on the host, review any changes to project files before
acting on them — they may contain prompt-injection payloads intended to trick
host-side Claude into executing arbitrary commands.

### Container hardening

- **Capability drop** — the container runs with `--cap-drop=ALL
  --cap-add=SYS_PTRACE` and `--security-opt=no-new-privileges`, removing all
  Linux capabilities except `SYS_PTRACE` (required by ASan's stack unwinder)
  and preventing privilege escalation via setuid binaries.
- **Custom seccomp profile** — a custom seccomp profile
  (`.devcontainer/seccomp.json`) extends Docker's default allowlist with
  `ptrace` and `personality` (ADDR_NO_RANDOMIZE) for ASan support. All other
  blocked syscalls (kexec_load, bpf, userfaultfd, etc.) remain blocked.
- **Read-only config mount** — `.devcontainer` is mounted read-only so the
  container cannot tamper with its own build definition.
- **No Docker socket** — the container has no access to the Docker daemon.
- **Non-root user** — the container runs as `vscode`, not root.
- **API key exposure** — `ANTHROPIC_API_KEY` is passed into the container via
  environment variable. The container has unrestricted network access, so treat
  this key as exposed to the container.

### Known residual risks

- The project folder bind mount is read-write, giving the container direct
  write access to the host directory. This is the primary escape vector (via
  write-back of poisoned files).
- The container has full outbound network access and could exfiltrate the API
  key or fetch malicious payloads.

## Maintaining This File

When changing `.devcontainer/Dockerfile`, `devcontainer.json`, or
`post-create.sh`, review this file and update any sections that are affected.
In particular:

- **Directory Layout** — if mounts, paths, or read/write permissions change.
- **Host Tools** — if scripts are added, removed, or renamed.
- **Security Model** — if hardening flags, mounts, capabilities, user config,
  or network access change.
- **Workflow** — if the setup or usage steps change.

## Toolchain

The container ships **Clang 18** (from the official LLVM apt repository) and
defaults to `CC="ccache clang" CXX="ccache clang++"`. The ccache directory is
backed by a named Docker volume (`claude-dev-ccache`) so it persists across
container rebuilds and project switches.

## Design Principles

- **Reproducible** — the container is defined entirely by `.devcontainer/`.
- **Generic** — the container knows nothing about the project; all
  project-specific content (source, CLAUDE.md, commands) comes from the
  mounted project folder.
- **Sandboxed** — Claude operates in the container with full permissions but no
  access to the host filesystem beyond the project folder. The sandbox is **not
  airtight** — see Security Model above.
