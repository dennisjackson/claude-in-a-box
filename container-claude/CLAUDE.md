# Container Environment

You are running inside a sandboxed dev container. All your work should be done
in `/workspaces/project/`, which is bind-mounted from the host. Changes you
make there are written directly to the host filesystem.

The project may have its own CLAUDE.md with project-specific instructions.
Follow those instructions.

## Installed Tools

### Compilers & Build
- **Clang 18** (default) -- `CC=clang`, `CXX=clang++`
- **GCC 14** (gcc/g++/gfortran via `update-alternatives`)
- **build-essential**, **CMake**, **Ninja**, **gyp**, **pkg-config**
- **bear** -- generate `compile_commands.json`
- **sccache** -- compiler cache backed by a persistent volume at `/.sccache`

### Debugging & Static Analysis
- **gdb**, **valgrind**
- **clang-tidy**, **cppcheck**, **semgrep**
- **clang-format**
- **weggli** -- semantic C/C++ code search

### Testing & Fuzzing
- **AFL++** -- coverage-guided fuzzer
- **lcov**, **diff-cover** -- code coverage

### Binary & Constraint Analysis
- **angr** -- binary analysis / symbolic execution
- **Z3** -- SMT solver

### Languages
- **Rust** (rustc, cargo)
- **Python 3**, **uv** (fast Python package manager), **Node.js 22**

### Networking
- **tlslite-ng** -- pure-Python TLS implementation

### Source Control & Search
- **git**, **git-cinnabar** (Mercurial repos via git), **Mercurial**
- **searchfox-cli** -- query Mozilla's Searchfox code search

### File Watching
- **watchman** -- filesystem change watcher

### Editors
- **vim**, **micro**

### Terminal
- **tmux** -- terminal multiplexer

### Environment
- **direnv** -- automatic per-directory environment variables
- **Homebrew** -- package manager (Linuxbrew) at `/home/linuxbrew/.linuxbrew/`

## Workspace Layout

```
/workspaces/project/     Your project (bind-mounted from host)
/.sccache/               Compiler cache (persists across container rebuilds)
```
