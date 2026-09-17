# Claude Dev Container — Host Project

This repo defines a reproducible, sandboxed dev container for running Claude
Code against arbitrary project folders. The container provides a full C/C++
build environment that Claude can explore and modify freely. Source code lives
on the host and is bind-mounted into the container.

## Directory Layout

| Path | Purpose |
|---|---|
| `.devcontainer/` | Dockerfile, devcontainer.json, seccomp profile, post-create script |
| `container-claude/` | CLAUDE.md and settings.json provisioned into the container (read-only) |
| `cbx-connect`, `cbx-nuke` | Top-level host scripts (connect to container, destroy it) |
| `internal/` | Helper scripts (fresh-container, status, envrc setup) |
| `.envrc` | Anthropic API key (not tracked in git) |

## How It Works

The container is generic — it has the toolchain, Claude Code, and a sccache
volume but no project-specific content. You point `cbx-connect` at a **project
folder** on the host and that folder gets bind-mounted read-write into the
container at `/workspaces/project/`.

Multiple containers can run simultaneously for different project folders. Each
project gets its own container, identified by a `cbx.project=<path>` Docker
label. The sccache volume is shared across all containers.

The project folder should contain whatever the task needs: source code,
CLAUDE.md, `.claude/` commands directory, data files, etc. Claude Code inside
the container will pick up the project's CLAUDE.md and commands automatically.

## Host Tools

- `cbx-connect <project-dir>` — mount the given project directory into the dev
  container and connect. Creates a container on first use for each project
  directory. Auto-runs envrc setup if `.envrc` is missing.
- `cbx-nuke` — destroy all cbx containers and the sccache volume (requires
  typing "nuke").
- `cbx-nuke <project-dir>` — destroy only the container for that project
  (keeps sccache and other containers).
- `internal/fresh-container.sh <project-dir>` — tear down and rebuild the
  container for a specific project.
- `internal/setup-envrc.sh` — interactively populate `.envrc` with
  `ANTHROPIC_API_KEY`. Triggered automatically by `cbx-connect` when `.envrc` is
  missing.
- `internal/status.sh` — report all container states, sccache volume, and
  environment config.

## Workflow

1. Set up a project folder on the host with source code, a CLAUDE.md, and
   optionally a `.claude/` commands directory.
2. Connect: `cbx-connect /path/to/my-project`
3. Claude Code is pre-installed and pre-configured inside. It sees the project
   folder contents at `/workspaces/project/`.
4. All changes Claude makes are written directly to the host project folder.
5. To work on another project simultaneously, open a new terminal and run
   `cbx-connect /path/to/other-project`. Each project gets its own container.

## Security Model

The container is an **untrusted environment**. Claude Code runs inside it with
`permissions.defaultMode: "bypassPermissions"` (set in
`container-claude/settings.json`, which is symlinked to
`~/.claude/settings.json` — the user scope, the only non-managed scope that
honors `bypassPermissions`) and full tool access, so any output from the
container — files, diffs, instructions — must be treated as potentially
compromised. `skipDangerousModePermissionPrompt` suppresses the one-time
bypass confirmation dialog. There is no `CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS`
environment variable in Claude Code — an earlier version of this config set
one and it did nothing, which is why the container still prompted for tools
outside the old allowlist.

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
  `ptrace` and `personality` (ADDR_NO_RANDOMIZE) for ASan support, and
  `perf_event_open` for samply. All other blocked syscalls (kexec_load, bpf,
  userfaultfd, etc.) remain blocked. See **perf_event_open** below — it is the
  one exception with real security weight.
- **Read-only config mounts** — `.devcontainer` and `container-claude` are
  mounted read-only so the container cannot tamper with its own build
  definition, CLAUDE.md, or settings.json.
- **No Docker socket** — the container has no access to the Docker daemon.
- **Non-root user** — the container runs as `vscode`, not root.
- **API key exposure** — `ANTHROPIC_API_KEY` is passed into the container via
  environment variable. The container has unrestricted network access, so treat
  this key as exposed to the container.

### perf_event_open and the host's paranoid level

samply needs `perf_event_open`, which Docker's default seccomp profile blocks.
It is allowed in `.devcontainer/seccomp.json`. What the container can then
*do* with it is not decided by seccomp but by the host sysctl
`kernel.perf_event_paranoid`, which is **global and not namespaced** — one
value governs every container on the machine, and the container cannot change
it.

| Value | What the container gets |
|---|---|
| `<= 0` | Samples **any** process on the host and in sibling containers (`pid=-1` / per-CPU events); kernel-space samples leak kernel addresses (KASLR defeat) |
| `1` | Per-process profiling only — exactly what samply needs |
| `>= 2` | User-space samples only; samply records no kernel stacks |

**Keep the host at 1**:

```sh
echo 'kernel.perf_event_paranoid = 1' | sudo tee /etc/sysctl.d/60-cbx-perf.conf
sudo sysctl --system
```

A host at `-1` also ignores the perf mlock limit, so moving to `1` can surface
a ring-buffer size complaint from samply; `kernel.perf_event_mlock_kb=2048`
fixes that if it happens.

`cbx-connect` reads the value on every connect and warns if it is below 1;
`internal/status.sh` reports it. Note that raising a host from `-1` to `1`
also stops host-side system-wide profiling (`perf record -a`, `perf top`)
for unprivileged users — that is the point, but it is a real change to the
host, not only to the container.

Seccomp cannot narrow this usefully: the interesting argument is the
`perf_event_attr` struct behind a pointer, which seccomp cannot dereference.
Filtering on arg 1 (`pid != -1`) is fragile (sign-extension of the `int`) and
would likely break samply's per-CPU event setup.

### Known residual risks

- The project folder bind mount is read-write, giving the container direct
  write access to the host directory. This is the primary escape vector (via
  write-back of poisoned files).
- The container has full outbound network access and could exfiltrate the API
  key or fetch malicious payloads.
- `perf_event_open` is reachable from the container. Independently of the
  paranoid level, the perf subsystem is one of the CVE-richest local
  privilege-escalation paths in the kernel (CVE-2013-2094, CVE-2016-6787,
  CVE-2022-1729) — lowering paranoia reduces what can be observed, not the
  syscall's exploitable surface. This is why Docker blocks it by default; it
  is allowed here as a deliberate trade for samply.

## Keeping Documentation in Sync

Three files document this project and must stay consistent with each other and
with the actual container configuration:

| File | Audience | Purpose |
|---|---|---|
| `CLAUDE.md` (this file) | Host-side Claude / maintainers | Full project documentation |
| `README.md` | Human users | Setup guide and quick reference |
| `container-claude/CLAUDE.md` | Container-side Claude | Environment description and tool inventory |

When changing `.devcontainer/Dockerfile`, `devcontainer.json`,
`post-create.sh`, or `container-claude/`, review **all three files** and update
any sections that are affected. In particular:

- **Directory Layout** — if mounts, paths, or read/write permissions change.
- **Host Tools** — if scripts are added, removed, or renamed.
- **Security Model** — if hardening flags, mounts, capabilities, user config,
  or network access change.
- **Workflow** — if the setup or usage steps change.
- **Installed tools** — if packages are added or removed from the Dockerfile,
  update the tool list in `container-claude/CLAUDE.md` and the Container
  Contents section in `README.md`.

## Toolchain

The container ships **Clang 18** (from the official LLVM apt repository) and
defaults to `CC="sccache clang" CXX="sccache clang++"`, with `RUSTC_WRAPPER`
also set to sccache. CC/CXX were previously left unwrapped on the theory that
projects like Mozilla manage their own sccache wrapping — in practice the cache
logged zero compile requests across full NSS builds, so it is wired in by
default now. Builds that do their own wrapping override CC/CXX anyway. The
sccache directory is backed by a named Docker volume (`claude-dev-sccache`) so
it persists across container rebuilds and project switches.

**Node.js 24** is installed from the official tarball (pinned via
`NODE_VERSION` in the Dockerfile), which provides `node`/`npm`/`npx` and backs
the `profiler-cli` install.

**Python splits into two islands.** The system `python3` is Ubuntu 22.04's
3.10 and stays that way — `./mach` and every `#!/usr/bin/env python3` script
depend on it and on the apt PyYAML. The analysis libraries (angr, z3-solver,
tlslite-ng) need a newer interpreter than the distro has (angr requires
>= 3.12), so they live in a single uv venv at `/opt/venvs/analysis` running a
uv-managed CPython 3.12, exposed as `analysis-python` (plus `angr-python` and
`tlslite-python` aliases). pipx is still used for Python *applications*
(diff-cover, semgrep, sphinx), which is what it is for; libraries meant to be
imported do not belong in a pipx venv, whose site-packages is deliberately
hidden. These are **wrapper scripts, not symlinks** — CPython locates
`pyvenv.cfg` by walking up from the directory of the path it was invoked as,
so a symlink into `/usr/local/bin` bypasses the venv and silently resolves
imports against the base interpreter. Installing the venv at build time also
warms `UV_CACHE_DIR` (`/opt/uv/cache`), so ad-hoc
`uv run --no-project --with angr` inside the container resolves from cache.

**Homebrew sits at the back of `PATH`.** Its watchman dependency tree ships its
own python3, binutils, gfortran and openssl, which shadowed ~70 system binaries
when brew was at the front — `/usr/bin/env python3` lost PyYAML (breaking
`./mach`) and clang linked against brew's rolling `ld` instead of Ubuntu's
binutils. Keep new brew installs to things nothing else provides.

The last layer in the Dockerfile is an **environment-assertion `RUN`** that
re-checks the finished image: no critical binary resolving into the Homebrew
prefix, `import yaml` from the system python3, a real compile/link/ASan-link
through `$CC`/`$CXX` with a non-zero sccache request count, each Python island
(every `*-python` wrapper importing the analysis libraries on a >= 3.12
interpreter, and the sphinx pipx venv), and the expected CLI tools. Per-layer
smoke tests can only prove
a tool worked when it was installed; this one catches later shadowing. Extend
it when adding tools.

## Design Principles

- **Reproducible** — the container is defined entirely by `.devcontainer/`.
- **Generic** — the container knows nothing about the project; all
  project-specific content (source, CLAUDE.md, commands) comes from the
  mounted project folder.
- **Sandboxed** — Claude operates in the container with full permissions but no
  access to the host filesystem beyond the project folder. The sandbox is **not
  airtight** — see Security Model above.
